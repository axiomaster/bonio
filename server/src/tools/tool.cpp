#include "hiclaw/memory/memory.hpp"
#include "hiclaw/net/http_client.hpp"
#include "hiclaw/security/path_guard.hpp"
#include "hiclaw/skills/skill_manager.hpp"
#include "hiclaw/tools/tool.hpp"
#include <nlohmann/json.hpp>
#include <cstdio>
#include <fstream>
#include <map>
#include <sstream>
#include <cstdlib>
#include <cstring>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#endif

namespace hiclaw {
namespace tools {

namespace {

std::map<std::string, ToolExecutor>& registry() {
  static std::map<std::string, ToolExecutor> r;
  return r;
}

static std::string get_arg(const std::string& args_json, const char* key) {
  try {
    nlohmann::json j = nlohmann::json::parse(args_json);
    if (j.is_object() && j.contains(key) && j[key].is_string())
      return j[key].get<std::string>();
  } catch (const nlohmann::json::parse_error&) {}
  return "";
}

static int get_arg_int(const std::string& args_json, const char* key, int default_val) {
  try {
    nlohmann::json j = nlohmann::json::parse(args_json);
    if (j.is_object() && j.contains(key) && j[key].is_number_integer())
      return j[key].get<int>();
  } catch (const nlohmann::json::parse_error&) {}
  return default_val;
}

ToolResult memory_store_impl(const std::string& args_json) {
  std::string key = get_arg(args_json, "key");
  std::string content = get_arg(args_json, "content");
  std::string category = get_arg(args_json, "category");
  if (key.empty()) return ToolResult{false, "", "missing 'key' argument"};
  if (content.empty()) return ToolResult{false, "", "missing 'content' argument"};
  if (category.empty()) category = "core";
  if (!memory::store(key, content, category))
    return ToolResult{false, "", "failed to store memory"};
  return ToolResult{true, "Stored memory: " + key, ""};
}

ToolResult memory_recall_impl(const std::string& args_json) {
  std::string query = get_arg(args_json, "query");
  int limit = get_arg_int(args_json, "limit", 5);
  if (limit <= 0 || limit > 50) limit = 5;
  std::vector<memory::MemoryEntry> entries = memory::recall(query, static_cast<size_t>(limit));
  if (entries.empty())
    return ToolResult{true, "No memories found matching that query.", ""};
  std::ostringstream out;
  out << "Found " << entries.size() << " memories:\n";
  for (const auto& e : entries)
    out << "- [" << e.category << "] " << e.key << ": " << e.content << "\n";
  return ToolResult{true, out.str(), ""};
}

ToolResult memory_forget_impl(const std::string& args_json) {
  std::string key = get_arg(args_json, "key");
  if (key.empty()) return ToolResult{false, "", "missing 'key' argument"};
  if (memory::forget(key))
    return ToolResult{true, "Forgot memory: " + key, ""};
  return ToolResult{true, "No memory found with key: " + key, ""};
}

ToolResult web_fetch_impl(const std::string& args_json) {
  std::string url = get_arg(args_json, "url");
  if (url.empty()) return ToolResult{false, "", "missing 'url' argument"};
  bool is_http = url.size() >= 7 && url.compare(0, 7, "http://") == 0;
  bool is_https = url.size() >= 8 && url.compare(0, 8, "https://") == 0;
  if (!is_http && !is_https)
    return ToolResult{false, "", "only http:// and https:// URLs allowed"};
  net::HttpResponse res;
  if (!net::get(url, res))
    return ToolResult{false, "", res.error.empty() ? "fetch failed" : res.error};
  return ToolResult{true, res.body, ""};
}

ToolResult shell_impl(const std::string& args_json) {
  std::string command = get_arg(args_json, "command");
  if (command.empty()) {
    return ToolResult{false, "", "missing 'command' argument"};
  }
#ifdef _WIN32
  FILE* p = _popen(command.c_str(), "r");
  if (!p) return ToolResult{false, "", "popen failed"};
  std::string out;
  char buf[256];
  while (fgets(buf, sizeof(buf), p)) out += buf;
  _pclose(p);
  return ToolResult{true, out, ""};
#else
  int fd[2];
  if (pipe(fd) != 0) return ToolResult{false, "", "pipe failed"};
  pid_t pid = fork();
  if (pid < 0) return ToolResult{false, "", "fork failed"};
  if (pid == 0) {
    close(fd[0]);
    dup2(fd[1], STDOUT_FILENO);
    dup2(fd[1], STDERR_FILENO);
    close(fd[1]);
    execl("/bin/sh", "sh", "-c", command.c_str(), nullptr);
    _exit(127);
  }
  close(fd[1]);
  std::string out;
  char buf[256];
  for (;;) {
    ssize_t n = read(fd[0], buf, sizeof(buf));
    if (n <= 0) break;
    out.append(buf, static_cast<size_t>(n));
  }
  close(fd[0]);
  waitpid(pid, nullptr, 0);
  return ToolResult{true, out, ""};
#endif
}

ToolResult file_read_impl(const std::string& args_json) {
  std::string path = get_arg(args_json, "path");
  if (path.empty()) {
    return ToolResult{false, "", "missing 'path' argument"};
  }
  if (!security::is_path_allowed(path))
    return ToolResult{false, "", "path not allowed (sensitive directory)"};
  std::ifstream f(path);
  if (!f) return ToolResult{false, "", "cannot open file: " + path};
  std::ostringstream buf;
  buf << f.rdbuf();
  return ToolResult{true, buf.str(), ""};
}

ToolResult file_write_impl(const std::string& args_json) {
  std::string path = get_arg(args_json, "path");
  std::string content = get_arg(args_json, "content");
  if (path.empty()) return ToolResult{false, "", "missing 'path' argument"};
  if (!security::is_path_allowed(path))
    return ToolResult{false, "", "path not allowed (sensitive directory)"};
  std::ofstream f(path);
  if (!f) return ToolResult{false, "", "cannot write file: " + path};
  f << content;
  return ToolResult{true, "ok", ""};
}

ToolResult skill_read_impl(const std::string& args_json) {
  std::string name = get_arg(args_json, "name");
  if (name.empty()) return ToolResult{false, "", "missing 'name' argument"};
  auto* mgr = skills::instance();
  if (!mgr) return ToolResult{false, "", "skill system not initialized"};
  const auto* skill = mgr->find(name);
  if (!skill) return ToolResult{false, "", "skill not found: " + name};
  return ToolResult{true, skill->body, ""};
}

}  // namespace

void register_tool(const std::string& name, ToolExecutor exec) {
  registry()[name] = std::move(exec);
}

ToolResult run_tool(const std::string& name, const std::string& args_json) {
  auto it = registry().find(name);
  if (it == registry().end()) return ToolResult{false, "", "unknown tool: " + name};
  return it->second(args_json);
}

std::vector<std::string> list_tool_names() {
  std::vector<std::string> names;
  for (const auto& p : registry()) names.push_back(p.first);
  return names;
}

bool is_remote_tool(const std::string& name) {
  static const char* remote_prefixes[] = {
    "screen.", "camera.", "location.", "device.", "notifications.",
    "system.", "sms.", "photos.", "contacts.", "calendar.", "motion.",
    "canvas.",
    nullptr
  };
  for (const char** p = remote_prefixes; *p; ++p) {
    size_t len = std::strlen(*p);
    if (name.size() >= len && name.compare(0, len, *p) == 0)
      return true;
  }
  return false;
}

void register_builtin_tools() {
  static bool done = false;
  if (done) return;
  done = true;
  register_tool("shell", shell_impl);
  register_tool("file_read", file_read_impl);
  register_tool("file_write", file_write_impl);
  register_tool("memory_store", memory_store_impl);
  register_tool("memory_recall", memory_recall_impl);
  register_tool("memory_forget", memory_forget_impl);
  register_tool("web_fetch", web_fetch_impl);
  register_tool("skill.read", skill_read_impl);
}

}  // namespace tools
}  // namespace hiclaw
