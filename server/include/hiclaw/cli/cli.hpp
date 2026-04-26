#ifndef HICLAW_CLI_CLI_HPP
#define HICLAW_CLI_CLI_HPP

#include <string>

namespace hiclaw {
namespace cli {

struct Options {
  bool show_version = false;
  bool show_help = false;
  std::string config_dir;
  std::string log_level;  // off|error|warn|info|debug|trace, or from hiclaw_log
  std::string subcommand;
  std::string cron_sub;   // list | add | run
  std::string cron_expr;  // for add
  std::string cron_prompt;// for add
  // gateway (sub: "" = WebSocket | "serve" = HTTP server)
  int gateway_port = 0;  // 0 = use config file value
  bool gateway_new_pairing = false;
  std::string gateway_sub;
  int gateway_serve_port = 0;  // 0 = use config file value
  // agent (sub: "" = interactive | "run" = single prompt)
  std::string agent_sub;
  std::string agent_prompt;  // for agent run
  // model (sub: list | status; config moved to hiclaw config)
  std::string model_sub;
  // skill (sub: list | install | remove)
  std::string skill_sub;
  std::string skill_path;   // for install: source directory
  std::string skill_id;     // for remove: skill id
  // wechat (sub: setup)
  std::string wechat_sub;
};

/**
 * Print structured help (zeroclaw-style) to stdout.
 * @param version Version string, e.g. "0.1.0"
 */
void print_help(const char* version = "0.1.0");

/**
 * Print help for 'hiclaw model' (when no subcommand or --help).
 */
void print_models_help();

/**
 * Parse command line. Returns false on error or --help.
 * When --help/-h is seen, sets out.show_help = true and prints help.
 */
bool parse(int argc, char* argv[], Options& out);

}  // namespace cli
}  // namespace hiclaw

#endif
