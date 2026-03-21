#ifndef HICLAW_CONFIG_DEFAULT_PROVIDERS_HPP
#define HICLAW_CONFIG_DEFAULT_PROVIDERS_HPP

#include <cstddef>

namespace hiclaw {
namespace config {

/** One built-in provider entry (C++ constants). */
struct DefaultProviderEntry {
  const char* id;
  const char* display_name;
  const char* default_base_url;
  const char* default_api_key_env;
};

/** Built-in provider list; compiled into the binary. */
inline constexpr DefaultProviderEntry kDefaultProviders[] = {
    {"ollama", "Ollama", "http://localhost:11434", ""},
    {"openai", "OpenAI", "https://api.openai.com/v1", "OPENAI_API_KEY"},
    {"anthropic", "Anthropic", "https://api.anthropic.com/v1", "ANTHROPIC_API_KEY"},
    {"glm", "GLM", "https://open.bigmodel.cn/api/paas/v4", "GLM_API_KEY"},
    {"minimax", "MiniMax", "https://api.minimaxi.com/v1", "MINIMAX_API_KEY"},
    {"qwen", "Qwen", "https://dashscope.aliyuncs.com/compatible-mode/v1", "DASHSCOPE_API_KEY"},
    {"kimi", "Kimi", "https://api.moonshot.cn/v1", "KIMI_API_KEY"},
    {"gemini", "Gemini", "https://generativelanguage.googleapis.com/v1beta", "GEMINI_API_KEY"},
    {"openai_compatible", "Custom", "", "OPENAI_API_KEY"},
};

inline constexpr std::size_t kDefaultProvidersCount = sizeof(kDefaultProviders) / sizeof(kDefaultProviders[0]);

}  // namespace config
}  // namespace hiclaw

#endif
