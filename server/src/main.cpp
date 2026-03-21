/**
 * hiclaw - HarmonyOS port of ZeroClaw (C++)
 * Entry point and command dispatch.
 */
#include "hiclaw/agent/agent.hpp"
#include "hiclaw/cli/cli.hpp"
#include "hiclaw/config/config.hpp"
#include "hiclaw/cron/schedule.hpp"
#include "hiclaw/cron/store.hpp"
#include "hiclaw/observability/log.hpp"
#include "hiclaw/net/serve.hpp"
#include "hiclaw/net/gateway.hpp"
#include "hiclaw/skills/skill_manager.hpp"
#include <cstdlib>
#include <chrono>
#include <ctime>
#include <iostream>
#include <string>
#include <cstdio>
#if defined(HICLAW_USE_LINENOISE)
#include <linenoise.h>
#if defined(_WIN32)
#include <io.h>
#define is_stdin_tty() (_isatty(_fileno(stdin)) != 0)
#else
#include <unistd.h>
#define is_stdin_tty() (isatty(STDIN_FILENO) != 0)
#endif
#endif

namespace {

const char* const hiclaw_version = "0.1.0";

/** Remove backspace/DEL and the character they erase, so ^H doesn't appear in line. */
static std::string strip_backspace(const std::string& line) {
  std::string out;
  out.reserve(line.size());
  for (unsigned char c : line) {
    if (c == 8 || c == 127) {  // \b or DEL
      if (!out.empty()) out.pop_back();
    } else {
      out.push_back(static_cast<char>(c));
    }
  }
  return out;
}

static void trim_line(std::string& s) {
  while (!s.empty() && (s.back() == '\r' || s.back() == '\n')) s.pop_back();
  while (!s.empty() && (s.front() == ' ' || s.front() == '\t')) s.erase(0, 1);
}

/** Read a line: use linenoise when TTY and HICLAW_USE_LINENOISE, else getline. Returns empty on EOF. */
static bool read_line(const char* prompt, std::string& out) {
  out.clear();
#if defined(HICLAW_USE_LINENOISE)
  if (is_stdin_tty()) {
    char* raw = linenoise(prompt);
    if (!raw) return false;
    out = raw;
    free(raw);
    trim_line(out);
    return true;
  }
#endif
  std::cout << prompt << std::flush;
  if (!std::getline(std::cin, out)) return false;
  out = strip_backspace(out);
  trim_line(out);
  return true;
}

void print_config_debug(const hiclaw::config::Config& cfg, const std::string& load_err) {
  std::string ws_env = hiclaw::config::get_workspace();
  std::string ws_display = cfg.config_dir;
  if (!ws_env.empty()) {
    ws_display = ws_env;
  } else if (cfg.config_dir == hiclaw::config::get_default_workspace()) {
    ws_display += " (default)";
  }
  std::cerr << "[hiclaw] workspace=" << ws_display << "\n";
  std::cerr << "[hiclaw] config=" << cfg.config_dir << "/" << cfg.config_file << "\n";
  std::cerr << "[hiclaw] default_model=" << (cfg.default_model.empty() ? "(none)" : cfg.default_model) << "\n";
  std::cerr << "[hiclaw] models count=" << cfg.models.size() << "\n";
  if (!load_err.empty()) {
    std::cerr << "[hiclaw] warning: " << load_err << "\n";
  }
}

}

