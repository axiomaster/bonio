#ifndef HICLAW_PROVIDERS_OPENAI_COMPATIBLE_HPP
#define HICLAW_PROVIDERS_OPENAI_COMPATIBLE_HPP

#include "hiclaw/providers/ollama.hpp"
#include "hiclaw/types/message.hpp"
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

namespace hiclaw {
namespace providers {

/**
 * OpenAI-compatible API (e.g. LocalAI, llama.cpp server, OpenRouter).
 * POST to base_url/v1/chat/completions. HTTP only; use a local proxy for api.openai.com.
 * api_key: optional, sent as Authorization: Bearer <api_key>.
 */
OllamaResponse chat(const std::string& base_url,
                    const std::string& api_key,
                    const std::string& model,
                    const std::vector<std::string>& messages_json,
                    double temperature,
                    const std::string& tools_json);

/**
 * Tool-name codec: strict OpenAI-compatible providers (e.g. DeepSeek) validate
 * function names against ^[a-zA-Z0-9_-]+$, but hiclaw tool names are dotted
 * ("sms.send"). Encode dots as "__" in outgoing requests and decode them back
 * from model responses. Safe because no built-in tool name contains "__".
 */
std::string encode_tool_name(const std::string& name);
std::string decode_tool_name(const std::string& name);

/** Rewrite function names in a chat-completions request body: tools[] and
 * messages[].tool_calls[].function.name get encoded via encode_tool_name. */
void encode_request_tool_names(nlohmann::json& body);

}  // namespace providers
}  // namespace hiclaw

#endif
