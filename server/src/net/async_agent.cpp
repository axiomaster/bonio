#include "hiclaw/net/async_agent.hpp"
#include "hiclaw/agent/agent.hpp"
#include "hiclaw/observability/log.hpp"
#include "hiclaw/tools/tool.hpp"
#include <nlohmann/json.hpp>
#include <sstream>
#include <random>
#include <chrono>
#include <future>

namespace hiclaw {
namespace net {

namespace {

std::string generate_run_id() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<uint64_t> dist(0, UINT64_MAX);
  std::ostringstream oss;
  oss << "run_" << std::hex << dist(gen) << "_" << std::chrono::steady_clock::now().time_since_epoch().count();
  return oss.str();
}

std::vector<types::Message> session_messages_to_history(
    const std::vector<session::Message>& msgs) {
  std::vector<types::Message> history;
  for (const auto& m : msgs) {
    if (m.role == "user" || m.role == "assistant" || m.role == "system") {
      history.push_back({m.role, m.content});
    }
  }
  return history;
}

}  // namespace

AsyncAgentManager::AsyncAgentManager(const config::Config& config, EventCallback callback,
                                     std::shared_ptr<session::SessionStore> session_store,
                                     std::shared_ptr<ToolRouter> tool_router)
    : config_(config), event_callback_(std::move(callback)),
      session_store_(std::move(session_store)),
      tool_router_(std::move(tool_router)) {}

AsyncAgentManager::~AsyncAgentManager() {
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    for (auto& kv : tasks_) {
      kv.second->aborted = true;
    }
  }
  std::vector<std::thread> workers;
  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    for (auto& kv : tasks_) {
      if (kv.second->worker.joinable()) {
        workers.push_back(std::move(kv.second->worker));
      }
    }
    tasks_.clear();
  }
  for (auto& w : workers) {
    if (w.joinable()) {
      w.join();
    }
  }
}

std::string AsyncAgentManager::start_task(const std::string& session_key, const std::string& message) {
  auto task = std::make_shared<AsyncTask>();
  task->run_id = generate_run_id();
  task->session_key = session_key;
  task->message = message;

  std::string run_id = task->run_id;

  {
    std::lock_guard<std::mutex> lock(tasks_mutex_);
    tasks_[run_id] = task;
  }

  task->worker = std::thread(&AsyncAgentManager::run_task, this, task);

  return run_id;
}

bool AsyncAgentManager::abort_task(const std::string& run_id) {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  auto it = tasks_.find(run_id);
  if (it != tasks_.end()) {
    it->second->aborted = true;
    return true;
  }
  return false;
}

bool AsyncAgentManager::has_task(const std::string& run_id) const {
  std::lock_guard<std::mutex> lock(tasks_mutex_);
  return tasks_.find(run_id) != tasks_.end();
}

