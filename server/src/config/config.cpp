#include "hiclaw/config/config.hpp"
#include "hiclaw/config/default_providers.hpp"
#include <nlohmann/json.hpp>
#include <cstdlib>
#include <fstream>
#include <sstream>
#if defined(_WIN32)
#include <direct.h>
#else
#include <sys/stat.h>
#endif

namespace hiclaw {
namespace config {

namespace {

using json = nlohmann::json;

}  // anonymous namespace

using json = nlohmann::json;

bool loadFromJson(const std::string& path, Config& out, std::string& err) {
  std::ifstream f(path);
  if (!f) {
    err = "cannot open " + path;
    return false;
  }
  std::ostringstream buf;
  buf << f.rdbuf();
  std::string content = buf.str();
  try {
    json j = json::parse(content);
    if (j.contains("default_model") && j["default_model"].is_string())
      out.default_model = j["default_model"].get<std::string>();
    if (j.contains("system_prompt") && j["system_prompt"].is_string())
      out.system_prompt = j["system_prompt"].get<std::string>();
    // Gateway configuration
    if (j.contains("gateway") && j["gateway"].is_object()) {
      const json& gw = j["gateway"];
      if (gw.contains("port") && gw["port"].is_number_integer())
        out.gateway.port = gw["port"].get<int>();
      if (gw.contains("host") && gw["host"].is_string())
        out.gateway.host = gw["host"].get<std::string>();
      if (gw.contains("enabled") && gw["enabled"].is_boolean())
        out.gateway.enabled = gw["enabled"].get<bool>();
      if (gw.contains("pairing_code") && gw["pairing_code"].is_string())
        out.gateway.pairing_code = gw["pairing_code"].get<std::string>();
    }
    if (j.contains("models") && j["models"].is_array()) {
      out.models.clear();
      for (const json& el : j["models"]) {
        if (!el.is_object()) continue;
        ModelEntry e;
        if (el.contains("id") && el["id"].is_string()) e.id = el["id"].get<std::string>();
        if (e.id.empty()) continue;
        if (el.contains("provider") && el["provider"].is_string()) e.provider = el["provider"].get<std::string>();
        if (el.contains("base_url") && el["base_url"].is_string()) e.base_url = el["base_url"].get<std::string>();
        if (el.contains("model_id") && el["model_id"].is_string()) e.model_id = el["model_id"].get<std::string>();
        if (e.model_id.empty()) e.model_id = e.id;
        if (el.contains("api_key_env") && el["api_key_env"].is_string()) e.api_key_env = el["api_key_env"].get<std::string>();
        if (el.contains("api_key") && el["api_key"].is_string()) e.api_key = el["api_key"].get<std::string>();
        out.models.push_back(std::move(e));
      }
    }
  } catch (const json::parse_error& e) {
    err = "JSON parse error: " + std::string(e.what());
    return false;
  }
  out.config_dir = path;
  const auto slash = path.find_last_of("/\\");
  if (slash != std::string::npos) {
    out.config_dir = path.substr(0, slash);
  }
  return true;
}

/** On Windows use backslash for paths so ifstream and paths are consistent. */
static std::string path_normalize(std::string path) {
#if defined(_WIN32)
  for (char& c : path) {
    if (c == '/') c = '\\';
  }
#endif
  return path;
}

/** Path separator for the platform (for joining dir + filename). */
static std::string path_sep() {
#if defined(_WIN32)
  return "\\";
#else
  return "/";
#endif
}

/** Expand leading ~ to home directory. */
static std::string expand_tilde(const std::string& path) {
  if (path.empty() || path[0] != '~') return path;
  const char* home = std::getenv("HOME");
#if defined(_WIN32)
  if (!home || !home[0]) home = std::getenv("USERPROFILE");
#endif
  if (!home || !home[0]) return path;
  if (path.size() == 1) return path_normalize(home);
  if (path[1] == '/' || path[1] == '\\') return path_normalize(std::string(home) + path.substr(1));
  return path;
}

/** Return HICLAW_WORKSPACE env with ~ expanded, or empty if not set. */
std::string get_workspace() {
  const char* v = std::getenv("HICLAW_WORKSPACE");
  if (!v || !v[0]) return "";
  return expand_tilde(v);
}

/** Default workspace: ~/.hiclaw (Windows: %USERPROFILE%\.hiclaw). */
std::string get_default_workspace() {
  return expand_tilde("~/.hiclaw");
}

/** Fallback defaults when provider not in built-in registry. */
static const char* fallbackBaseUrl(const std::string& provider) {
  if (provider == "ollama") return "http://localhost:11434";
  if (provider == "openai") return "https://api.openai.com/v1";
  if (provider == "anthropic") return "https://api.anthropic.com/v1";
  if (provider == "glm") return "https://open.bigmodel.cn/api/paas/v4";
  if (provider == "minimax") return "https://api.minimaxi.com/v1";
  if (provider == "qwen") return "https://dashscope.aliyuncs.com/compatible-mode/v1";
  if (provider == "kimi") return "https://api.moonshot.cn/v1";
  if (provider == "gemini") return "https://generativelanguage.googleapis.com/v1beta";
  if (provider == "openai_compatible" || provider == "custom") return "";
  return "";
}

static const char* fallbackApiKeyEnv(const std::string& provider) {
  if (provider == "openai") return "OPENAI_API_KEY";
  if (provider == "anthropic") return "ANTHROPIC_API_KEY";
  if (provider == "glm") return "GLM_API_KEY";
  if (provider == "minimax") return "MINIMAX_API_KEY";
  if (provider == "qwen") return "DASHSCOPE_API_KEY";
  if (provider == "kimi") return "KIMI_API_KEY";
  if (provider == "gemini") return "GEMINI_API_KEY";
  if (provider == "openai_compatible" || provider == "custom") return "OPENAI_API_KEY";
  return "";
}

std::map<std::string, ProviderMeta> load_provider_registry(const std::string& /*config_dir*/) {
  std::map<std::string, ProviderMeta> out;
  for (std::size_t i = 0; i < kDefaultProvidersCount; ++i) {
    const auto& e = kDefaultProviders[i];
    ProviderMeta meta;
    meta.id = e.id;
    meta.display_name = e.display_name;
    meta.default_base_url = e.default_base_url;
    meta.default_api_key_env = e.default_api_key_env;
    out[meta.id] = meta;
  }
  return out;
}

bool resolve_model(const Config& config,
                   std::string& out_base_url,
                   std::string& out_model_id,
                   std::string& out_api_key,
                   bool& out_use_openai_compatible) {
  out_api_key.clear();
  const std::string& key = config.default_model;
  if (key.empty()) {
    out_base_url = "http://localhost:11434";
    out_model_id = "llama3.2";
    out_use_openai_compatible = false;
    return true;
  }
  static std::string s_cached_config_dir;
  static std::map<std::string, ProviderMeta> s_registry;
  if (s_cached_config_dir != config.config_dir) {
    s_cached_config_dir = config.config_dir;
    s_registry = load_provider_registry(config.config_dir);
  }
  for (const ModelEntry& e : config.models) {
    if (e.id != key) continue;
    const char* base = nullptr;
    if (!e.base_url.empty()) {
      base = e.base_url.c_str();
    } else {
      auto it = s_registry.find(e.provider);
      if (it != s_registry.end() && !it->second.default_base_url.empty()) {
        base = it->second.default_base_url.c_str();
      }
      if (!base || base[0] == '\0') base = fallbackBaseUrl(e.provider);
    }
    if (!base || base[0] == '\0') {
      out_base_url = "http://localhost:8080";
    } else {
      out_base_url = base;
    }
    out_model_id = e.model_id.empty() ? e.id : e.model_id;
    if (!e.api_key.empty()) {
      out_api_key = e.api_key;
    } else {
      const char* env_key = nullptr;
      if (!e.api_key_env.empty()) {
        env_key = e.api_key_env.c_str();
      } else {
        auto it = s_registry.find(e.provider);
        if (it != s_registry.end() && !it->second.default_api_key_env.empty()) {
          env_key = it->second.default_api_key_env.c_str();
        }
        if (!env_key || env_key[0] == '\0') env_key = fallbackApiKeyEnv(e.provider);
      }
      if (env_key && env_key[0]) {
        const char* v = std::getenv(env_key);
        if (!v || !v[0]) v = std::getenv("OPENAI_API_KEY");
        if (v && v[0]) out_api_key = v;
      }
    }
    out_use_openai_compatible = (e.provider != "ollama");
    return true;
  }
  // Fallback: default_model set but models[] empty or no match - infer provider from "provider-model" (e.g. minimax-2.5 -> minimax)
  if (!key.empty()) {
    size_t hyphen = key.find('-');
    std::string provider = (hyphen != std::string::npos && hyphen > 0) ? key.substr(0, hyphen) : key;
    auto it = s_registry.find(provider);
    if (it != s_registry.end()) {
      const char* base = it->second.default_base_url.empty() ? fallbackBaseUrl(provider) : it->second.default_base_url.c_str();
      if (base && base[0]) {
        out_base_url = base;
        out_model_id = key;
        if (provider == "minimax" && key == "minimax-2.5") out_model_id = "MiniMax-M2.5";
        out_use_openai_compatible = (provider != "ollama");
        const char* env_key = it->second.default_api_key_env.empty() ? fallbackApiKeyEnv(provider) : it->second.default_api_key_env.c_str();
        if (env_key && env_key[0]) {
          const char* v = std::getenv(env_key);
          if (!v || !v[0]) v = std::getenv("OPENAI_API_KEY");
          if (v && v[0]) out_api_key = v;
        }
        return true;
      }
    }
  }
  // Fallback: no matching model entry, use ollama as default
  out_base_url = "http://localhost:11434";
  out_model_id = key;
  out_use_openai_compatible = false;
  return true;
}

bool load(const std::string& config_dir, Config& out, std::string& err) {
  out = Config{};
  std::string workspace = get_workspace();
  std::string dir;
  if (!workspace.empty()) {
    dir = path_normalize(workspace);
  } else {
    dir = path_normalize(config_dir.empty() ? get_default_workspace() : config_dir);
  }
  out.config_dir = dir;
  out.config_file = "hiclaw.json";
  std::string json_path = dir + path_sep() + "hiclaw.json";
  out.default_model = "gemma4:e4b";
  if (loadFromJson(json_path, out, err)) {
    ensure_default_in_models(out);
    return true;
  }
  err = "no config file at " + json_path + ", using defaults";
  ensure_default_in_models(out);
  return true;
}

void ensure_default_in_models(Config& cfg) {
  if (cfg.default_model.empty()) return;
  for (const auto& e : cfg.models)
    if (e.id == cfg.default_model) return;
  ModelEntry e;
  e.id = cfg.default_model;
  e.model_id = cfg.default_model;
  size_t hyphen = cfg.default_model.find('-');
  if (hyphen != std::string::npos && hyphen > 0) {
    std::string candidate = cfg.default_model.substr(0, hyphen);
    bool known = false;
    for (std::size_t i = 0; i < kDefaultProvidersCount; ++i) {
      if (candidate == kDefaultProviders[i].id) { known = true; break; }
    }
    e.provider = known ? candidate : "ollama";
  } else {
    e.provider = "ollama";
  }
  cfg.models.push_back(e);
}

bool save(const std::string& config_dir, const Config& cfg, std::string& err) {
  std::string dir = path_normalize(config_dir.empty() ? get_default_workspace() : config_dir);
  std::string filename = cfg.config_file.empty() ? "hiclaw.json" : cfg.config_file;
#if defined(_WIN32)
  _mkdir(dir.c_str());
#else
  mkdir(dir.c_str(), 0755);
#endif
  std::string json_path = dir + path_sep() + filename;
  try {
    json j;
    j["default_model"] = cfg.default_model;
    if (!cfg.system_prompt.empty()) j["system_prompt"] = cfg.system_prompt;
    j["models"] = json::array();
    for (const ModelEntry& e : cfg.models) {
      json m;
      m["id"] = e.id;
      m["provider"] = e.provider;
      if (!e.base_url.empty()) m["base_url"] = e.base_url;
      if (!e.model_id.empty() && e.model_id != e.id) m["model_id"] = e.model_id;
      if (!e.api_key_env.empty()) m["api_key_env"] = e.api_key_env;
      if (!e.api_key.empty()) m["api_key"] = e.api_key;
      j["models"].push_back(std::move(m));
    }
    // Gateway configuration
    json gw;
    gw["port"] = cfg.gateway.port;
    gw["host"] = cfg.gateway.host;
    gw["enabled"] = cfg.gateway.enabled;
    if (!cfg.gateway.pairing_code.empty()) gw["pairing_code"] = cfg.gateway.pairing_code;
    j["gateway"] = gw;
    std::ofstream f(json_path);
    if (!f) {
      err = "cannot write " + json_path;
      return false;
    }
    f << j.dump(2);
    if (!f) {
      err = "write failed";
      return false;
    }
  } catch (const json::exception& e) {
    err = "JSON error: " + std::string(e.what());
    return false;
  }
  return true;
}

}  // namespace config
}  // namespace hiclaw
