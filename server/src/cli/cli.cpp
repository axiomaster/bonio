#include "hiclaw/cli/cli.hpp"
#include <CLI/CLI.hpp>
#include <iostream>

namespace hiclaw {
namespace cli {

void print_help(const char* version) {
  std::cout << "HiClaw " << version << " - HarmonyOS AI assistant.\n\n"
            << "Usage: HiClaw [OPTIONS] <COMMAND>\n\n"
            << "Commands:\n"
            << "  cron    Configure and run scheduled tasks (list, add, run)\n"
            << "  gateway WebSocket gateway or HTTP server (gateway [options] | gateway serve [port])\n"
            << "  agent   Run or serve the AI agent (agent | agent run <prompt>)\n"
            << "  config  Interactive configuration (add/edit models, etc.)\n"
            << "  model   List supported providers or show configured models (list, status)\n"
            << "  skill   Manage skill packages (list, install, remove, enable, disable)\n"
            << "  wechat  WeChat integration (setup)\n\n"
            << "Options:\n"
            << "      --config-dir <path>    Config directory (default: ~/.bonio, Windows: %%USERPROFILE%%\\.bonio)\n"
            << "      --log-level <level>    off|error|warn|info|debug|trace\n"
            << "  -h, --help                 Print this message\n"
            << "  -V, --version              Print version\n";
}

void print_models_help() {
  std::cout << "HiClaw model - list supported providers or show configured models.\n\n"
            << "Usage: hiclaw model [SUBCOMMAND]\n\n"
            << "Subcommands:\n"
            << "  list    List all system-supported providers\n"
            << "  status  Show configured models (with √ marking the default)\n\n"
            << "To add or edit models, use: hiclaw config (interactive).\n"
            << "  -h, --help    Print this message\n";
}

static void build_app(CLI::App& app, Options& out) {
  app.description("HiClaw - HarmonyOS AI assistant.");
  app.add_flag("--version,-V", out.show_version, "Print version");
  app.add_option("--config-dir", out.config_dir, "Config directory (default: ~/.bonio)");
  app.add_option("--log-level", out.log_level, "off|error|warn|info|debug|trace");

  auto* cron_cmd = app.add_subcommand("cron", "Configure and run scheduled tasks (list, add, run)");
  auto* cron_list = cron_cmd->add_subcommand("list", "List scheduled jobs");
  auto* cron_add = cron_cmd->add_subcommand("add", "Add a job: add \"<expr>\" \"<prompt>\"");
  cron_add->add_option("expr", out.cron_expr, "Cron expression (e.g. 0 9 * * *)")->required();
  cron_add->add_option("prompt", out.cron_prompt, "Prompt for the job")->required();
  cron_cmd->add_subcommand("run", "Run due jobs");

  auto* gateway_cmd = app.add_subcommand("gateway", "WebSocket gateway or HTTP server");
  gateway_cmd->add_option("--port", out.gateway_port, "WebSocket port (default: from config)");
  gateway_cmd->add_flag("--new-pairing", out.gateway_new_pairing, "Generate new pairing code");
  auto* gateway_serve = gateway_cmd->add_subcommand("serve", "Run HTTP server");
  gateway_serve->add_option("port", out.gateway_serve_port, "HTTP port (default: from config)");

  auto* agent_cmd = app.add_subcommand("agent", "Run or serve the AI agent");
  auto* agent_run = agent_cmd->add_subcommand("run", "Run single prompt");
  agent_run->add_option("prompt", out.agent_prompt, "Prompt text")->required();

  app.add_subcommand("config", "Interactive configuration (add/edit models, etc.)");

  auto* model_cmd = app.add_subcommand("model", "Manage models (list, status)");
  model_cmd->add_subcommand("list", "List all models and their provider");
  model_cmd->add_subcommand("status", "Show current model configuration");

  auto* skill_cmd = app.add_subcommand("skill", "Manage skill packages (list, install, remove, enable, disable)");
  skill_cmd->add_subcommand("list", "List loaded skills and their status");
  auto* skill_install = skill_cmd->add_subcommand("install", "Install a skill from a directory");
  skill_install->add_option("path", out.skill_path, "Path to skill directory (must contain SKILL.md)")->required();
  auto* skill_remove = skill_cmd->add_subcommand("remove", "Remove an installed skill by id");
  skill_remove->add_option("id", out.skill_id, "Skill id to remove")->required();
  auto* skill_enable = skill_cmd->add_subcommand("enable", "Enable a disabled skill");
  skill_enable->add_option("id", out.skill_id, "Skill id to enable")->required();
  auto* skill_disable = skill_cmd->add_subcommand("disable", "Disable a skill");
  skill_disable->add_option("id", out.skill_id, "Skill id to disable")->required();

  auto* wechat_cmd = app.add_subcommand("wechat", "WeChat integration (setup)");
  wechat_cmd->add_subcommand("setup", "Print WeChat setup instructions");
}

static void fill_options_from_parsed(CLI::App& app, Options& out) {
  auto* cron = app.get_subcommand("cron");
  if (cron && cron->parsed()) {
    out.subcommand = "cron";
    if (auto* s = cron->get_subcommand("list"); s && s->parsed()) out.cron_sub = "list";
    else if (auto* s = cron->get_subcommand("add"); s && s->parsed()) out.cron_sub = "add";
    else if (auto* s = cron->get_subcommand("run"); s && s->parsed()) out.cron_sub = "run";
  }
  auto* gateway = app.get_subcommand("gateway");
  if (gateway && gateway->parsed()) {
    out.subcommand = "gateway";
    if (auto* s = gateway->get_subcommand("serve"); s && s->parsed()) out.gateway_sub = "serve";
  }
  auto* agent = app.get_subcommand("agent");
  if (agent && agent->parsed()) {
    out.subcommand = "agent";
    if (auto* s = agent->get_subcommand("run"); s && s->parsed()) out.agent_sub = "run";
  }
  if (auto* c = app.get_subcommand("config"); c && c->parsed()) out.subcommand = "config";
  auto* model = app.get_subcommand("model");
  if (model && model->parsed()) {
    out.subcommand = "model";
    if (auto* s = model->get_subcommand("list"); s && s->parsed()) out.model_sub = "list";
    else if (auto* s = model->get_subcommand("status"); s && s->parsed()) out.model_sub = "status";
  }
  auto* skill = app.get_subcommand("skill");
  if (skill && skill->parsed()) {
    out.subcommand = "skill";
    if (auto* s = skill->get_subcommand("list"); s && s->parsed()) out.skill_sub = "list";
    else if (auto* s = skill->get_subcommand("install"); s && s->parsed()) out.skill_sub = "install";
    else if (auto* s = skill->get_subcommand("remove"); s && s->parsed()) out.skill_sub = "remove";
    else if (auto* s = skill->get_subcommand("enable"); s && s->parsed()) out.skill_sub = "enable";
    else if (auto* s = skill->get_subcommand("disable"); s && s->parsed()) out.skill_sub = "disable";
  }
  if (auto* c = app.get_subcommand("wechat"); c && c->parsed()) {
    out.subcommand = "wechat";
    if (auto* s = c->get_subcommand("setup"); s && s->parsed()) out.wechat_sub = "setup";
  }
}

bool parse(int argc, char* argv[], Options& out) {
  out = Options{};
  CLI::App app;
  build_app(app, out);

  try {
    app.parse(argc, argv);
  } catch (const CLI::CallForHelp&) {
    out.show_help = true;
    std::cout << app.help();
    return false;
  } catch (const CLI::CallForVersion&) {
    out.show_version = true;
    return false;
  } catch (const CLI::ParseError& e) {
    std::cerr << "HiClaw: " << e.what() << "\n";
    return false;
  }

  fill_options_from_parsed(app, out);
  return true;
}

}  // namespace cli
}  // namespace hiclaw
