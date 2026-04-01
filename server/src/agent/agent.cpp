#include "hiclaw/agent/agent.hpp"
#include "hiclaw/memory/memory.hpp"
#include "hiclaw/observability/log.hpp"
#include "hiclaw/net/http_client.hpp"
#include "hiclaw/providers/ollama.hpp"
#include "hiclaw/providers/openai_compatible.hpp"
#include "hiclaw/skills/skill_manager.hpp"
#include "hiclaw/tools/tool.hpp"
#include "hiclaw/types/message.hpp"
#include <nlohmann/json.hpp>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <vector>
#if defined(_WIN32)
#include <windows.h>
#endif

namespace hiclaw {
namespace agent {

namespace {

using json = nlohmann::json;

#if defined(_WIN32)
/** Convert console input (typically CP936/GBK on Chinese Windows) to UTF-8 for API request body. */
static std::string to_utf8(const std::string& input) {
  if (input.empty()) return input;
  int wlen = MultiByteToWideChar(CP_ACP, 0, input.c_str(), -1, nullptr, 0);
  if (wlen <= 0) return input;
  std::vector<wchar_t> wbuf(static_cast<size_t>(wlen));
  MultiByteToWideChar(CP_ACP, 0, input.c_str(), -1, wbuf.data(), wlen);
  int ulen = WideCharToMultiByte(CP_UTF8, 0, wbuf.data(), -1, nullptr, 0, nullptr, nullptr);
  if (ulen <= 0) return input;
  std::vector<char> ubuf(static_cast<size_t>(ulen));
  WideCharToMultiByte(CP_UTF8, 0, wbuf.data(), -1, ubuf.data(), ulen, nullptr, nullptr);
  return std::string(ubuf.data(), static_cast<size_t>(ulen) - 1);
}
#else
static std::string to_utf8(const std::string& input) { return input; }
#endif

static json tools_array() {
  json tools = json::array();

  // shell tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"shell","description":"Run a shell command","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}})"));

  // file_read tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"file_read","description":"Read file contents","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}})"));

  // file_write tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"file_write","description":"Write content to file","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}})"));

  // web_fetch tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"web_fetch","description":"Fetch URL content via HTTP GET. Returns response body as text.","parameters":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]}}})"));

  // memory_store tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"memory_store","description":"Store a fact or note in long-term memory. Use category core (permanent), daily, or conversation.","parameters":{"type":"object","properties":{"key":{"type":"string"},"content":{"type":"string"},"category":{"type":"string"}},"required":["key","content"]}}})"));

  // memory_recall tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"memory_recall","description":"Search long-term memory for relevant facts. Returns scored results.","parameters":{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"integer"}},"required":["query"]}}})"));

  // memory_forget tool
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"memory_forget","description":"Remove a memory by key.","parameters":{"type":"object","properties":{"key":{"type":"string"}},"required":["key"]}}})"));

  // skill.read tool — load a skill's full instructions on demand
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"skill.read","description":"Load a skill's full instructions by name. Call this when a user request matches a skill listed in Available Skills.","parameters":{"type":"object","properties":{"name":{"type":"string","description":"Skill name or id from the Available Skills list"}},"required":["name"]}}})"));

  tools.push_back(json::parse(R"___({"type":"function","function":{"name":"memo.save","description":"Save a memo/note. Use when the user asks to remember, save, or note something from the screen or conversation.","parameters":{"type":"object","properties":{"title":{"type":"string","description":"Short title for the memo"},"content":{"type":"string","description":"The content to save"},"source":{"type":"string","description":"Source of the memo (e.g. screen, voice)"}},"required":["title","content"]}}})___"));
  tools.push_back(json::parse(R"___({"type":"function","function":{"name":"memo.list","description":"List saved memos/notes. Returns recent memos.","parameters":{"type":"object","properties":{"limit":{"type":"integer","description":"Max number of memos to return, default 20"}}}}})___"));

  return tools;
}