void AsyncAgentManager::run_task(std::shared_ptr<AsyncTask> task) {
  try {
    log::info("async_agent: starting task " + task->run_id);

    // Send start event
    nlohmann::json start_payload;
    start_payload["sessionKey"] = task->session_key;
    start_payload["runId"] = task->run_id;
    start_payload["state"] = "started";
    send_event("chat", start_payload.dump());

    // Load conversation history from session store
    std::vector<types::Message> history;
    if (session_store_) {
      auto session_msgs = session_store_->get_messages(task->session_key, 128);
      history = session_messages_to_history(session_msgs);
      // Remove the last message if it's the same user message we're about to send
      // (it was already saved by the gateway before starting the task)
      if (!history.empty() && history.back().role == "user" &&
          history.back().content == task->message) {
        history.pop_back();
      }
    }

    std::string session_key_copy = task->session_key;
    std::string run_id_copy = task->run_id;

    // Text streaming callback: emit both "chat" delta and "agent" assistant events
    auto stream_callback = [this, &session_key_copy, &run_id_copy, &task](const std::string& delta_text) {
      if (task->aborted) return;

      // chat event with state: "delta" (expected by Android client)
      nlohmann::json chat_delta;
      chat_delta["sessionKey"] = session_key_copy;
      chat_delta["runId"] = run_id_copy;
      chat_delta["state"] = "delta";
      chat_delta["message"] = {
        {"role", "assistant"},
        {"content", nlohmann::json::array({{{"type", "text"}, {"text", delta_text}}})}
      };
      send_event("chat", chat_delta.dump());

      // agent event with stream: "assistant" (for additional consumers)
      nlohmann::json agent_payload;
      agent_payload["sessionKey"] = session_key_copy;
      agent_payload["stream"] = "assistant";
      agent_payload["message"] = {
        {"role", "assistant"},
        {"content", nlohmann::json::array({{{"type", "text"}, {"text", delta_text}}})}
      };
      send_event("agent", agent_payload.dump());
    };

    // Tool call callback — only emits agent UI events (tool progress/start).
    // node.invoke.request for remote tools is sent by remote_executor, not here.
    auto tool_callback = [this, &session_key_copy, &task](const agent::ToolCallEvent& event) {
      if (task->aborted) return;

      nlohmann::json agent_payload;
      agent_payload["sessionKey"] = session_key_copy;
      agent_payload["stream"] = "tool";
      agent_payload["data"] = {
        {"phase", event.is_complete ? "start" : "progress"},
        {"name", event.name},
        {"toolCallId", event.id}
      };
      if (!event.arguments.empty()) {
        try {
          agent_payload["data"]["args"] = nlohmann::json::parse(event.arguments);
        } catch (const nlohmann::json::parse_error&) {
          agent_payload["data"]["args"] = event.arguments;
        }
      }
      send_event("agent", agent_payload.dump());
    };

    // Remote tool executor: dispatches tool calls to the client via ToolRouter
    agent::RemoteToolExecutor remote_executor = nullptr;
    if (tool_router_) {
      auto tr = tool_router_;
      auto event_cb = [this](const std::string& name, const std::string& payload) {
        send_event(name, payload);
      };
      remote_executor = [tr, event_cb, &task](
          const std::string& tool_call_id,
          const std::string& tool_name,
          const std::string& args_json) -> types::ToolResult {

        auto future = tr->register_tool_call(tool_call_id);

        // Send node.invoke.request to client
        nlohmann::json invoke_payload;
        invoke_payload["id"] = "invoke_" + tool_call_id;
        invoke_payload["nodeId"] = "server";
        invoke_payload["command"] = tool_name;
        invoke_payload["timeoutMs"] = 30000;
        if (!args_json.empty()) {
          try {
            invoke_payload["params"] = nlohmann::json::parse(args_json);
          } catch (...) {
            invoke_payload["params"] = nlohmann::json::object();
          }
        } else {
          invoke_payload["params"] = nlohmann::json::object();
        }
        event_cb("node.invoke.request", invoke_payload.dump());

        log::info("async_agent: waiting for remote tool result: " + tool_name + " id=" + tool_call_id);

        // Wait for result with timeout
        auto status = future.wait_for(std::chrono::seconds(30));
        if (status == std::future_status::timeout) {
          tr->cancel_all();
          log::warn("async_agent: remote tool timeout: " + tool_name);
          return types::ToolResult{false, "", "Remote tool call timed out after 30 seconds"};
        }

        try {
          auto result = future.get();
          return types::ToolResult{result.success, result.output, result.error};
        } catch (const std::exception& e) {
          return types::ToolResult{false, "", std::string("Remote tool error: ") + e.what()};
        }
      };
    }

    // Execute multi-turn streaming agent with history and tool loop
    agent::RunResult result;
    if (!task->aborted) {
      result = agent::run_streaming_with_history(
          config_, history, task->message, 0.7,
          stream_callback, tool_callback, &task->aborted, 5, remote_executor);
    }

    // Save assistant response to session store
    if (session_store_ && result.ok && !result.content.empty() && !task->aborted) {
      session::Message ast_msg;
      ast_msg.role = "assistant";
      ast_msg.content = result.content;
      ast_msg.timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::system_clock::now().time_since_epoch()).count();
      ast_msg.run_id = task->run_id;
      session_store_->add_message(task->session_key, ast_msg);
    }

    // Send completion event with message field for client fallback
    nlohmann::json final_payload;
    final_payload["sessionKey"] = task->session_key;
    final_payload["runId"] = task->run_id;
    final_payload["state"] = task->aborted ? "aborted" : (result.ok ? "final" : "error");
    if (!result.ok && !task->aborted) {
      final_payload["errorMessage"] = result.error;
    } else if (!task->aborted && !result.content.empty()) {
      final_payload["message"] = result.content;
    }
    send_event("chat", final_payload.dump());

    // Cleanup task
    {
      std::lock_guard<std::mutex> lock(tasks_mutex_);
      tasks_.erase(task->run_id);
    }

    if (task->worker.joinable()) {
      task->worker.detach();
    }

    log::info("async_agent: completed task " + task->run_id);

  } catch (const std::exception& e) {
    log::error("async_agent: task " + task->run_id + " failed with exception: " + e.what());

    nlohmann::json error_payload;
    error_payload["sessionKey"] = task->session_key;
    error_payload["runId"] = task->run_id;
    error_payload["state"] = "error";
    error_payload["errorMessage"] = e.what();
    send_event("chat", error_payload.dump());

    {
      std::lock_guard<std::mutex> lock(tasks_mutex_);
      tasks_.erase(task->run_id);
    }

    if (task->worker.joinable()) {
      task->worker.detach();
    }
  }
}

void AsyncAgentManager::send_event(const std::string& event_name, const std::string& payload_json) {
  if (event_callback_) {
    event_callback_(event_name, payload_json);
  }
}

}  // namespace net
}  // namespace hiclaw
