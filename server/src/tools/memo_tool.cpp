#include "hiclaw/tools/memo_tool.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <mutex>

namespace hiclaw {
namespace tools {

namespace {

using json = nlohmann::json;
namespace fs = std::filesystem;

std::mutex memo_mutex_;
std::string memo_dir_cache_;

std::string get_memo_dir() {
  if (memo_dir_cache_.empty()) {
    const char* home = nullptr;
#if defined(_WIN32)
    home = std::getenv("USERPROFILE");
    if (!home) home = std::getenv("HOME");
#else
    home = std::getenv("HOME");
#endif
    if (!home) home = "/tmp";
    memo_dir_cache_ = (fs::path(home) / ".bonio" / "memos").string();
  }
  std::error_code ec;
  fs::create_directories(memo_dir_cache_, ec);
  return memo_dir_cache_;
}

std::string timestamp_id() {
  auto now = std::chrono::system_clock::now();
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
  return std::to_string(ms);
}

}  // namespace

types::ToolResult memo_save(const std::string& args_json) {
  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  std::lock_guard<std::mutex> lock(memo_mutex_);

  std::string title = params.contains("title") && params["title"].is_string()
                          ? params["title"].get<std::string>()
                          : "Untitled";
  std::string content = params.contains("content") && params["content"].is_string()
                            ? params["content"].get<std::string>()
                            : "";
  std::string source = params.contains("source") && params["source"].is_string()
                           ? params["source"].get<std::string>()
                           : "screen";

  if (content.empty()) {
    return types::ToolResult{false, "", "content is required"};
  }

  std::string id = timestamp_id();
  json memo;
  memo["id"] = id;
  memo["title"] = title;
  memo["content"] = content;
  memo["source"] = source;
  memo["timestamp"] = id;

  std::string filepath = (fs::path(get_memo_dir()) / (id + ".json")).string();
  std::ofstream f(filepath);
  if (!f) {
    return types::ToolResult{false, "", "failed to save memo"};
  }
  f << memo.dump(2);
  f.close();

  log::info("memo_tool: saved memo " + id + ": " + title);

  json result;
  result["saved"] = true;
  result["id"] = id;
  result["title"] = title;
  return types::ToolResult{true, result.dump(), ""};
}

types::ToolResult memo_list(const std::string& args_json) {
  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  std::lock_guard<std::mutex> lock(memo_mutex_);

  int limit = 20;
  if (params.contains("limit") && params["limit"].is_number_integer()) {
    limit = params["limit"].get<int>();
  }
  if (limit <= 0 || limit > 200) limit = 20;

  json memos = json::array();
  std::string dir = get_memo_dir();

  if (!fs::exists(dir)) {
    json result;
    result["memos"] = memos;
    result["count"] = 0;
    return types::ToolResult{true, result.dump(), ""};
  }

  std::vector<fs::path> paths;
  for (const auto& entry : fs::directory_iterator(dir)) {
    if (entry.path().extension() == ".json") paths.push_back(entry.path());
  }

  std::sort(paths.begin(), paths.end(), [](const fs::path& a, const fs::path& b) {
    std::error_code ec;
    return fs::last_write_time(a, ec) > fs::last_write_time(b, ec);
  });

  int count = 0;
  for (const auto& p : paths) {
    if (count >= limit) break;
    try {
      std::ifstream f(p.string());
      json memo = json::parse(f);
      memos.push_back(std::move(memo));
      count++;
    } catch (...) {
      continue;
    }
  }

  json result;
  result["memos"] = memos;
  result["count"] = count;
  return types::ToolResult{true, result.dump(), ""};
}

}  // namespace tools
}  // namespace hiclaw
