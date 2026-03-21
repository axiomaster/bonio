#ifndef HICLAW_PROVIDERS_OPENAI_COMPATIBLE_HPP
#define HICLAW_PROVIDERS_OPENAI_COMPATIBLE_HPP

#include "hiclaw/providers/ollama.hpp"
#include "hiclaw/types/message.hpp"
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

}  // namespace providers
}  // namespace hiclaw

#endif
