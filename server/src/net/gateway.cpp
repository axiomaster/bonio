#include "hiclaw/agent/agent.hpp"
#include "hiclaw/config/config.hpp"
#include "hiclaw/net/async_agent.hpp"
#include "hiclaw/net/gateway.hpp"
#include "hiclaw/net/tool_router.hpp"
#include "hiclaw/observability/log.hpp"
#include "hiclaw/session/store.hpp"
#include "hiclaw/skills/skill_manager.hpp"

#ifdef _WIN32
#undef min
#undef max
#endif
#include <nlohmann/json.hpp>
#include <atomic>
#include <chrono>
#include <cstring>
#include <deque>
#include <iostream>
#include <random>
#include <sstream>
#include <vector>

#if defined(HICLAW_USE_LIBWEBSOCKETS) && HICLAW_USE_LIBWEBSOCKETS
#include <libwebsockets.h>
#endif

#if defined(HICLAW_USE_WEBSOCKETPP) && HICLAW_USE_WEBSOCKETPP
#include <websocketpp/config/asio_no_tls.hpp>
#include <websocketpp/server.hpp>
#endif

namespace hiclaw {
namespace net {

namespace {

using json = nlohmann::json;

static std::string get_string(const json& j, const char* key) {
  if (!j.contains(key) || !j[key].is_string()) return "";
  return j[key].get<std::string>();
}

/// Shared protocol: handle one client frame, return response and update connected.
std::string gateway_handle_frame(const std::string& frame,
                                 const config::Config& config,
                                 const std::string& pairing_code,
                                 bool& connected) {
  std::string method, id, message;
  try {
    json j = json::parse(frame);
    method = get_string(j, "method");
    id = get_string(j, "id");
    if (j.contains("params") && j["params"].is_object()) {
      message = get_string(j["params"], "message");
      if (message.empty()) message = get_string(j["params"], "content");
    }
    if (message.empty()) message = get_string(j, "content");
  } catch (const json::parse_error&) {
    json err;
    err["type"] = "res";
    err["id"] = "";
    err["ok"] = false;
    err["error"] = {{"code", "BAD_REQUEST"}, {"message", "invalid JSON"}};
    return err.dump();
  }

  if (method == "connect") {
    bool auth_ok = pairing_code.empty();
    if (!auth_ok) {
      try {
        json j = json::parse(frame);
        if (j.contains("params") && j["params"].is_object()) {
          std::string pw = get_string(j["params"], "password");
          if (pw == pairing_code) auth_ok = true;
          if (!auth_ok) { std::string tok = get_string(j["params"], "token"); if (tok == pairing_code) auth_ok = true; }
        }
      } catch (const json::parse_error&) {}
    }
    connected = auth_ok;
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = auth_ok;
    if (auth_ok) {
      res["payload"] = {{"server", {{"host", "hiclaw"}}}, {"snapshot", {{"sessionDefaults", {{"mainSessionKey", "main"}}}}}};
    } else {
      res["error"] = {{"code", "AUTH_FAILED"}, {"message", "Invalid pairing code or token"}};
    }
    return res.dump();
  }

  if (method == "health") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"status", "ok"}};
    return res.dump();
  }

  if (!connected) {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = false;
    res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
    return res.dump();
  }

