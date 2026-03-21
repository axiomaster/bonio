#include "hiclaw/net/http_client.hpp"
#include "hiclaw/providers/ollama.hpp"
#include "hiclaw/providers/openai_compatible.hpp"
#include "hiclaw/types/message.hpp"
#include <nlohmann/json.hpp>

namespace hiclaw {
namespace providers {

namespace {

using json = nlohmann::json;

std::string build_openai_body(const std::string& model,
                              const std::vector<std::string>& messages_json,
                              double temperature,
                              const std::string& tools_json) {
  json j;
  j["model"] = model;
  j["messages"] = json::array();
  for (const std::string& s : messages_json) {
    try {
      j["messages"].push_back(json::parse(s));
    } catch (const json::parse_error&) {
      continue;
    }
  }
  j["temperature"] = temperature;
  if (!tools_json.empty()) {
    try {
      j["tools"] = json::parse(tools_json);
    } catch (const json::parse_error&) {
      // leave tools out on parse error
    }
  }
  return j.dump();
}

std::string parse_content(const std::string& body) {
  try {
    json j = json::parse(body);
    if (j.contains("content") && j["content"].is_string())
      return j["content"].get<std::string>();
    if (j.contains("message") && j["message"].is_object() && j["message"].contains("content"))
      return j["message"]["content"].get<std::string>();
    if (j.contains("choices") && j["choices"].is_array() && !j["choices"].empty()) {
      const json& choice = j["choices"][0];
      if (choice.contains("message") && choice["message"].contains("content"))
        return choice["message"]["content"].get<std::string>();
    }
  } catch (const json::parse_error&) {
  }
  return "";
}

void parse_tool_calls(const std::string& body, std::vector<types::ToolCall>& out) {
  out.clear();
  try {
    json j = json::parse(body);
    json* arr = nullptr;
    if (j.contains("tool_calls") && j["tool_calls"].is_array())
      arr = &j["tool_calls"];
    else if (j.contains("message") && j["message"].contains("tool_calls") && j["message"]["tool_calls"].is_array())
      arr = &j["message"]["tool_calls"];
    if (!arr) return;
    for (const json& el : *arr) {
      types::ToolCall tc;
      if (el.contains("id") && el["id"].is_string()) tc.id = el["id"].get<std::string>();
      if (el.contains("function") && el["function"].is_object()) {
        const json& fn = el["function"];
        if (fn.contains("name") && fn["name"].is_string()) tc.name = fn["name"].get<std::string>();
        if (fn.contains("arguments") && fn["arguments"].is_string()) tc.arguments = fn["arguments"].get<std::string>();
      }
      if (!tc.name.empty()) out.push_back(std::move(tc));
    }
  } catch (const json::parse_error&) {
  }
}

std::string extract_message_object(const std::string& body) {
  try {
    json j = json::parse(body);
    if (j.contains("message") && j["message"].is_object())
      return j["message"].dump();
  } catch (const json::parse_error&) {
  }
  return "";
}

}  // namespace

OllamaResponse chat(const std::string& base_url,
                    const std::string& api_key,
                    const std::string& model,
                    const std::vector<std::string>& messages_json,
                    double temperature,
                    const std::string& tools_json) {
  OllamaResponse resp;
  std::string url = base_url;
  while (!url.empty() && (url.back() == '/' || url.back() == '\\')) url.pop_back();
  bool base_has_version = (url.size() >= 3 && url.compare(url.size() - 3, 3, "/v1") == 0) ||
                          (url.size() >= 3 && url.compare(url.size() - 3, 3, "/v4") == 0) ||
                          (url.size() >= 6 && url.compare(url.size() - 6, 6, "/v1beta") == 0);
  if (base_has_version)
    url += "/chat/completions";
  else
    url += "/v1/chat/completions";

  std::string body = build_openai_body(model, messages_json, temperature, tools_json);
  std::string auth;
  if (!api_key.empty()) auth = "Bearer " + api_key;

  net::HttpResponse http_res;
  if (!net::post_json(url, body, http_res, auth)) {
    resp.error = http_res.error.empty() ? "HTTP request failed" : http_res.error;
    if (http_res.status_code == 401) {
      std::string preview = http_res.body.substr(0, 200);
      for (char& c : preview) if (static_cast<unsigned char>(c) >= 128) c = '?';
      resp.error = "HTTP 401: " + preview + " (check api_key in config or set the provider API key env, e.g. GLM_API_KEY)";
    }
    return resp;
  }
  if (http_res.status_code != 200) {
    std::string preview = http_res.body.substr(0, 200);
    for (char& c : preview) if (static_cast<unsigned char>(c) >= 128) c = '?';
    resp.error = "HTTP " + std::to_string(http_res.status_code) + ": " + preview;
    if (http_res.status_code == 401)
      resp.error += " (check api_key in config or set the provider API key env, e.g. GLM_API_KEY)";
    return resp;
  }
  std::string msg_obj = extract_message_object(http_res.body);
  if (msg_obj.empty()) msg_obj = http_res.body;
  resp.content = parse_content(msg_obj);
  parse_tool_calls(msg_obj, resp.tool_calls);
  resp.ok = true;
  return resp;
}

}  // namespace providers
}  // namespace hiclaw
