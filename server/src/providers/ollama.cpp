#include "hiclaw/net/http_client.hpp"
#include "hiclaw/providers/ollama.hpp"
#include "hiclaw/types/message.hpp"
#include <nlohmann/json.hpp>

namespace hiclaw {
namespace providers {

namespace {

using json = nlohmann::json;

// Response structure for structured parsing
struct ChatCompletionResponse {
  std::string id;
  std::string object;
  struct Choice {
    int index = 0;
    struct Message {
      std::string role;
      std::string content;
      std::string reasoning;  // For thinking models
      std::vector<types::ToolCall> tool_calls;
    } message;
    std::string finish_reason;
  };
  std::vector<Choice> choices;
  struct Usage {
    int prompt_tokens = 0;
    int completion_tokens = 0;
    int total_tokens = 0;
  } usage;
  bool parse_success = false;
  std::string parse_error;
};

// Structured parsing of OpenAI-compatible response
ChatCompletionResponse parse_response(const std::string& body) {
  ChatCompletionResponse resp;
  try {
    json j = json::parse(body);

    if (j.contains("id") && j["id"].is_string()) {
      resp.id = j["id"].get<std::string>();
    }
    if (j.contains("object") && j["object"].is_string()) {
      resp.object = j["object"].get<std::string>();
    }

    // Parse choices array
    if (j.contains("choices") && j["choices"].is_array()) {
      for (const auto& choice_json : j["choices"]) {
        ChatCompletionResponse::Choice choice;
        if (choice_json.contains("index") && choice_json["index"].is_number()) {
          choice.index = choice_json["index"].get<int>();
        }
        if (choice_json.contains("finish_reason") && choice_json["finish_reason"].is_string()) {
          choice.finish_reason = choice_json["finish_reason"].get<std::string>();
        }

        // Parse message
        if (choice_json.contains("message") && choice_json["message"].is_object()) {
          const auto& msg = choice_json["message"];
          if (msg.contains("role") && msg["role"].is_string()) {
            choice.message.role = msg["role"].get<std::string>();
          }
          if (msg.contains("content") && msg["content"].is_string()) {
            choice.message.content = msg["content"].get<std::string>();
          }
          // Parse reasoning field for thinking models
          if (msg.contains("reasoning") && msg["reasoning"].is_string()) {
            choice.message.reasoning = msg["reasoning"].get<std::string>();
          }

          // Parse tool calls
          if (msg.contains("tool_calls") && msg["tool_calls"].is_array()) {
            for (const auto& tc_json : msg["tool_calls"]) {
              types::ToolCall tc;
              if (tc_json.contains("id") && tc_json["id"].is_string()) {
                tc.id = tc_json["id"].get<std::string>();
              }
              if (tc_json.contains("function") && tc_json["function"].is_object()) {
                const auto& fn = tc_json["function"];
                if (fn.contains("name") && fn["name"].is_string()) {
                  tc.name = fn["name"].get<std::string>();
                }
                if (fn.contains("arguments") && fn["arguments"].is_string()) {
                  tc.arguments = fn["arguments"].get<std::string>();
                }
              }
              if (!tc.name.empty()) {
                choice.message.tool_calls.push_back(std::move(tc));
              }
            }
          }
        }

        resp.choices.push_back(std::move(choice));
      }
    }

    // Parse usage
    if (j.contains("usage") && j["usage"].is_object()) {
      const auto& usage = j["usage"];
      if (usage.contains("prompt_tokens") && usage["prompt_tokens"].is_number()) {
        resp.usage.prompt_tokens = usage["prompt_tokens"].get<int>();
      }
      if (usage.contains("completion_tokens") && usage["completion_tokens"].is_number()) {
        resp.usage.completion_tokens = usage["completion_tokens"].get<int>();
      }
      if (usage.contains("total_tokens") && usage["total_tokens"].is_number()) {
        resp.usage.total_tokens = usage["total_tokens"].get<int>();
      }
    }

    resp.parse_success = true;
  } catch (const json::parse_error& e) {
    resp.parse_error = "JSON parse error: " + std::string(e.what());
  } catch (const std::exception& e) {
    resp.parse_error = "Parse error: " + std::string(e.what());
  }
  return resp;
}

// Build OpenAI-compatible request body
std::string build_request_body(const std::string& model,
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

  // Add tools if provided
  if (!tools_json.empty()) {
    try {
      j["tools"] = json::parse(tools_json);
    } catch (const json::parse_error&) {
      // Ignore tools on parse error
    }
  }

  return j.dump();
}

}  // namespace

OllamaResponse chat(const std::string& base_url,
                    const std::string& model,
                    const std::vector<std::string>& messages_json,
                    double temperature,
                    const std::string& tools_json) {
  OllamaResponse resp;

  // Build URL for OpenAI-compatible endpoint
  std::string url = base_url;
  if (url.empty()) url = "http://localhost:11434";

  // Remove trailing slashes
  while (!url.empty() && (url.back() == '/' || url.back() == '\\')) {
    url.pop_back();
  }

  // Use OpenAI-compatible API endpoint
  url += "/v1/chat/completions";

  // Build request body
  std::string body = build_request_body(model, messages_json, temperature, tools_json);

  // Make HTTP request
  net::HttpResponse http_res;
  if (!net::post_json(url, body, http_res)) {
    resp.error = http_res.error.empty() ? "HTTP request failed" : http_res.error;
    return resp;
  }

  if (http_res.status_code != 200) {
    resp.error = "HTTP " + std::to_string(http_res.status_code) + ": " +
                 http_res.body.substr(0, 200);
    return resp;
  }

  // Parse response using structured parsing
  ChatCompletionResponse parsed = parse_response(http_res.body);

  if (!parsed.parse_success) {
    resp.error = parsed.parse_error;
    return resp;
  }

  if (parsed.choices.empty()) {
    resp.error = "No choices in response";
    return resp;
  }

  // Extract content from first choice
  const auto& first_choice = parsed.choices[0];
  resp.content = first_choice.message.content;
  resp.reasoning = first_choice.message.reasoning;
  resp.tool_calls = first_choice.message.tool_calls;
  resp.ok = true;

  return resp;
}

}  // namespace providers
}  // namespace hiclaw