  if (method == "config.get") {
    // Build models array
    json models_arr = json::array();
    for (const auto& m : config.models) {
      json mj;
      mj["id"] = m.id;
      mj["provider"] = m.provider;
      if (!m.base_url.empty()) mj["base_url"] = m.base_url;
      mj["model_id"] = m.model_id.empty() ? m.id : m.model_id;
      if (!m.api_key_env.empty()) mj["api_key_env"] = m.api_key_env;
      if (!m.api_key.empty()) mj["api_key"] = m.api_key;
      models_arr.push_back(std::move(mj));
    }

    // Build providers array from built-in registry
    auto registry = config::load_provider_registry(config.config_dir);
    json providers_arr = json::array();
    for (const auto& kv : registry) {
      const auto& p = kv.second;
      json pj;
      pj["id"] = p.id;
      pj["display_name"] = p.display_name;
      pj["requires_api_key"] = !p.default_api_key_env.empty();
      pj["default_base_url"] = p.default_base_url;
      providers_arr.push_back(std::move(pj));
    }

    // Build gateway config
    json gateway_obj;
    gateway_obj["port"] = config.gateway.port;
    gateway_obj["host"] = config.gateway.host;
    gateway_obj["enabled"] = config.gateway.enabled;

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {
      {"default_model", config.default_model},
      {"models", models_arr},
      {"gateway", gateway_obj},
      {"providers", providers_arr}
    };
    if (!config.system_prompt.empty()) {
      res["payload"]["system_prompt"] = config.system_prompt;
    }
    return res.dump();
  }

  // 静态变量存储语音唤醒状态（简化实现）
  static std::atomic<bool> voicewake_enabled{false};

  if (method == "voicewake.get") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"enabled", voicewake_enabled.load()}};
    return res.dump();
  }

  if (method == "voicewake.set") {
    bool has_enabled = false;
    bool new_enabled = false;
    try {
      json j = json::parse(frame);
      if (j.contains("params") && j["params"].is_object()) {
        if (j["params"].contains("enabled")) {
          new_enabled = j["params"]["enabled"].get<bool>();
          has_enabled = true;
        }
      }
    } catch (const std::exception& e) {
      log::info("voicewake.set: parse error: " + std::string(e.what()));
    }

    if (!has_enabled) {
      json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = false;
      res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing enabled parameter"}};
      return res.dump();
    }

    voicewake_enabled.store(new_enabled);

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"enabled", voicewake_enabled.load()}};
    return res.dump();
  }

  if (method == "agent.run" || method == "chat.run" || method == "chat.send") {
    if (message.empty()) {
      json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = false;
      res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing message"}};
      return res.dump();
    }
    log::info("gateway: agent.run message=" + message.substr(0, 60) + (message.size() > 60 ? "..." : ""));
    agent::RunResult result = agent::run(config, message, 0.7);
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = result.ok;
    if (result.ok) {
      res["payload"] = {{"content", result.content}, {"full_response", result.content}};
    } else {
      res["error"] = {{"code", "AGENT_ERROR"}, {"message", result.error}};
    }
    return res.dump();
  }
  if (method == "chat.history") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"messages", json::array()}, {"sessionId", "main"}};
    return res.dump();
  }
  if (method == "sessions.list") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"sessions", json::array({json::object({{"key", "main"}, {"updatedAt", 0}, {"displayName", "Main"}})})}};
    return res.dump();
  }

  // Note: config.set is handled in websocketpp message handler directly (non-const config)
  if (method == "config.set") {
    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = false;
    res["error"] = {{"code", "INTERNAL_ERROR"}, {"message", "config.set must be handled in wspp handler"}};
    return res.dump();
  }

  if (method == "node.event") {
    // 客户端主动发送事件，记录日志
    log::info("gateway: received node.event: " + frame.substr(0, (std::min)(frame.length(), size_t(200))));

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"received", true}};
    return res.dump();
  }

  if (method == "node.invoke.result") {
    // 客户端返回 Tool Call 执行结果
    std::string tool_call_id;
    try {
      json j = json::parse(frame);
      if (j.contains("params") && j["params"].is_object()) {
        if (j["params"].contains("toolCallId")) {
          tool_call_id = j["params"]["toolCallId"].get<std::string>();
        }
      }
    } catch (...) {}

    log::info("gateway: received node.invoke.result for toolCallId=" + tool_call_id);

    json res;
    res["type"] = "res";
    res["id"] = id;
    res["ok"] = true;
    res["payload"] = {{"received", true}};
    return res.dump();
  }

  json res;
  res["type"] = "res";
  res["id"] = id;
  res["ok"] = false;
  res["error"] = {{"code", "UNKNOWN_METHOD"}, {"message", "method not supported"}};
  return res.dump();
}

}  // namespace