static json remote_tools_array() {
  json tools = json::array();

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"screen.capture","description":"Capture a screenshot of the user's current screen. Returns a base64-encoded image.","parameters":{"type":"object","properties":{}}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"camera.snap","description":"Take a photo using the device camera. Returns a base64-encoded image.","parameters":{"type":"object","properties":{"camera":{"type":"string","description":"Which camera to use: front or back","enum":["front","back"]}}}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"location.get","description":"Get the device's current GPS location (latitude, longitude, accuracy).","parameters":{"type":"object","properties":{}}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"notifications.list","description":"List recent notifications on the device.","parameters":{"type":"object","properties":{}}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"device.info","description":"Get device information (model, OS version, battery level, etc.).","parameters":{"type":"object","properties":{}}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"contacts.search","description":"Search the user's contacts by name or phone number.","parameters":{"type":"object","properties":{"query":{"type":"string","description":"Name or number to search for"}},"required":["query"]}}})"));

  tools.push_back(json::parse(R"___({"type":"function","function":{"name":"calendar.events","description":"List upcoming calendar events.","parameters":{"type":"object","properties":{"days":{"type":"integer","description":"Number of days to look ahead (default 7)"}}}}})___"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"system.notify","description":"Send a notification to the user's device.","parameters":{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"}},"required":["title","body"]}}})"));

  tools.push_back(json::parse(R"___({"type":"function","function":{"name":"input.type","description":"Type text into the currently focused input field on the device screen. The avatar will animate running to the input field and typing. Requires the user to have an input field focused.","parameters":{"type":"object","properties":{"text":{"type":"string","description":"The text to type into the input field"},"animate":{"type":"boolean","description":"Whether to animate the avatar typing, default true"},"charDelayMs":{"type":"integer","description":"Delay between each character in ms, default 80, range 20-500"}},"required":["text"]}}})___"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"input.find","description":"Check if there is a focused editable input field on the screen and get its position.","parameters":{"type":"object","properties":{},"required":[]}}})"));

  return tools;
}

static std::string get_skill_index() {
  auto* mgr = skills::instance();
  if (!mgr) return "";
  return mgr->build_skill_index_prompt();
}

static json all_tools_array() {
  json tools = tools_array();
  json remote = remote_tools_array();
  for (auto& t : remote) {
    tools.push_back(std::move(t));
  }
  return tools;
}

std::string user_message_json(const std::string& content) {
  json j;
  j["role"] = "user";
  j["content"] = content;
  return j.dump();
}

std::string assistant_message_json(const std::string& content,
                                   const std::vector<types::ToolCall>& tool_calls) {
  json j;
  j["role"] = "assistant";
  j["content"] = content.empty() ? "" : content;
  if (!tool_calls.empty()) {
    j["tool_calls"] = json::array();
    for (const types::ToolCall& tc : tool_calls) {
      json fc;
      fc["type"] = "function";
      fc["id"] = tc.id;
      fc["function"] = json::object();
      fc["function"]["name"] = tc.name;
      fc["function"]["arguments"] = tc.arguments;
      j["tool_calls"].push_back(std::move(fc));
    }
  }
  return j.dump();
}

std::string tool_message_json(const std::string& tool_call_id, const std::string& content) {
  json j;
  j["role"] = "tool";
  j["tool_call_id"] = tool_call_id;
  j["content"] = content;
  return j.dump();
}

}  // namespace