int main(int argc, char* argv[]) {
  hiclaw::cli::Options opts;
  if (!hiclaw::cli::parse(argc, argv, opts)) {
    return opts.show_help ? 0 : 1;
  }

  if (!opts.log_level.empty()) {
    hiclaw::log::set_level(opts.log_level);
  } else if (const char* env = std::getenv("hiclaw_log")) {
    hiclaw::log::set_level(env);
  }

  if (opts.show_version) {
    std::cout << "HiClaw " << hiclaw_version << "\n";
    return 0;
  }

  if (opts.subcommand == "cron") {
    hiclaw::config::Config cfg;
    std::string err;
    if (!hiclaw::config::load(opts.config_dir, cfg, err)) {
      std::cerr << "config: " << err << "\n";
      return 1;
    }
    hiclaw::log::set_log_dir(cfg.config_dir);
    print_config_debug(cfg, err);
    std::string dir = cfg.config_dir.empty() ? hiclaw::config::get_default_workspace() : cfg.config_dir;
    hiclaw::skills::init_global(dir);
    if (opts.cron_sub == "list") {
      auto jobs = hiclaw::cron::load_jobs(dir);
      if (jobs.empty()) {
        std::cout << "No scheduled jobs. Add with: HiClaw cron add \"0 9 * * *\" \"your prompt\"\n";
        return 0;
      }
      std::cout << "Scheduled jobs (" << jobs.size() << "):\n";
      for (const auto& j : jobs) {
        std::cout << "  " << j.id << " | " << j.expr << " | next=" << j.next_run_iso << " | " << j.prompt << "\n";
      }
      return 0;
    }
    if (opts.cron_sub == "add") {
      if (opts.cron_expr.empty() || opts.cron_prompt.empty()) {
        std::cerr << "HiClaw cron add \"<expr>\" \"<prompt>\"\n";
        return 1;
      }
      std::string id = hiclaw::cron::add_job(dir, opts.cron_expr, opts.cron_prompt);
      if (id.empty()) {
        std::cerr << "Invalid cron expression or save failed.\n";
        return 1;
      }
      std::cout << "Added job " << id << "\n";
      return 0;
    }
    if (opts.cron_sub == "run") {
      auto jobs = hiclaw::cron::load_jobs(dir);
      std::time_t now = std::time(nullptr);
      int ran = 0;
      for (const auto& j : jobs) {
        if (j.next_run == 0 || j.next_run > now) continue;
        hiclaw::agent::RunResult result = hiclaw::agent::run(cfg, j.prompt, 0.7);
        std::cout << "[" << j.id << "] " << (result.ok ? result.content : result.error) << "\n";
        std::time_t next = hiclaw::cron::next_run_after(j.expr, now);
        hiclaw::cron::update_job_next_run(dir, j.id, next);
        ran++;
      }
      if (ran == 0) std::cout << "No due jobs.\n";
      return 0;
    }
    std::cerr << "HiClaw cron: use list | add \"expr\" \"prompt\" | run\n";
    return 1;
  }

  if (opts.subcommand == "gateway") {
    hiclaw::config::Config cfg;
    std::string err;
    if (!hiclaw::config::load(opts.config_dir, cfg, err)) {
      std::cerr << "config: " << err << "\n";
      return 1;
    }
    hiclaw::log::set_log_dir(cfg.config_dir);
    print_config_debug(cfg, err);
    std::string ws_dir = cfg.config_dir.empty() ? hiclaw::config::get_default_workspace() : cfg.config_dir;
    hiclaw::skills::init_global(ws_dir);

    // Check if gateway is enabled in config
    if (!cfg.gateway.enabled) {
      std::cerr << "Gateway is disabled in configuration (gateway.enabled = false)\n";
      return 1;
    }

    if (opts.gateway_sub == "serve") {
      // Use command line port if specified, otherwise use config file port
      int serve_port = (opts.gateway_serve_port > 0) ? opts.gateway_serve_port : cfg.gateway.port;
      hiclaw::net::serve(serve_port, cfg);
      return 0;
    }

    // Use command line port if specified, otherwise use config file port
    int gateway_port = (opts.gateway_port > 0) ? opts.gateway_port : cfg.gateway.port;

    std::string pairing_code;
    // Prefer command line --new-pairing, then config pairing_code, then generate
    if (opts.gateway_new_pairing) {
      pairing_code = hiclaw::net::gateway_generate_pairing_code();
      std::cout << "Pairing code: " << pairing_code << "\n";
    } else if (!cfg.gateway.pairing_code.empty()) {
      pairing_code = cfg.gateway.pairing_code;
    }
    std::cout << "HiClaw gateway on port " << gateway_port << " (host: " << cfg.gateway.host << ")\n";
    hiclaw::net::gateway_run(gateway_port, cfg, pairing_code);
    return 0;
  }

  if (opts.subcommand == "agent") {
    hiclaw::config::Config cfg;
    std::string err;
    if (!hiclaw::config::load(opts.config_dir, cfg, err)) {
      std::cerr << "config: " << err << "\n";
      return 1;
    }
    hiclaw::log::set_log_dir(cfg.config_dir);
    print_config_debug(cfg, err);
    {
      std::string dir = cfg.config_dir.empty() ? hiclaw::config::get_default_workspace() : cfg.config_dir;
      hiclaw::skills::init_global(dir);
    }
    if (opts.agent_sub == "run") {
      if (opts.agent_prompt.empty()) {
        std::cerr << "HiClaw agent run <prompt>\n";
        return 1;
      }
      hiclaw::agent::RunResult result = hiclaw::agent::run(cfg, opts.agent_prompt, 0.7);
      if (!result.ok) {
        std::cerr << "error: " << result.error << "\n";
        return 1;
      }
      std::cout << result.content << "\n";
      return 0;
    }
    if (opts.agent_sub.empty()) {
      if (opts.log_level.empty() && !std::getenv("hiclaw_log")) {
        hiclaw::log::set_level("info");
      }
      std::cout << "HiClaw agent (interactive). Type your message and press Enter. 'exit' or 'quit' to end.\n";
      for (;;) {
        std::cout << "> " << std::flush;
        std::string line;
        if (!std::getline(std::cin, line)) break;
        line = strip_backspace(line);
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) line.pop_back();
        while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) line.erase(0, 1);
        if (line.empty()) continue;
        if (line == "exit" || line == "quit") break;
        std::cout << "[request] " << line << "\n";
        std::cout << "[thinking] waiting for model...\n" << std::flush;
        hiclaw::agent::RunResult result = hiclaw::agent::run(cfg, line, 0.7);
        if (!result.ok) {
          std::cout << "[error] " << result.error << "\n";
          continue;
        }
        std::cout << "[model]\n" << result.content << "\n\n";
      }
      return 0;
    }
    std::cerr << "HiClaw agent: use 'agent' (interactive) or 'agent run <prompt>'.\n";
    return 1;
  }

  if (opts.subcommand == "config") {
    hiclaw::config::Config cfg;
    std::string err;
    if (!hiclaw::config::load(opts.config_dir, cfg, err)) {
      std::cerr << "config: " << err << "\n";
      return 1;
    }
    hiclaw::log::set_log_dir(cfg.config_dir);
    print_config_debug(cfg, err);
    std::string dir = cfg.config_dir.empty() ? hiclaw::config::get_default_workspace() : cfg.config_dir;
    auto registry = hiclaw::config::load_provider_registry(dir);
    std::cout << "HiClaw config (interactive). Commands: model | exit\n";
    for (;;) {
      std::string line;
      if (!read_line("config> ", line)) break;
      if (line.empty()) continue;
      if (line == "exit" || line == "quit") break;
      if (line == "model") {
        std::string provider_type, id, base_url, model_id, api_key, set_default;
        std::string prompt_pt;
        if (registry.empty()) {
          prompt_pt = "Provider type (ollama|openai|anthropic|glm|minimax|qwen|kimi|gemini|openai_compatible): ";
        } else {
          prompt_pt = "Provider type (";
          bool first = true;
          for (const auto& kv : registry) {
            if (!first) prompt_pt += "|";
            prompt_pt += kv.first;
            first = false;
          }
          prompt_pt += "): ";
        }
        if (!read_line(prompt_pt.c_str(), provider_type)) break;
        if (!read_line("Model id (e.g. glm-4): ", id)) break;
        if (id.empty()) { std::cerr << "id is required.\n"; continue; }
        if (!read_line("Base URL (optional, Enter for default): ", base_url)) break;
        if (!read_line(std::string("API model_id (optional, default=" + id + "): ").c_str(), model_id)) break;
        if (!read_line("API key (optional, stored as api_key in config): ", api_key)) break;
        if (!read_line("Set as default model? (y/n): ", set_default)) break;

        bool found = false;
        for (auto& e : cfg.models) {
          if (e.id == id) {
            e.provider = provider_type.empty() ? e.provider : provider_type;
            if (!base_url.empty()) e.base_url = base_url;
            e.model_id = model_id.empty() ? id : model_id;
            if (!api_key.empty()) e.api_key = api_key;
            found = true;
            break;
          }
        }
        if (!found) {
          hiclaw::config::ModelEntry e;
          e.id = id;
          e.provider = provider_type.empty() ? "openai_compatible" : provider_type;
          e.base_url = base_url;
          e.model_id = model_id.empty() ? id : model_id;
          e.api_key = api_key;
          cfg.models.push_back(e);
        }
        if (set_default == "y" || set_default == "Y") cfg.default_model = id;
        hiclaw::config::ensure_default_in_models(cfg);
        if (!hiclaw::config::save(dir, cfg, err)) {
          std::cerr << "Save failed: " << err << "\n";
        } else {
          std::cout << "Saved. Default model: " << cfg.default_model << "\n";
        }
        continue;
      }
      std::cout << "Unknown command. Use: model | exit\n";
    }
    return 0;
  }

  if (opts.subcommand == "model") {
    if (opts.model_sub.empty()) {
      hiclaw::cli::print_models_help();
      return 0;
    }
    std::string dir = hiclaw::config::get_default_workspace();
    auto registry = hiclaw::config::load_provider_registry(dir);

    auto provider_display_name = [&registry](const std::string& p) -> std::string {
      auto it = registry.find(p);
      if (it != registry.end() && !it->second.display_name.empty())
        return it->second.display_name;
      return p;
    };

    if (opts.model_sub == "list") {
      // List all system-supported providers
      std::cout << "Supported providers:\n";
      for (const auto& kv : registry) {
        std::cout << "  " << kv.second.display_name;
        if (!kv.second.default_base_url.empty()) {
          std::cout << " (" << kv.second.default_base_url << ")";
        }
        std::cout << "\n";
      }
      return 0;
    }

    // For status, load config
    hiclaw::config::Config cfg;
    std::string err;
    if (!hiclaw::config::load(opts.config_dir, cfg, err)) {
      std::cerr << "config: " << err << "\n";
      return 1;
    }
    hiclaw::log::set_log_dir(cfg.config_dir);
    print_config_debug(cfg, err);

    if (opts.model_sub == "status") {
      if (cfg.models.empty()) {
        std::cout << "No models configured. Add with: hiclaw config\n";
        return 0;
      }
      std::cout << "Configured models:\n";
      for (const auto& e : cfg.models) {
        std::cout << "  " << e.id << " (" << provider_display_name(e.provider) << ")";
        if (e.id == cfg.default_model) {
          std::cout << " *";
        }
        std::cout << "\n";
      }
      return 0;
    }

    std::cerr << "HiClaw model: use list | status.\n";
    return 1;
  }

  if (opts.subcommand == "skill") {
    hiclaw::config::Config cfg;
    std::string err;
    if (!hiclaw::config::load(opts.config_dir, cfg, err)) {
      std::cerr << "config: " << err << "\n";
      return 1;
    }
    std::string dir = cfg.config_dir.empty() ? hiclaw::config::get_default_workspace() : cfg.config_dir;
    hiclaw::skills::SkillManager mgr(dir);

    if (opts.skill_sub == "install") {
      std::string result = mgr.install(opts.skill_path);
      if (!result.empty()) {
        std::cerr << "Install failed: " << result << "\n";
        return 1;
      }
      std::cout << "Skill installed successfully. Run 'hiclaw skill list' to verify.\n";
      return 0;
    }

    if (opts.skill_sub == "remove") {
      if (!mgr.remove(opts.skill_id)) {
        std::cerr << "Skill '" << opts.skill_id << "' not found in installed skills.\n";
        return 1;
      }
      std::cout << "Skill '" << opts.skill_id << "' removed.\n";
      return 0;
    }

    if (opts.skill_sub == "enable") {
      mgr.load_all();
      if (!mgr.enable(opts.skill_id)) {
        std::cerr << "Skill '" << opts.skill_id << "' not found or already enabled.\n";
        return 1;
      }
      std::cout << "Skill '" << opts.skill_id << "' enabled.\n";
      return 0;
    }

    if (opts.skill_sub == "disable") {
      mgr.load_all();
      if (!mgr.disable(opts.skill_id)) {
        std::cerr << "Skill '" << opts.skill_id << "' not found or already disabled.\n";
        return 1;
      }
      std::cout << "Skill '" << opts.skill_id << "' disabled.\n";
      return 0;
    }

    // Default: list
    mgr.load_all();
    const auto& skills = mgr.skills();
    if (skills.empty()) {
      std::cout << "No skills loaded.\n"
                << "  Builtin skills dir:   " << dir << "/skills/builtin/\n"
                << "  Installed skills dir: " << dir << "/skills/installed/\n";
      return 0;
    }
    std::cout << "Loaded skills (" << skills.size() << "):\n";
    for (const auto& s : skills) {
      std::cout << "  " << s.id << " - " << s.name
                << (s.builtin ? " [builtin]" : " [installed]")
                << (s.enabled ? "" : " [disabled]") << "\n";
      if (!s.description.empty()) {
        std::cout << "    " << s.description << "\n";
      }
    }
    return 0;
  }

  if (opts.subcommand.empty()) {
    hiclaw::cli::print_help(hiclaw_version);
    return 1;
  }

  std::cerr << "HiClaw: unknown subcommand '" << opts.subcommand << "'.\n";
  return 1;
}