std::string gateway_generate_pairing_code() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<int> dist(0, 9);
  std::string code;
  for (int i = 0; i < 6; ++i) code += static_cast<char>('0' + dist(gen));
  return code;
}

// -----------------------------------------------------------------------------
// websocketpp backend (preferred on HarmonyOS)
// -----------------------------------------------------------------------------
#if defined(HICLAW_USE_WEBSOCKETPP) && HICLAW_USE_WEBSOCKETPP

#include <map>
#include <memory>

namespace {

typedef websocketpp::server<websocketpp::config::asio> ws_server_t;

struct WsppSession {
  bool connected = false;
  std::unique_ptr<AsyncAgentManager> agent_manager;
  std::shared_ptr<ToolRouter> tool_router;
  std::shared_ptr<session::SessionStore> session_store;
};

void run_wspp_server(int port, config::Config& config, const std::string& pairing_code) {
  ws_server_t server;
  server.set_reuse_addr(true);
  server.init_asio();

  // Per-connection session (connection_hdl as key; no set_user_data in default asio config)
  std::map<websocketpp::connection_hdl, WsppSession, std::owner_less<websocketpp::connection_hdl>> sessions;

  server.set_open_handler([&server, &sessions, &config, &pairing_code](websocketpp::connection_hdl hdl) {
    sessions[hdl] = WsppSession();
    sessions[hdl].connected = false;
    sessions[hdl].tool_router = std::make_shared<ToolRouter>();
    sessions[hdl].session_store = std::make_shared<session::SessionStore>(config.config_dir);

    // 创建事件推送回调 - 使用 io_service.post 确保线程安全
    auto event_callback = [&server, hdl, &sessions](const std::string& event_name, const std::string& payload) {
      nlohmann::json ev;
      ev["type"] = "event";
      ev["event"] = event_name;
      try {
        ev["payload"] = nlohmann::json::parse(payload);
      } catch (...) {
        ev["payload"] = payload;
      }
      std::string msg = ev.dump();

      // 使用 post 将发送操作调度到 IO 线程
      server.get_io_service().post([&server, hdl, msg = std::move(msg)]() {
        try {
          // 检查连接是否仍然有效
          if (!hdl.expired()) {
            server.send(hdl, msg, websocketpp::frame::opcode::text);
          }
        } catch (const std::exception&) {
          // 静默处理发送错误（连接可能已关闭）
        }
      });
    };

    sessions[hdl].agent_manager = std::make_unique<AsyncAgentManager>(config, event_callback, sessions[hdl].session_store, sessions[hdl].tool_router);

    // 发送 connect.challenge
    std::string nonce = "hiclaw-nonce-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    nlohmann::json ev;
    ev["type"] = "event";
    ev["event"] = "connect.challenge";
    ev["payload"] = {{"nonce", nonce}};
    std::string msg = ev.dump();
    try {
      server.send(hdl, msg, websocketpp::frame::opcode::text);
    } catch (...) {}
  });

  server.set_message_handler([&server, &sessions, &config, &pairing_code](websocketpp::connection_hdl hdl, ws_server_t::message_ptr msg) {
    if (!msg || msg->get_opcode() != websocketpp::frame::opcode::text) return;
    std::string payload = msg->get_payload();
    auto it = sessions.find(hdl);
    if (it == sessions.end()) return;

    // 先解析 method 判断是否是 chat.send 或 chat.abort
    std::string method;
    std::string id;
    try {
      nlohmann::json j = nlohmann::json::parse(payload);
      method = get_string(j, "method");
      id = get_string(j, "id");
    } catch (const nlohmann::json::parse_error&) {
      nlohmann::json err;
      err["type"] = "res";
      err["id"] = "";
      err["ok"] = false;
      err["error"] = {{"code", "BAD_REQUEST"}, {"message", "invalid JSON"}};
      try {
        server.send(hdl, err.dump(), websocketpp::frame::opcode::text);
      } catch (...) {}
      return;
    }

    // 处理 chat.send 和 chat.abort（需要 agent_manager）
    if (method == "chat.send" || method == "chat.abort") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      if (!it->second.agent_manager) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "INTERNAL_ERROR"}, {"message", "agent manager not initialized"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      if (method == "chat.send") {
        // 解析参数
        std::string message;
        std::string session_key = "main";
        try {
          nlohmann::json j = nlohmann::json::parse(payload);
          if (j.contains("params") && j["params"].is_object()) {
            message = get_string(j["params"], "message");
            if (message.empty()) message = get_string(j["params"], "content");
            session_key = get_string(j["params"], "sessionKey");
            if (session_key.empty()) session_key = "main";
          }
        } catch (...) {}

        if (message.empty()) {
          nlohmann::json res;
          res["type"] = "res";
          res["id"] = id;
          res["ok"] = false;
          res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing message"}};
          try {
            server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
          } catch (...) {}
          return;
        }

        // Save user message to session store
        if (it->second.session_store) {
          session::Message user_msg;
          user_msg.role = "user";
          user_msg.content = message;
          user_msg.timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
              std::chrono::system_clock::now().time_since_epoch()).count();
          it->second.session_store->add_message(session_key, user_msg);
        }

        std::string run_id = it->second.agent_manager->start_task(session_key, message);
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = true;
        res["payload"] = {{"runId", run_id}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      if (method == "chat.abort") {
        std::string run_id;
        try {
          nlohmann::json j = nlohmann::json::parse(payload);
          if (j.contains("params") && j["params"].is_object()) {
            run_id = get_string(j["params"], "runId");
          }
        } catch (...) {}

        if (run_id.empty()) {
          nlohmann::json res;
          res["type"] = "res";
          res["id"] = id;
          res["ok"] = false;
          res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing runId"}};
          try {
            server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
          } catch (...) {}
          return;
        }

        bool aborted = it->second.agent_manager->abort_task(run_id);
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = aborted;
        if (!aborted) {
          res["error"] = {{"code", "NOT_FOUND"}, {"message", "task not found or already completed"}};
        }
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }
    }

    // 处理 node.invoke.result（客户端返回工具调用结果）
    if (method == "node.invoke.result") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      std::string tool_call_id;
      bool success = true;
      std::string output;
      std::string error;

      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          auto& params = j["params"];
          // Extract toolCallId from id field (format: invoke_xxx -> xxx)
          std::string invoke_id = get_string(params, "id");
          if (invoke_id.rfind("invoke_", 0) == 0) {
            tool_call_id = invoke_id.substr(7);  // Remove "invoke_" prefix
          } else {
            tool_call_id = invoke_id;
          }
          if (params.contains("ok")) {
            success = params["ok"].get<bool>();
          }
          if (params.contains("result")) {
            output = params["result"].dump();
          }
          if (params.contains("error")) {
            if (params["error"].is_string()) {
              error = params["error"].get<std::string>();
            } else {
              error = params["error"].dump();
            }
          }
        }
      } catch (...) {}

      log::info("gateway: node.invoke.result toolCallId=" + tool_call_id + " success=" + (success ? "true" : "false"));

      // Route to ToolRouter if available
      if (it->second.tool_router && !tool_call_id.empty()) {
        ToolResult result;
        result.success = success;
        result.output = output;
        result.error = error;
        bool routed = it->second.tool_router->complete_tool_call(tool_call_id, result);
        log::info("gateway: tool_router routing " + std::string(routed ? "succeeded" : "failed"));
      }

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = true;
      res["payload"] = {{"received", true}};
      try {
        server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
      } catch (...) {}
      return;
    }