RunResult run(const config::Config& config,
              const std::string& user_prompt,
              double temperature) {
  tools::register_builtin_tools();
  memory::set_base_path(config.config_dir);
  log::info("agent run: " + user_prompt.substr(0, 60) + (user_prompt.size() > 60 ? "..." : ""));

  std::string base_url, model_id, api_key;
  bool use_openai = false;
  if (!config::resolve_model(config, base_url, model_id, api_key, use_openai)) {
    RunResult r;
    r.error = "resolve_model failed";
    return r;
  }
  std::string mod = model_id.empty() ? "llama3.2" : model_id;

  log::debug("run base_url=" + base_url + " model=" + mod +
             " use_openai=" + (use_openai ? "true" : "false") +
             " api_key_set=" + (api_key.empty() ? "no" : "yes"));
  double temp = (temperature >= 0.0 && temperature <= 2.0) ? temperature : 0.7;
  if (use_openai && api_key.empty())
    hiclaw::log::warn("api_key is empty; set api_key in model config or the provider API key env (e.g. GLM_API_KEY) to avoid 401");

  std::vector<std::string> messages_json;

  // Inject system prompt
  std::string sys_prompt = config.system_prompt;
  if (sys_prompt.empty()) {
    sys_prompt =
        "You are BoJi (啵唧), an AI assistant running on the user's Android device.\n\n"
        "## Response Style\n"
        "- Keep responses SHORT and to the point. 1-3 sentences for simple questions.\n"
        "- Do NOT add excessive emoji, roleplay descriptions, or filler text.\n"
        "- Do NOT list options the user didn't ask about.\n"
        "- Do NOT fabricate results — if you need to use a tool, actually use it.\n"
        "- When a task requires action (SMS, photo, file lookup), DO IT immediately using tools. Don't just describe what you would do.\n"
        "- Respond in the same language as the user.\n"
        "\n"
        "## Tools\n"
        "### Local (on device)\n"
        "- `shell` — run shell commands (query SMS, manage files, change settings, etc.)\n"
        "- `file_read` / `file_write` — read/write files\n"
        "- `web_fetch` — fetch web pages\n"
        "- `memory_store` / `memory_recall` / `memory_forget` — long-term memory\n"
        "- `skill.read` — load skill instructions (see Available Skills below)\n"
        "\n"
        "### Remote (device hardware/app)\n"
        "- `camera.snap` — take photo (front/back camera)\n"
        "- `screen.capture` — screenshot\n"
        "- `location.get` — GPS location\n"
        "- `device.info` — device model, battery, OS\n"
        "- `contacts.search` — search contacts\n"
        "- `notifications.list` — recent notifications\n"
        "- `calendar.events` — upcoming events\n"
        "- `system.notify` — send notification\n"
        "\n"
        "## Skill Usage\n"
        "When a user request matches an Available Skill, you MUST:\n"
        "1. Call `skill.read` with the skill name\n"
        "2. Follow the loaded instructions using `shell`\n"
        "Do NOT guess commands — load the skill first.\n";
  }
  sys_prompt += get_skill_index();
  {
    json sj;
    sj["role"] = "system";
    sj["content"] = sys_prompt;
    messages_json.push_back(sj.dump());
  }

  messages_json.push_back(user_message_json(to_utf8(user_prompt)));

  bool send_tools = (base_url.find("minimaxi.com") == std::string::npos);
  std::string tools_str = (send_tools) ? tools_array().dump() : "";
  for (int round = 0; round < 3; ++round) {
    std::string tools = (round == 0 && send_tools) ? tools_str : "";
    providers::OllamaResponse resp;
    if (use_openai)
      resp = providers::chat(base_url, api_key, mod, messages_json, temp, tools);
    else
      resp = providers::chat(base_url, mod, messages_json, temp, tools);

    if (!resp.ok) {
      hiclaw::log::error("provider error: " + resp.error);
      RunResult r;
      r.error = resp.error;
      return r;
    }

    if (resp.tool_calls.empty()) {
      RunResult r;
      r.ok = true;
      r.content = resp.content;
      return r;
    }

    messages_json.push_back(assistant_message_json(resp.content, resp.tool_calls));
    for (const types::ToolCall& tc : resp.tool_calls) {
      types::ToolResult tr = tools::run_tool(tc.name, tc.arguments);
      std::string out = tr.success ? tr.output : ("error: " + tr.error);
      messages_json.push_back(tool_message_json(tc.id, out));
    }
  }

  RunResult r;
  r.ok = true;
  r.content = "(max tool rounds reached)";
  return r;
}

