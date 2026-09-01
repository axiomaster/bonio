#include "hiclaw/tools/memo_tool.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
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
  static int64_t last_ms = 0;
  if (ms <= last_ms) ms = last_ms + 1;
  last_ms = ms;
  return std::to_string(ms);
}

bool valid_memo_id(const std::string& id) {
  if (id.empty() || id.size() > 128) return false;
  return std::all_of(id.begin(), id.end(), [](unsigned char c) {
    return std::isalnum(c) || c == '-' || c == '_';
  });
}

std::string optional_string(const json& params, const char* key) {
  return params.contains(key) && params[key].is_string()
             ? params[key].get<std::string>()
             : "";
}

json normalized_memo(json memo) {
  if (!memo.contains("createdAt")) {
    std::string timestamp = memo.value("timestamp", memo.value("id", "0"));
    try {
      memo["createdAt"] = std::stoll(timestamp);
    } catch (...) {
      memo["createdAt"] = 0;
    }
  }
  if (!memo.contains("tags") || !memo["tags"].is_array()) memo["tags"] = json::array();
  if (!memo.contains("sourceApp")) memo["sourceApp"] = "";
  if (!memo.contains("pageTitle")) memo["pageTitle"] = "";
  if (!memo.contains("pageLink")) memo["pageLink"] = "";
  if (!memo.contains("coverImage")) memo["coverImage"] = "";
  return memo;
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

  std::string title = optional_string(params, "title");
  std::string content = optional_string(params, "content");
  std::string source = optional_string(params, "source");
  if (title.empty()) title = "Untitled";
  if (source.empty()) source = "screen";

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
  memo["createdAt"] = std::stoll(id);
  memo["sourceApp"] = optional_string(params, "sourceApp");
  memo["pageTitle"] = optional_string(params, "pageTitle");
  memo["pageLink"] = optional_string(params, "pageLink");
  memo["coverImage"] = optional_string(params, "coverImage");
  memo["tags"] = json::array();
  if (params.contains("tags") && params["tags"].is_array()) {
    for (const auto& tag : params["tags"]) {
      if (tag.is_string() && !tag.get<std::string>().empty()) memo["tags"].push_back(tag);
    }
  }

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
      memos.push_back(normalized_memo(std::move(memo)));
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

types::ToolResult memo_get(const std::string& args_json) {
  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  const std::string id = optional_string(params, "id");
  if (!valid_memo_id(id)) return types::ToolResult{false, "", "invalid memo id"};

  std::lock_guard<std::mutex> lock(memo_mutex_);
  const fs::path path = fs::path(get_memo_dir()) / (id + ".json");
  if (!fs::exists(path)) return types::ToolResult{false, "", "memo not found"};
  try {
    std::ifstream f(path.string());
    json result;
    result["memo"] = normalized_memo(json::parse(f));
    return types::ToolResult{true, result.dump(), ""};
  } catch (const std::exception& e) {
    return types::ToolResult{false, "", std::string("failed to read memo: ") + e.what()};
  }
}

types::ToolResult memo_delete(const std::string& args_json) {
  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  const std::string id = optional_string(params, "id");
  if (!valid_memo_id(id)) return types::ToolResult{false, "", "invalid memo id"};

  std::lock_guard<std::mutex> lock(memo_mutex_);
  std::error_code ec;
  const bool removed = fs::remove(fs::path(get_memo_dir()) / (id + ".json"), ec);
  if (ec) return types::ToolResult{false, "", "failed to delete memo"};
  if (!removed) return types::ToolResult{false, "", "memo not found"};
  json result = {{"deleted", true}, {"id", id}};
  return types::ToolResult{true, result.dump(), ""};
}

}  // namespace tools
}  // namespace hiclaw