    // 处理 chat.history（返回真实会话历史）
    if (method == "chat.history") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      std::string session_key = "main";
      int limit = 0;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          session_key = get_string(j["params"], "sessionKey");
          if (session_key.empty()) session_key = "main";
          if (j["params"].contains("limit")) {
            limit = j["params"]["limit"].get<int>();
          }
        }
      } catch (...) {}

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = true;

      if (it->second.session_store) {
        auto messages = it->second.session_store->get_messages(session_key, limit);
        nlohmann::json msgs = nlohmann::json::array();
        for (const auto& m : messages) {
          nlohmann::json mj;
          mj["role"] = m.role;
          mj["content"] = nlohmann::json::array({{{"type", "text"}, {"text", m.content}}});
          mj["timestamp"] = m.timestamp;
          if (!m.run_id.empty()) mj["runId"] = m.run_id;
          if (!m.tool_call_id.empty()) mj["toolCallId"] = m.tool_call_id;
          if (!m.tool_name.empty()) mj["toolName"] = m.tool_name;
          msgs.push_back(std::move(mj));
        }
        res["payload"] = {{"messages", msgs}, {"sessionId", session_key}};
      } else {
        res["payload"] = {{"messages", nlohmann::json::array()}, {"sessionId", session_key}};
      }

      try {
        server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
      } catch (...) {}
      return;
    }

    // 处理 sessions.list（返回真实会话列表）
    if (method == "sessions.list") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = true;

      if (it->second.session_store) {
        auto sessions_list = it->second.session_store->list_sessions();
        nlohmann::json arr = nlohmann::json::array();
        for (const auto& s : sessions_list) {
          arr.push_back({
            {"key", s.key},
            {"displayName", s.display_name},
            {"createdAt", s.created_at},
            {"updatedAt", s.updated_at}
          });
        }
        res["payload"] = {{"sessions", arr}};
      } else {
        res["payload"] = {{"sessions", nlohmann::json::array()}};
      }

      try {
        server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
      } catch (...) {}
      return;
    }

    // 处理 sessions.delete
    if (method == "sessions.delete") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string session_key;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          session_key = get_string(j["params"], "sessionKey");
        }
      } catch (...) {}

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      if (session_key.empty()) {
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing sessionKey"}};
      } else if (it->second.session_store && it->second.session_store->delete_session(session_key)) {
        res["ok"] = true;
        res["payload"] = {{"deleted", true}};
      } else {
        res["ok"] = false;
        res["error"] = {{"code", "NOT_FOUND"}, {"message", "session not found"}};
      }
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }

    // 处理 sessions.reset
    if (method == "sessions.reset") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string session_key;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          session_key = get_string(j["params"], "sessionKey");
        }
      } catch (...) {}

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      if (session_key.empty()) {
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing sessionKey"}};
      } else if (it->second.session_store && it->second.session_store->reset_session(session_key)) {
        res["ok"] = true;
        res["payload"] = {{"reset", true}};
      } else {
        res["ok"] = false;
        res["error"] = {{"code", "NOT_FOUND"}, {"message", "session not found"}};
      }
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }

    // 处理 sessions.patch
    if (method == "sessions.patch") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string session_key;
      std::string display_name;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          session_key = get_string(j["params"], "sessionKey");
          display_name = get_string(j["params"], "displayName");
        }
      } catch (...) {}

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      if (session_key.empty()) {
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing sessionKey"}};
      } else if (it->second.session_store && it->second.session_store->patch_session(session_key, display_name)) {
        res["ok"] = true;
        res["payload"] = {{"patched", true}};
      } else {
        res["ok"] = false;
        res["error"] = {{"code", "NOT_FOUND"}, {"message", "session not found"}};
      }
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }

    // 处理 config.set（更新配置并保存）
    if (method == "config.set") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          auto& params = j["params"];

          // Update default_model
          if (params.contains("default_model") && params["default_model"].is_string()) {
            config.default_model = params["default_model"].get<std::string>();
          }

          // Update system_prompt
          if (params.contains("system_prompt") && params["system_prompt"].is_string()) {
            config.system_prompt = params["system_prompt"].get<std::string>();
          }

          // Update models array
          if (params.contains("models") && params["models"].is_array()) {
            config.models.clear();
            for (const auto& mj : params["models"]) {
              if (!mj.is_object()) continue;
              config::ModelEntry e;
              if (mj.contains("id") && mj["id"].is_string()) e.id = mj["id"].get<std::string>();
              if (e.id.empty()) continue;
              if (mj.contains("provider") && mj["provider"].is_string()) e.provider = mj["provider"].get<std::string>();
              if (mj.contains("base_url") && mj["base_url"].is_string()) e.base_url = mj["base_url"].get<std::string>();
              if (mj.contains("model_id") && mj["model_id"].is_string()) e.model_id = mj["model_id"].get<std::string>();
              if (e.model_id.empty()) e.model_id = e.id;
              if (mj.contains("api_key_env") && mj["api_key_env"].is_string()) e.api_key_env = mj["api_key_env"].get<std::string>();
              if (mj.contains("api_key") && mj["api_key"].is_string()) e.api_key = mj["api_key"].get<std::string>();
              config.models.push_back(std::move(e));
            }
          }

          // Save to hiclaw.json
          std::string save_err;
          bool saved = config::save(config.config_dir, config, save_err);
          if (!saved) {
            log::error("config.set: save failed: " + save_err);
          }

          nlohmann::json res;
          res["type"] = "res";
          res["id"] = id;
          res["ok"] = saved;
          if (saved) {
            res["payload"] = {
              {"default_model", config.default_model},
              {"saved", true}
            };
          } else {
            res["error"] = {{"code", "SAVE_FAILED"}, {"message", save_err}};
          }
          try {
            server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
          } catch (...) {}
          return;
        }
      } catch (const std::exception& e) {
        log::error("config.set: parse error: " + std::string(e.what()));
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", std::string("parse error: ") + e.what()}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      // Missing params
      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = false;
      res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing params"}};
      try {
        server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
      } catch (...) {}
      return;
    }

    // 处理 skills.* RPC
    if (method == "skills.list" || method == "skills.enable" || method == "skills.disable") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      auto* mgr = skills::instance();
      if (!mgr) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "INTERNAL_ERROR"}, {"message", "skill system not initialized"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      if (method == "skills.list") {
        nlohmann::json arr = nlohmann::json::array();
        for (const auto& s : mgr->skills()) {
          arr.push_back({
            {"id", s.id},
            {"name", s.name},
            {"description", s.description},
            {"enabled", s.enabled},
            {"builtin", s.builtin}
          });
        }
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = true;
        res["payload"] = {{"skills", arr}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      // skills.enable / skills.disable
      std::string skill_id;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          skill_id = get_string(j["params"], "id");
        }
      } catch (...) {}

      if (skill_id.empty()) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing id parameter"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      bool ok = (method == "skills.enable") ? mgr->enable(skill_id) : mgr->disable(skill_id);
      bool new_enabled = (method == "skills.enable");

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = ok;
      if (ok) {
        res["payload"] = {{"id", skill_id}, {"enabled", new_enabled}};
      } else {
        res["error"] = {{"code", "NOT_FOUND"}, {"message", "skill not found or already in requested state"}};
      }
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }

    if (method == "skills.install") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      auto* mgr = skills::instance();
      if (!mgr) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "INTERNAL_ERROR"}, {"message", "skill system not initialized"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string skill_id_val;
      std::string content;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          skill_id_val = get_string(j["params"], "id");
          content = get_string(j["params"], "content");
        }
      } catch (...) {}

      if (skill_id_val.empty() || content.empty()) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing id or content parameter"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string err = mgr->install_from_content(skill_id_val, content);
      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      if (err.empty()) {
        res["ok"] = true;
        res["payload"] = {{"id", skill_id_val}, {"installed", true}};
      } else {
        res["ok"] = false;
        res["error"] = {{"code", "INSTALL_FAILED"}, {"message", err}};
      }
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }

    if (method == "skills.remove") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      auto* mgr = skills::instance();
      if (!mgr) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "INTERNAL_ERROR"}, {"message", "skill system not initialized"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string skill_id_val;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          skill_id_val = get_string(j["params"], "id");
        }
      } catch (...) {}

      if (skill_id_val.empty()) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "BAD_REQUEST"}, {"message", "missing id parameter"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      bool removed = mgr->remove(skill_id_val);
      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = removed;
      if (removed) {
        res["payload"] = {{"id", skill_id_val}, {"removed", true}};
      } else {
        res["error"] = {{"code", "NOT_FOUND"}, {"message", "skill not found in installed skills"}};
      }
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }

    // 处理 chat.subscribe（订阅会话变更通知）
    if (method == "chat.subscribe") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try {
          server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
        } catch (...) {}
        return;
      }

      // Parse sessionKeys to subscribe (simplified - we just acknowledge)
      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = true;
      res["payload"] = {{"subscribed", true}};
      try {
        server.send(hdl, res.dump(), websocketpp::frame::opcode::text);
      } catch (...) {}
      return;
    }

    // 其他方法使用原来的 gateway_handle_frame
    bool connected = it->second.connected;
    std::string response = gateway_handle_frame(payload, config, pairing_code, connected);
    it->second.connected = connected;
    try {
      server.send(hdl, response, websocketpp::frame::opcode::text);
    } catch (...) {}
  });

  server.set_close_handler([&sessions](websocketpp::connection_hdl hdl) {
    sessions.erase(hdl);
  });

  try {
    server.listen(static_cast<uint16_t>(port));
    server.start_accept();
  } catch (std::exception const& e) {
    std::cerr << "HiClaw gateway: listen failed: " << e.what() << "\n";
    return;
  }
  std::cout << "HiClaw gateway on port " << port << " (websocketpp)";
  if (!pairing_code.empty()) std::cout << " (pairing code: " << pairing_code << ")";
  std::cout << "\n";

  // Heartbeat timer - send tick event every 30 seconds
  auto heartbeat_timer = std::make_shared<websocketpp::lib::asio::steady_timer>(server.get_io_service());
  std::function<void(const websocketpp::lib::error_code&)> heartbeat_loop;
  heartbeat_loop = [&server, &sessions, heartbeat_timer, &heartbeat_loop](const websocketpp::lib::error_code& ec) {
    if (ec) return;

    // Send tick event to all connected sessions
    for (auto& kv : sessions) {
      if (kv.second.connected) {
        nlohmann::json ev;
        ev["type"] = "event";
        ev["event"] = "tick";
        ev["payload"] = {{"ts", std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count()}};
        std::string msg = ev.dump();

        try {
          server.send(kv.first, msg, websocketpp::frame::opcode::text);
        } catch (...) {
          // Connection may have closed
        }
      }
    }

    // Schedule next heartbeat
    heartbeat_timer->expires_after(std::chrono::seconds(30));
    heartbeat_timer->async_wait(heartbeat_loop);
  };

  // Start heartbeat timer
  heartbeat_timer->expires_after(std::chrono::seconds(30));
  heartbeat_timer->async_wait(heartbeat_loop);

  server.run();
}

}  // namespace