namespace {

// Accumulated tool call state during streaming
struct AccumulatedToolCall {
  std::string id;
  std::string name;
  std::string arguments;
  bool has_id = false;
  bool has_name = false;
};

// Helper to process a complete SSE line and extract content delta and tool_calls
static void process_sse_line(const std::string& line,
                             std::string& full_content,
                             TextStreamCallback text_callback,
                             std::vector<AccumulatedToolCall>& tool_calls_acc,
                             ToolCallCallback tool_callback,
                             bool& is_done) {
  // Skip empty lines
  if (line.empty()) return;

  // Check for SSE data line
  if (line.size() >= 6 && line.substr(0, 6) == "data: ") {
    std::string json_str = line.substr(6);

    // Check for [DONE] marker - signal to flush tool calls
    if (json_str == "[DONE]") {
      is_done = true;
      // Flush all accumulated tool calls as complete
      if (tool_callback) {
        for (auto& tc : tool_calls_acc) {
          if (tc.has_id && tc.has_name) {
            ToolCallEvent event;
            event.id = tc.id;
            event.name = tc.name;
            event.arguments = tc.arguments;
            event.is_complete = true;
            tool_callback(event);
          }
        }
      }
      return;
    }

    try {
      json j = json::parse(json_str);

      // OpenAI format: choices[0].delta.content
      if (j.contains("choices") && j["choices"].is_array() && !j["choices"].empty()) {
        auto& choice = j["choices"][0];
        if (choice.contains("delta") && choice["delta"].is_object()) {
          auto& delta = choice["delta"];

          // Process text content
          if (delta.contains("content") && !delta["content"].is_null()) {
            std::string text = delta["content"].get<std::string>();
            if (!text.empty()) {
              full_content += text;
              if (text_callback) {
                text_callback(text);
              }
            }
          }

          // Process tool_calls (incremental)
          if (delta.contains("tool_calls") && delta["tool_calls"].is_array()) {
            for (auto& tc_delta : delta["tool_calls"]) {
              // Get index to track which tool call this belongs to
              if (!tc_delta.contains("index") || !tc_delta["index"].is_number()) {
                continue;
              }
              int idx = tc_delta["index"].get<int>();

              // Ensure we have space for this index
              if (idx < 0) continue;
              while (static_cast<int>(tool_calls_acc.size()) <= idx) {
                tool_calls_acc.push_back(AccumulatedToolCall{});
              }

              auto& acc = tool_calls_acc[idx];

              // Capture ID (usually sent in first chunk)
              if (tc_delta.contains("id") && !tc_delta["id"].is_null()) {
                acc.id = tc_delta["id"].get<std::string>();
                acc.has_id = true;
              }

              // Capture type (should be "function")
              if (tc_delta.contains("type") && !tc_delta["type"].is_null()) {
                // We only support "function" type
              }

              // Capture function name and arguments
              if (tc_delta.contains("function") && tc_delta["function"].is_object()) {
                auto& func = tc_delta["function"];
                if (func.contains("name") && !func["name"].is_null()) {
                  acc.name = func["name"].get<std::string>();
                  acc.has_name = true;
                }
                if (func.contains("arguments") && !func["arguments"].is_null()) {
                  // Arguments are sent incrementally as string fragments
                  acc.arguments += func["arguments"].get<std::string>();
                }
              }
            }
          }
        }
      }
    } catch (const json::parse_error&) {
      // Skip malformed JSON
    }
  }
}

}  // anonymous namespace

