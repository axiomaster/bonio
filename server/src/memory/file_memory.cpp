#include "hiclaw/memory/memory.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <chrono>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace hiclaw {
namespace memory {

namespace {

using json = nlohmann::json;

std::string& base_path_storage() {
  static std::string path = ".bonio";
  return path;
}

std::string sanitize_key(const std::string& key) {
  std::string out;
  for (char c : key) {
    if (c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' ||
        c == '<' || c == '>' || c == '|')
      out += '_';
    else
      out += c;
  }
  return out.empty() ? "_" : out;
}

std::string memory_dir() {
  std::string base = base_path_storage();
  if (base.empty()) base = ".bonio";
  return (std::filesystem::path(base) / "memory").string();
}

std::string entry_path(const std::string& safe_key) {
  return (std::filesystem::path(memory_dir()) / (safe_key + ".json")).string();
}

std::string now_iso() {
  auto t = std::chrono::system_clock::now();
  auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(t.time_since_epoch()).count();
  time_t sec = static_cast<time_t>(ms / 1000);
  struct tm* tm = nullptr;
#ifdef _WIN32
  struct tm tmbuf;
  if (localtime_s(&tmbuf, &sec) == 0) tm = &tmbuf;
#else
  struct tm tmbuf;
  tm = localtime_r(&sec, &tmbuf);
#endif
  if (!tm) return "1970-01-01T00:00:00Z";
  char buf[32];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02d",
           tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday,
           tm->tm_hour, tm->tm_min, tm->tm_sec);
  return std::string(buf);
}

}  // namespace

void set_base_path(const std::string& path) {
  base_path_storage() = path.empty() ? ".bonio" : path;
}

std::string get_base_path() {
  return base_path_storage();
}

bool store(const std::string& key, const std::string& content, const std::string& category) {
  std::string safe = sanitize_key(key);
  std::string dir = memory_dir();
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  if (ec) return false;
  std::string path = entry_path(safe);
  json j;
  j["key"] = key;
  j["content"] = content;
  j["category"] = category.empty() ? "core" : category;
  j["timestamp"] = now_iso();
  std::ofstream f(path);
  if (!f) return false;
  f << j.dump();
  return true;
}

std::vector<MemoryEntry> recall(const std::string& query, size_t limit) {
  std::vector<MemoryEntry> entries;
  std::string dir = memory_dir();
  std::error_code ec;
  if (!std::filesystem::is_directory(dir, ec)) return entries;

  std::string q = query;
  std::transform(q.begin(), q.end(), q.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

  std::vector<std::pair<std::string, MemoryEntry>> with_ts;
  for (const auto& e : std::filesystem::directory_iterator(dir, ec)) {
    if (ec || !e.is_regular_file()) continue;
    std::string p = e.path().string();
    if (p.size() < 6 || p.compare(p.size() - 5, 5, ".json") != 0) continue;
    std::ifstream f(p);
    if (!f) continue;
    try {
      json j = json::parse(f);
      MemoryEntry ent;
      if (!j.contains("key") || !j["key"].is_string()) continue;
      ent.key = j["key"].get<std::string>();
      if (j.contains("content") && j["content"].is_string()) ent.content = j["content"].get<std::string>();
      if (j.contains("category") && j["category"].is_string()) ent.category = j["category"].get<std::string>();
      if (j.contains("timestamp") && j["timestamp"].is_string()) ent.timestamp = j["timestamp"].get<std::string>();
      ent.id = ent.key;

    std::string content_lower = ent.content;
    std::string key_lower = ent.key;
    std::transform(content_lower.begin(), content_lower.end(), content_lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    std::transform(key_lower.begin(), key_lower.end(), key_lower.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (!q.empty() && key_lower.find(q) == std::string::npos && content_lower.find(q) == std::string::npos)
      continue;
    with_ts.push_back({ent.timestamp, ent});
    } catch (const json::parse_error&) {}
  }
  std::sort(with_ts.begin(), with_ts.end(), [](const auto& a, const auto& b) { return a.first > b.first; });
  for (size_t i = 0; i < with_ts.size() && i < limit; ++i)
    entries.push_back(std::move(with_ts[i].second));
  return entries;
}

bool forget(const std::string& key) {
  std::string safe = sanitize_key(key);
  std::string path = entry_path(safe);
  std::error_code ec;
  if (!std::filesystem::exists(path, ec)) return false;
  return std::filesystem::remove(path, ec);
}

}  // namespace memory
}  // namespace hiclaw