void gateway_run(int port, config::Config& config, const std::string& pairing_code) {
  run_wspp_server(port, config, pairing_code);
}

// -----------------------------------------------------------------------------
// libwebsockets backend
// -----------------------------------------------------------------------------
#elif defined(HICLAW_USE_LIBWEBSOCKETS) && HICLAW_USE_LIBWEBSOCKETS

namespace {

struct GatewayUser {
  const config::Config* config;
  std::string pairing_code;
};

struct SessionData {
  bool connected = false;
  std::deque<std::string> write_queue;
};

static int gateway_callback(struct lws* wsi, enum lws_callback_reasons reason,
                            void* user, void* in, size_t len) {
  auto* pss = static_cast<SessionData**>(user);
  struct lws_context* ctx = lws_get_context(wsi);
  auto* gu = static_cast<GatewayUser*>(lws_context_user(ctx));
  const config::Config& config = *gu->config;
  const std::string& pairing_code = gu->pairing_code;

  switch (reason) {
  case LWS_CALLBACK_ESTABLISHED: {
    *pss = new SessionData();
    std::string nonce = "hiclaw-nonce-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    nlohmann::json ev;
    ev["type"] = "event";
    ev["event"] = "connect.challenge";
    ev["payload"] = {{"nonce", nonce}};
    std::string msg = ev.dump();
    (*pss)->write_queue.push_back(std::move(msg));
    lws_callback_on_writable(wsi);
    break;
  }
  case LWS_CALLBACK_CLOSED: {
    if (pss && *pss) {
      delete *pss;
      *pss = nullptr;
    }
    break;
  }
  case LWS_CALLBACK_RECEIVE: {
    if (!pss || !*pss) break;
    std::string frame(static_cast<const char*>(in), len);
    std::string response = gateway_handle_frame(frame, config, pairing_code, (*pss)->connected);
    (*pss)->write_queue.push_back(std::move(response));
    lws_callback_on_writable(wsi);
    break;
  }
  case LWS_CALLBACK_SERVER_WRITEABLE: {
    if (!pss || !*pss || (*pss)->write_queue.empty()) break;
    std::string& msg = (*pss)->write_queue.front();
    size_t len_msg = msg.size();
    std::vector<unsigned char> buf(LWS_PRE + len_msg);
    memcpy(buf.data() + LWS_PRE, msg.data(), len_msg);
    int n = lws_write(wsi, buf.data() + LWS_PRE, len_msg, LWS_WRITE_TEXT);
    (*pss)->write_queue.pop_front();
    if (n < 0) return -1;
    if (!(*pss)->write_queue.empty())
      lws_callback_on_writable(wsi);
    break;
  }
  default:
    break;
  }
  return 0;
}

static const struct lws_protocols protocols[] = {
  { "gateway", gateway_callback, sizeof(SessionData*), 4096, 0, nullptr, 0 },
  LWS_PROTOCOL_LIST_TERM
};

}  // namespace