RunResult run_streaming(const config::Config& config,
                        const std::string& user_prompt,
                        double temperature,
                        TextStreamCallback text_callback,
                        ToolCallCallback tool_callback) {
  tools::register_builtin_tools();
  memory::set_base_path(config.config_dir);
  log::info("agent run_streaming: " + user_prompt.substr(0, 60) + (user_prompt.size() > 60 ? "..." : ""));

  // Resolve model configuration
  std::string base_url, model_id, api_key;
  bool use_openai = false;
  if (!config::resolve_model(config, base_url, model_id, api_key, use_openai)) {
    RunResult r;
    r.error = "resolve_model failed";
    return r;
  }

  std::string mod = model_id.empty() ? "llama3.2" : model_id;
  double temp = (temperature >= 0.0 && temperature <= 2.0) ? temperature : 0.7;

  log::debug("run_streaming base_url=" + base_url + " model=" + mod +
             " use_openai=" + (use_openai ? "true" : "false"));

  // Build OpenAI-compatible streaming request
  json req_body;
  req_body["model"] = mod;
  req_body["stream"] = true;
  req_body["messages"] = json::array();

  // Inject system prompt
  std::string sys_prompt = config.system_prompt;
  if (sys_prompt.empty()) {
    sys_prompt =
        "You are BoJi (啵唧), an AI assistant running on the user's Android device.\n\n"
        "## Response Style\n"
        "- Keep responses SHORT and to the point. 1-3 sentences for simple questions.\n"
        "- Do NOT add excessive emoji, roleplay descriptions, or filler text.\n"
        "- Do NOT list options the user didn't ask about.\n"
        "- Do NOT fabricate results — if you need to use a tool, actually use it.\n"
        "- When a task requires action (SMS, photo, file lookup), DO IT immediately using tools. Don't just describe what you would do.\n"
        "- Respond in the same language as the user.\n"
        "\n"
        "## Tools\n"
        "### Local (on device)\n"
        "- `shell` — run shell commands (query SMS, manage files, change settings, etc.)\n"
        "- `file_read` / `file_write` — read/write files\n"
        "- `web_fetch` — fetch web pages\n"
        "- `memory_store` / `memory_recall` / `memory_forget` — long-term memory\n"
        "- `skill.read` — load skill instructions (see Available Skills below)\n"
        "\n"
        "### Remote (device hardware/app)\n"
        "- `camera.snap` — take photo (front/back camera)\n"
        "- `screen.capture` — screenshot\n"
        "- `location.get` — GPS location\n"
        "- `device.info` — device model, battery, OS\n"
        "- `contacts.search` — search contacts\n"
        "- `notifications.list` — recent notifications\n"
        "- `calendar.events` — upcoming events\n"
        "- `system.notify` — send notification\n"
        "\n"
        "## Skill Usage\n"
        "When a user request matches an Available Skill, you MUST:\n"
        "1. Call `skill.read` with the skill name\n"
        "2. Follow the loaded instructions using `shell`\n"
        "Do NOT guess commands — load the skill first.\n";
  }
  sys_prompt += get_skill_index();
  req_body["messages"].push_back({{"role", "system"}, {"content", sys_prompt}});

  req_body["messages"].push_back({
    {"role", "user"},
    {"content", to_utf8(user_prompt)}
  });
  req_body["temperature"] = temp;

  bool send_tools_s = (base_url.find("minimaxi.com") == std::string::npos);
  if (send_tools_s) {
    req_body["tools"] = tools_array();
  }

  // Build URL
  std::string url = base_url;
  while (!url.empty() && (url.back() == '/' || url.back() == '\\')) url.pop_back();
  bool base_has_version = (url.size() >= 3 && url.compare(url.size() - 3, 3, "/v1") == 0) ||
                          (url.size() >= 3 && url.compare(url.size() - 3, 3, "/v4") == 0) ||
                          (url.size() >= 6 && url.compare(url.size() - 6, 6, "/v1beta") == 0);
  if (base_has_version)
    url += "/chat/completions";
  else
    url += "/v1/chat/completions";

  std::string auth = api_key.empty() ? "" : "Bearer " + api_key;

  // Send streaming request with line buffer for handling chunk boundaries
  std::string full_content;
  std::string line_buffer;  // Line buffer to handle chunk boundaries
  std::vector<AccumulatedToolCall> tool_calls_acc;  // Accumulated tool calls
  bool is_done = false;

  auto stream_cb = [&full_content, &text_callback, &tool_callback, &line_buffer, &tool_calls_acc, &is_done](const std::string& chunk) {
    // Append new data to the buffer
    line_buffer += chunk;

    // Process complete lines
    size_t pos = 0;
    while ((pos = line_buffer.find('\n')) != std::string::npos) {
      std::string line = line_buffer.substr(0, pos);
      line_buffer = line_buffer.substr(pos + 1);

      // Remove carriage return if present (Windows line endings)
      if (!line.empty() && line.back() == '\r') {
        line.pop_back();
      }

      // Process the complete SSE line
      process_sse_line(line, full_content, text_callback, tool_calls_acc, tool_callback, is_done);
    }
    // Incomplete line remains in line_buffer for next chunk
  };

  net::HttpResponse http_res;
  bool ok = net::post_json_streaming(url, req_body.dump(), stream_cb, http_res, auth);

  // Process any remaining content in the buffer
  if (!line_buffer.empty()) {
    // Remove trailing \r if present
    if (!line_buffer.empty() && line_buffer.back() == '\r') {
      line_buffer.pop_back();
    }
    process_sse_line(line_buffer, full_content, text_callback, tool_calls_acc, tool_callback, is_done);
  }

  // If stream ended without [DONE], flush any accumulated tool calls
  if (!is_done && tool_callback) {
    for (auto& tc : tool_calls_acc) {
      if (tc.has_id && tc.has_name) {
        ToolCallEvent event;
        event.id = tc.id;
        event.name = tc.name;
        event.arguments = tc.arguments;
        event.is_complete = true;
        tool_callback(event);
      }
    }
  }

  if (!ok) {
    RunResult r;
    std::string detail = http_res.error.empty() ? "HTTP request failed" : http_res.error;
    r.error = "无法连接模型服务 (" + mod + " @ " + base_url + "): " + detail;
    log::error("run_streaming error: " + r.error);
    return r;
  }

  RunResult r;
  r.ok = true;
  r.content = full_content;
  return r;
}

