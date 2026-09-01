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
#include <optional>
#include <vector>

namespace hiclaw {
namespace tools {

namespace {

using json = nlohmann::json;
namespace fs = std::filesystem;

constexpr char kMetadataFile[] = "memo.json";
constexpr char kCoverFile[] = "cover.jpg";

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

std::optional<std::vector<uint8_t>> base64_decode(const std::string& encoded) {
  static const std::string alphabet =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string input = encoded;
  const size_t data_url_start = input.find("base64,");
  if (data_url_start != std::string::npos) input = input.substr(data_url_start + 7);
  input.erase(std::remove_if(input.begin(), input.end(), [](unsigned char c) {
    return std::isspace(c);
  }), input.end());
  if (input.empty() || input.size() % 4 != 0) return std::nullopt;

  std::vector<uint8_t> decoded;
  decoded.reserve(input.size() / 4 * 3);
  for (size_t i = 0; i < input.size(); i += 4) {
    uint32_t value = 0;
    int padding = 0;
    for (size_t offset = 0; offset < 4; ++offset) {
      const char c = input[i + offset];
      if (c == '=') {
        if (offset < 2 || (offset == 2 && input[i + 3] != '=')) return std::nullopt;
        ++padding;
        continue;
      }
      const size_t index = alphabet.find(c);
      if (index == std::string::npos || padding != 0) return std::nullopt;
      value |= static_cast<uint32_t>(index) << (18 - 6 * offset);
    }
    decoded.push_back(static_cast<uint8_t>((value >> 16) & 0xff));
    if (padding < 2) decoded.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
    if (padding == 0) decoded.push_back(static_cast<uint8_t>(value & 0xff));
    if (padding > 0 && i + 4 != input.size()) return std::nullopt;
  }
  return decoded;
}

std::string base64_encode(const std::vector<uint8_t>& data) {
  static const char alphabet[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string encoded;
  encoded.reserve((data.size() + 2) / 3 * 4);
  for (size_t i = 0; i < data.size(); i += 3) {
    const uint32_t value = static_cast<uint32_t>(data[i]) << 16 |
        (i + 1 < data.size() ? static_cast<uint32_t>(data[i + 1]) << 8 : 0) |
        (i + 2 < data.size() ? static_cast<uint32_t>(data[i + 2]) : 0);
    encoded.push_back(alphabet[(value >> 18) & 0x3f]);
    encoded.push_back(alphabet[(value >> 12) & 0x3f]);
    encoded.push_back(i + 1 < data.size() ? alphabet[(value >> 6) & 0x3f] : '=');
    encoded.push_back(i + 2 < data.size() ? alphabet[value & 0x3f] : '=');
  }
  return encoded;
}

bool is_jpeg(const std::vector<uint8_t>& bytes) {
  return bytes.size() >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8 &&
      bytes[bytes.size() - 2] == 0xff && bytes[bytes.size() - 1] == 0xd9;
}

bool write_bytes(const fs::path& path, const std::vector<uint8_t>& bytes) {
  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  if (!file) return false;
  file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  return file.good();
}

bool write_json(const fs::path& path, const json& value) {
  std::ofstream file(path, std::ios::trunc);
  if (!file) return false;
  file << value.dump(2);
  return file.good();
}

std::optional<std::vector<uint8_t>> read_bytes(const fs::path& path) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file) return std::nullopt;
  const std::streamsize size = file.tellg();
  if (size <= 0) return std::nullopt;
  file.seekg(0);
  std::vector<uint8_t> bytes(static_cast<size_t>(size));
  if (!file.read(reinterpret_cast<char*>(bytes.data()), size)) return std::nullopt;
  return bytes;
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
  if (!memo.contains("coverFile")) memo["coverFile"] = "";
  return memo;
}

fs::path memo_path(const std::string& id) {
  return fs::path(get_memo_dir()) / id;
}

json memo_for_response(json memo, const fs::path& directory) {
  memo = normalized_memo(std::move(memo));
  memo["coverImage"] = "";
  const std::string cover_file = optional_string(memo, "coverFile");
  if (cover_file == kCoverFile) {
    const std::optional<std::vector<uint8_t>> bytes = read_bytes(directory / cover_file);
    if (bytes && is_jpeg(*bytes)) memo["coverImage"] = base64_encode(*bytes);
  }
  return memo;
}

bool migrate_legacy_memo(const fs::path& legacy_path) {
  const std::string id = legacy_path.stem().string();
  if (!valid_memo_id(id)) return false;
  const fs::path target = memo_path(id);
  if (fs::exists(target)) return false;

  json memo;
  try {
    std::ifstream file(legacy_path);
    memo = normalized_memo(json::parse(file));
  } catch (...) {
    log::warn("memo_tool: skipped unreadable legacy memo " + legacy_path.string());
    return false;
  }
  memo["id"] = id;

  std::optional<std::vector<uint8_t>> cover;
  const std::string legacy_cover = optional_string(memo, "coverImage");
  if (!legacy_cover.empty()) {
    cover = base64_decode(legacy_cover);
    if (!cover || !is_jpeg(*cover)) {
      log::warn("memo_tool: skipped invalid cover while migrating memo " + id);
      return false;
    }
  }
  memo.erase("coverImage");
  memo["schemaVersion"] = 2;
  memo["coverFile"] = cover ? kCoverFile : "";

  const fs::path temporary = fs::path(get_memo_dir()) / ("." + id + ".migrating");
  std::error_code ec;
  fs::remove_all(temporary, ec);
  fs::create_directories(temporary, ec);
  if (ec || !write_json(temporary / kMetadataFile, memo) ||
      (cover && !write_bytes(temporary / kCoverFile, *cover))) {
    fs::remove_all(temporary, ec);
    log::warn("memo_tool: failed to migrate legacy memo " + id);
    return false;
  }
  fs::rename(temporary, target, ec);
  if (ec) {
    fs::remove_all(temporary, ec);
    log::warn("memo_tool: failed to finalize migration for memo " + id);
    return false;
  }
  fs::remove(legacy_path, ec);
  if (ec) log::warn("memo_tool: migrated memo but could not remove legacy file " + id);
  return true;
}

void migrate_legacy_memos() {
  const fs::path root = get_memo_dir();
  std::error_code ec;
  int migrated = 0;
  for (const auto& entry : fs::directory_iterator(root, ec)) {
    if (ec) break;
    if (entry.is_regular_file() && entry.path().extension() == ".json" &&
        migrate_legacy_memo(entry.path())) {
      ++migrated;
    }
  }
  if (migrated > 0) log::info("memo_tool: migrated " + std::to_string(migrated) + " legacy memo(s)");
}

std::optional<json> read_memo(const std::string& id) {
  const fs::path directory = memo_path(id);
  const fs::path metadata_path = directory / kMetadataFile;
  if (!fs::is_directory(directory) || !fs::is_regular_file(metadata_path)) return std::nullopt;
  try {
    std::ifstream file(metadata_path);
    return memo_for_response(json::parse(file), directory);
  } catch (...) {
    return std::nullopt;
  }
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
  migrate_legacy_memos();
  std::string title = optional_string(params, "title");
  std::string content = optional_string(params, "content");
  std::string source = optional_string(params, "source");
  if (title.empty()) title = "Untitled";
  if (source.empty()) source = "screen";
  if (content.empty()) return types::ToolResult{false, "", "content is required"};

  std::optional<std::vector<uint8_t>> cover;
  const std::string cover_image = optional_string(params, "coverImage");
  if (!cover_image.empty()) {
    cover = base64_decode(cover_image);
    if (!cover || !is_jpeg(*cover)) {
      return types::ToolResult{false, "", "coverImage must be a base64 JPEG"};
    }
  }

  const std::string id = timestamp_id();
  json memo;
  memo["schemaVersion"] = 2;
  memo["id"] = id;
  memo["title"] = title;
  memo["content"] = content;
  memo["source"] = source;
  memo["timestamp"] = id;
  memo["createdAt"] = std::stoll(id);
  memo["sourceApp"] = optional_string(params, "sourceApp");
  memo["pageTitle"] = optional_string(params, "pageTitle");
  memo["pageLink"] = optional_string(params, "pageLink");
  memo["coverFile"] = cover ? kCoverFile : "";
  memo["tags"] = json::array();
  if (params.contains("tags") && params["tags"].is_array()) {
    for (const auto& tag : params["tags"]) {
      if (tag.is_string() && !tag.get<std::string>().empty()) memo["tags"].push_back(tag);
    }
  }

  const fs::path directory = memo_path(id);
  std::error_code ec;
  fs::create_directories(directory, ec);
  if (ec) return types::ToolResult{false, "", "failed to create memo directory"};
  if (!write_json(directory / kMetadataFile, memo) ||
      (cover && !write_bytes(directory / kCoverFile, *cover))) {
    fs::remove_all(directory, ec);
    return types::ToolResult{false, "", "failed to save memo"};
  }

  log::info("memo_tool: saved memo " + id + ": " + title);
  json result = {{"saved", true}, {"id", id}, {"title", title}};
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
  migrate_legacy_memos();
  int limit = 20;
  if (params.contains("limit") && params["limit"].is_number_integer()) limit = params["limit"].get<int>();
  if (limit <= 0 || limit > 200) limit = 20;

  std::vector<json> stored_memos;
  std::error_code ec;
  for (const auto& entry : fs::directory_iterator(get_memo_dir(), ec)) {
    if (ec) break;
    if (!entry.is_directory() || !valid_memo_id(entry.path().filename().string())) continue;
    std::optional<json> memo = read_memo(entry.path().filename().string());
    if (memo) stored_memos.push_back(std::move(*memo));
  }
  std::sort(stored_memos.begin(), stored_memos.end(), [](const json& a, const json& b) {
    return a.value("createdAt", 0LL) > b.value("createdAt", 0LL);
  });

  json memos = json::array();
  for (size_t i = 0; i < stored_memos.size() && i < static_cast<size_t>(limit); ++i) {
    memos.push_back(std::move(stored_memos[i]));
  }
  json result = {{"memos", memos}, {"count", memos.size()}};
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
  migrate_legacy_memos();
  std::optional<json> memo = read_memo(id);
  if (!memo) return types::ToolResult{false, "", "memo not found"};
  json result = {{"memo", *memo}};
  return types::ToolResult{true, result.dump(), ""};
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
  migrate_legacy_memos();
  const fs::path directory = memo_path(id);
  if (!fs::is_directory(directory)) return types::ToolResult{false, "", "memo not found"};
  std::error_code ec;
  fs::remove_all(directory, ec);
  if (ec) return types::ToolResult{false, "", "failed to delete memo"};
  json result = {{"deleted", true}, {"id", id}};
  return types::ToolResult{true, result.dump(), ""};
}

}  // namespace tools
}  // namespace hiclaw
