#ifndef HICLAW_PROVIDERS_OLLAMA_HPP
#define HICLAW_PROVIDERS_OLLAMA_HPP

#include "hiclaw/types/message.hpp"
#include <string>
#include <vector>

namespace hiclaw {
namespace providers {

struct OllamaResponse {
  std::string content;
  std::string reasoning;  // For thinking models (e.g., qwen3)
  std::vector<types::ToolCall> tool_calls;
  bool ok = false;
  std::string error;
};

/**
 * Call Ollama /api/chat. messages_json: array of JSON objects (each one message).
 * base_url e.g. "http://localhost:11434", model e.g. "llama3.2".
 */
OllamaResponse chat(const std::string& base_url,
                    const std::string& model,
                    const std::vector<std::string>& messages_json,
                    double temperature,
                    const std::string& tools_json);

}  // namespace providers
}  // namespace hiclaw

#endif