RunResult run_streaming_with_history(
    const config::Config& config,
    const std::vector<types::Message>& history,
    const std::string& user_prompt,
    double temperature,
    TextStreamCallback text_callback,
    ToolCallCallback tool_callback,
    const std::atomic<bool>* aborted,
    int max_tool_rounds,
    RemoteToolExecutor remote_executor,
    const std::string* user_message_json_override) {
  tools::register_builtin_tools();
  memory::set_base_path(config.config_dir);
  log::info("agent run_streaming_with_history: " + user_prompt.substr(0, 60) +
            (user_prompt.size() > 60 ? "..." : ""));

  std::string base_url, model_id, api_key;
  bool use_openai = false;
  if (!config::resolve_model(config, base_url, model_id, api_key, use_openai)) {
    RunResult r;
    r.error = "resolve_model failed";
    return r;
  }

  std::string mod = model_id.empty() ? "llama3.2" : model_id;
  double temp = (temperature >= 0.0 && temperature <= 2.0) ? temperature : 0.7;

  log::debug("run_streaming_with_history base_url=" + base_url +
             " model=" + mod + " use_openai=" + (use_openai ? "true" : "false") +
             " history_size=" + std::to_string(history.size()));

  // Build message array: system prompt + history + new user message
  std::vector<std::string> messages_json;

  // Inject system prompt as first message
  std::string sys_prompt = config.system_prompt;
  if (sys_prompt.empty()) {
    sys_prompt =
        "You are BoJi (啵唧), an AI assistant running on the user's Android device.\n\n"
        "## Response Style\n"
        "- Keep responses SHORT and to the point. 1-3 sentences for simple questions.\n"
        "- Do NOT add excessive emoji, roleplay descriptions, or filler text.\n"
        "- Do NOT list options the user didn't ask about.\n"
        "- Do NOT fabricate results — if you need to use a tool, actually use it.\n"
        "- When a task requires action (SMS, photo, file lookup), DO IT immediately using tools. Don't just describe what you would do.\n"
        "- Respond in the same language as the user.\n"
        "\n"
        "## Tools\n"
        "### Local (on device)\n"
        "- `shell` — run shell commands (query SMS, manage files, change settings, etc.)\n"
        "- `file_read` / `file_write` — read/write files\n"
        "- `web_fetch` — fetch web pages\n"
        "- `memory_store` / `memory_recall` / `memory_forget` — long-term memory\n"
        "- `skill.read` — load skill instructions (see Available Skills below)\n"
        "\n"
        "### Remote (device hardware/app)\n"
        "- `camera.snap` — take photo (front/back camera)\n"
        "- `screen.capture` — screenshot\n"
        "- `location.get` — GPS location\n"
        "- `device.info` — device model, battery, OS\n"
        "- `contacts.search` — search contacts\n"
        "- `notifications.list` — recent notifications\n"
        "- `calendar.events` — upcoming events\n"
        "- `system.notify` — send notification\n"
        "\n"
        "## Skill Usage\n"
        "When a user request matches an Available Skill, you MUST:\n"
        "1. Call `skill.read` with the skill name\n"
        "2. Follow the loaded instructions using `shell`\n"
        "Do NOT guess commands — load the skill first.\n";
  }
  sys_prompt += get_skill_index();
  {
    json sj;
    sj["role"] = "system";
    sj["content"] = sys_prompt;
    messages_json.push_back(sj.dump());
  }

  for (const auto& msg : history) {
    json mj;
    mj["role"] = msg.role;
    mj["content"] = msg.content;
    messages_json.push_back(mj.dump());
  }
  if (user_message_json_override != nullptr && !user_message_json_override->empty()) {
    messages_json.push_back(*user_message_json_override);
  } else {
    messages_json.push_back(user_message_json(to_utf8(user_prompt)));
  }

  bool send_tools = (base_url.find("minimaxi.com") == std::string::npos);
  std::string tools_str = send_tools ? (remote_executor ? all_tools_array() : tools_array()).dump() : "";

  std::string full_content;

  for (int round = 0; round < max_tool_rounds; ++round) {
    if (aborted && aborted->load()) {
      RunResult r;
      r.ok = true;
      r.content = full_content;
      return r;
    }

    // Build streaming request body
    json req_body;
    req_body["model"] = mod;
    req_body["stream"] = true;
    req_body["messages"] = json::array();
    for (const auto& mj_str : messages_json) {
      req_body["messages"].push_back(json::parse(mj_str));
    }
    req_body["temperature"] = temp;
    if (send_tools && !tools_str.empty()) {
      req_body["tools"] = json::parse(tools_str);
    }

    // Build URL
    std::string url = base_url;
    while (!url.empty() && (url.back() == '/' || url.back() == '\\')) url.pop_back();
    bool base_has_version = (url.size() >= 3 && url.compare(url.size() - 3, 3, "/v1") == 0) ||
                            (url.size() >= 3 && url.compare(url.size() - 3, 3, "/v4") == 0) ||
                            (url.size() >= 6 && url.compare(url.size() - 6, 6, "/v1beta") == 0);
    if (base_has_version)
      url += "/chat/completions";
    else
      url += "/v1/chat/completions";

    std::string auth = api_key.empty() ? "" : "Bearer " + api_key;

    // Stream the response
    std::string round_content;
    std::string line_buffer;
    std::vector<AccumulatedToolCall> tool_calls_acc;
    bool is_done = false;

    auto stream_cb = [&round_content, &text_callback, &tool_callback,
                      &line_buffer, &tool_calls_acc, &is_done](const std::string& chunk) {
      line_buffer += chunk;
      size_t pos = 0;
      while ((pos = line_buffer.find('\n')) != std::string::npos) {
        std::string line = line_buffer.substr(0, pos);
        line_buffer = line_buffer.substr(pos + 1);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        process_sse_line(line, round_content, text_callback, tool_calls_acc, tool_callback, is_done);
      }
    };

    net::HttpResponse http_res;
    bool ok = net::post_json_streaming(url, req_body.dump(), stream_cb, http_res, auth);

    // Process remaining buffer
    if (!line_buffer.empty()) {
      if (!line_buffer.empty() && line_buffer.back() == '\r') line_buffer.pop_back();
      process_sse_line(line_buffer, round_content, text_callback, tool_calls_acc, tool_callback, is_done);
    }

    if (!is_done && tool_callback) {
      for (auto& tc : tool_calls_acc) {
        if (tc.has_id && tc.has_name) {
          ToolCallEvent event;
          event.id = tc.id;
          event.name = tc.name;
          event.arguments = tc.arguments;
          event.is_complete = true;
          tool_callback(event);
        }
      }
    }

    if (!ok) {
      RunResult r;
      std::string detail = http_res.error.empty() ? "HTTP request failed" : http_res.error;
      r.error = "无法连接模型服务 (" + mod + " @ " + base_url + "): " + detail;
      log::error("run_streaming_with_history error: " + r.error);
      return r;
    }

    full_content += round_content;

    // Check if there are tool calls to execute
    bool has_tools = false;
    for (const auto& tc : tool_calls_acc) {
      if (tc.has_id && tc.has_name) { has_tools = true; break; }
    }

    if (!has_tools) {
      // No tool calls, we're done
      RunResult r;
      r.ok = true;
      r.content = full_content;
      return r;
    }

    // Execute tool calls and append results
    std::vector<types::ToolCall> tool_calls;
    for (const auto& tc : tool_calls_acc) {
      if (tc.has_id && tc.has_name) {
        tool_calls.push_back({tc.id, tc.name, tc.arguments});
      }
    }

    messages_json.push_back(assistant_message_json(round_content, tool_calls));

    for (const auto& tc : tool_calls) {
      if (aborted && aborted->load()) break;
      types::ToolResult tr;
      if (tools::is_remote_tool(tc.name) && remote_executor) {
        tr = remote_executor(tc.id, tc.name, tc.arguments);
      } else {
        tr = tools::run_tool(tc.name, tc.arguments);
      }
      std::string out = tr.success ? tr.output : ("error: " + tr.error);
      messages_json.push_back(tool_message_json(tc.id, out));
    }

    // Reset for next round - don't send tools again after first round
    // (keeps behavior consistent with non-streaming run)
  }

  RunResult r;
  r.ok = true;
  r.content = full_content.empty() ? "(max tool rounds reached)" : full_content;
  return r;
}

}  // namespace agent
}  // namespace hiclaw
