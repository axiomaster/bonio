#include "hiclaw/memory/memory.hpp"
#include "hiclaw/net/http_client.hpp"
#include "hiclaw/security/path_guard.hpp"
#include "hiclaw/skills/skill_manager.hpp"
#include "hiclaw/tools/memo_tool.hpp"
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

ToolResult web_search_impl(const std::string& args_json) {
  std::string query = get_arg(args_json, "query");
  if (query.empty()) return ToolResult{false, "", "missing 'query' argument"};
  int count = get_arg_int(args_json, "count", 5);
  if (count <= 0 || count > 20) count = 5;

  // URL-encode the query
  std::string encoded_query;
  for (char c : query) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
        c == '-' || c == '_' || c == '.' || c == '~') {
      encoded_query += c;
    } else if (c == ' ') {
      encoded_query += '+';
    } else {
      char hex[4];
      snprintf(hex, sizeof(hex), "%%%02X", static_cast<unsigned char>(c));
      encoded_query += hex;
    }
  }

  // Use DuckDuckGo HTML search (no API key required)
  std::string search_url = "https://html.duckduckgo.com/html/?q=" + encoded_query;
  net::HttpResponse res;
  if (!net::get(search_url, res))
    return ToolResult{false, "", res.error.empty() ? "search failed" : res.error};

  // Parse HTML response to extract search results
  std::ostringstream out;
  out << "Search results for \"" << query << "\":\n\n";

  // Simple HTML parsing to extract results
  std::string body = res.body;
  size_t pos = 0;
  int result_count = 0;

  // Look for result snippets: <a rel="nofollow" class="result__a" href="...">
  const std::string result_start = "<a rel=\"nofollow\" class=\"result__a\"";
  const std::string href_start = "href=\"";
  const std::string title_end_marker = "</a>";
  const std::string snippet_start = "<a class=\"result__snippet\"";
  const std::string snippet_end = "</a>";

  while ((pos = body.find(result_start, pos)) != std::string::npos && result_count < count) {
    // Extract URL
    size_t href_pos = body.find(href_start, pos);
    if (href_pos == std::string::npos) break;
    size_t url_start = href_pos + href_start.length();
    size_t url_end = body.find("\"", url_start);
    if (url_end == std::string::npos) break;
    std::string url = body.substr(url_start, url_end - url_start);

    // Skip DuckDuckGo redirect links
    if (url.find("/l/?uddg=") == 0) {
      // Extract real URL from redirect
      size_t real_url_start = url.find("uddg=");
      if (real_url_start != std::string::npos) {
        real_url_start += 5;
        size_t real_url_end = url.find("&", real_url_start);
        if (real_url_end == std::string::npos) real_url_end = url.length();
        // URL is encoded, decode basic %XX
        std::string real_url = url.substr(real_url_start, real_url_end - real_url_start);
        // Simple decode
        std::string decoded_url;
        for (size_t i = 0; i < real_url.length(); ++i) {
          if (real_url[i] == '%' && i + 2 < real_url.length()) {
            char hex[3] = {real_url[i+1], real_url[i+2], 0};
            unsigned char val = static_cast<unsigned char>(strtol(hex, nullptr, 16));
            decoded_url += val;
            i += 2;
          } else {
            decoded_url += real_url[i];
          }
        }
        url = decoded_url;
      } else {
        pos = url_end + 1;
        continue;
      }
    }

    // Extract title (between > and </a>)
    size_t title_start = body.find(">", url_end);
    if (title_start == std::string::npos) break;
    title_start += 1;
    size_t title_end = body.find(title_end_marker, title_start);
    if (title_end == std::string::npos) break;
    std::string title_html = body.substr(title_start, title_end - title_start);

    // Strip HTML tags from title
    std::string title;
    bool in_tag = false;
    for (char c : title_html) {
      if (c == '<') in_tag = true;
      else if (c == '>') in_tag = false;
      else if (!in_tag) title += c;
    }

    // Try to find snippet
    std::string snippet;
    size_t snippet_pos = body.find(snippet_start, title_end);
    if (snippet_pos != std::string::npos) {
      size_t snippet_content_start = body.find(">", snippet_pos);
      if (snippet_content_start != std::string::npos) {
        snippet_content_start += 1;
        size_t snippet_content_end = body.find(snippet_end, snippet_content_start);
        if (snippet_content_end != std::string::npos) {
          std::string snippet_html = body.substr(snippet_content_start, snippet_content_end - snippet_content_start);
          // Strip HTML tags from snippet
          in_tag = false;
          for (char c : snippet_html) {
            if (c == '<') in_tag = true;
            else if (c == '>') in_tag = false;
            else if (!in_tag && c != '\r' && c != '\n') snippet += c;
          }
        }
      }
    }

    // Format result
    out << "[" << (result_count + 1) << "] " << title << "\n";
    out << "    URL: " << url << "\n";
    if (!snippet.empty()) {
      // Truncate snippet if too long
      if (snippet.length() > 200) {
        snippet = snippet.substr(0, 197) + "...";
      }
      out << "    " << snippet << "\n";
    }
    out << "\n";

    result_count++;
    pos = title_end + title_end_marker.length();
  }

  if (result_count == 0) {
    out << "No results found. The search service may be unavailable.\n";
  } else {
    out << "Found " << result_count << " result(s).";
  }

  return ToolResult{true, out.str(), ""};
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
    "canvas.", "telephony.", "input.",
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
  register_tool("web_search", web_search_impl);
  register_tool("skill.read", skill_read_impl);
  register_tool("memo.save", [](const std::string& args_json) -> ToolResult { return memo_save(args_json); });
  register_tool("memo.list", [](const std::string& args_json) -> ToolResult { return memo_list(args_json); });
}

}  // namespace tools
}  // namespace hiclaw
