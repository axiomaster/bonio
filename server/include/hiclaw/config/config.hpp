#ifndef HICLAW_CONFIG_CONFIG_HPP
#define HICLAW_CONFIG_CONFIG_HPP

#include <string>
#include <vector>
#include <map>

namespace hiclaw {
namespace config {

/** Provider metadata (built-in list in default_providers.hpp). */
struct ProviderMeta {
  std::string id;
  std::string display_name;
  std::string default_base_url;
  std::string default_api_key_env;
};

/**
 * Load provider registry from built-in constants (see default_providers.hpp).
 * Returns map provider_id -> ProviderMeta.
 */
std::map<std::string, ProviderMeta> load_provider_registry(const std::string& config_dir);

/** One model config entry: id is the model name (e.g. "glm-4"); provider is the service (e.g. "glm")—multiple models can share one provider. */
struct ModelEntry {
  std::string id;
  std::string provider;      // ollama | openai | anthropic | glm | minimax | qwen | kimi | gemini | openai_compatible
  std::string base_url;      // optional override
  std::string model_id;      // optional API model name (defaults to id)
  std::string api_key_env;   // optional env var for API key (e.g. GLM_API_KEY)
  std::string api_key;       // optional API key from config (used when env var not set)
};

struct Config {
  std::string config_dir;
  /** Config filename in config_dir: "config.json" (default) or "hiclaw.json" when using HICLAW_WORKSPACE. */
  std::string config_file = "config.json";
  /** Which model (by id) to use: must match one of models[].id. */
  std::string default_model;
  /** Model list: each entry is a model; provider field indicates the API/service (e.g. GLM-4 and GLM-5 both use provider glm). */
  std::vector<ModelEntry> models;
  /** System prompt injected as the first message in every conversation. Empty = use built-in default. */
  std::string system_prompt;

  // Gateway configuration
  struct GatewayConfig {
    int port = 8765;                   // WebSocket gateway port
    std::string host = "0.0.0.0";       // Bind address (default: all interfaces)
    bool enabled = true;                // Enable/disable gateway
    std::string pairing_code;           // Optional static pairing code (empty = auto-generate)
  };
  GatewayConfig gateway;
};

/**
 * Resolve default_model to base_url, model_id, api_key, and whether to use OpenAI-compatible API.
 * Returns true if a model was resolved (from models[] or provider registry fallback).
 */
bool resolve_model(const Config& config,
                      std::string& out_base_url,
                      std::string& out_model_id,
                      std::string& out_api_key,
                      bool& out_use_openai_compatible);

/**
 * Get workspace path from HICLAW_WORKSPACE env (with ~ expanded to home), or empty if not set.
 */
std::string get_workspace();

/**
 * Default workspace when HICLAW_WORKSPACE is not set: ~/.bonio (Windows: %USERPROFILE%\.bonio).
 * Config file is always workspace/hiclaw.json.
 */
std::string get_default_workspace();

/**
 * Load config from workspace/hiclaw.json. Workspace = HICLAW_WORKSPACE (if set), else --config-dir (if set), else default (~/.bonio).
 */
bool load(const std::string& config_dir, Config& out, std::string& err);

/**
 * Save config to out.config_dir / out.config_file (creates directory if needed).
 * When loaded from workspace, config_file is hiclaw.json so model/config updates go there.
 */
bool save(const std::string& config_dir, const Config& cfg, std::string& err);

/**
 * If default_model is set but not present in models[], add a minimal entry for it
 * (provider inferred from id, e.g. minimax-2.5 -> minimax). Call before save when
 * adding new models so the current default is not lost.
 */
void ensure_default_in_models(Config& cfg);

}  // namespace config
}  // namespace hiclaw

#endif