void gateway_run(int port, config::Config& config, const std::string& pairing_code) {
  static GatewayUser gu;
  gu.config = &config;
  gu.pairing_code = pairing_code;

  struct lws_context_creation_info info = {};
  info.port = port;
  info.protocols = protocols;
  info.user = &gu;
  info.options = 0;

  struct lws_context* ctx = lws_create_context(&info);
  if (!ctx) {
    std::cerr << "HiClaw gateway: lws_create_context failed\n";
    return;
  }
  std::cout << "HiClaw gateway on port " << port << " (libwebsockets)";
  if (!pairing_code.empty()) std::cout << " (pairing code: " << pairing_code << ")";
  std::cout << "\n";
  while (true) {
    if (lws_service(ctx, 0) < 0) break;
  }
  lws_context_destroy(ctx);
}

// -----------------------------------------------------------------------------
// no backend (stub)
// -----------------------------------------------------------------------------
#else

void gateway_run(int port, config::Config& config, const std::string& pairing_code) {
  (void)port;
  (void)config;
  (void)pairing_code;
  std::cerr << "HiClaw gateway: no WebSocket backend built. Set HICLAW_GATEWAY_BACKEND=websocketpp (default for HarmonyOS) or install libwebsockets and use libwebsockets.\n";
}

#endif

}  // namespace net
}  // namespace hiclaw
