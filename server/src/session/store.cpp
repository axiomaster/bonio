#include "hiclaw/session/store.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#include <fstream>
#include <filesystem>
#include <unordered_set>

namespace hiclaw {
namespace session {

namespace fs = std::filesystem;
using json = nlohmann::json;

static std::string sanitize_utf8(const std::string& input) {
  std::string out;
  out.reserve(input.size());
  size_t i = 0;
  while (i < input.size()) {
    unsigned char c = static_cast<unsigned char>(input[i]);
    int expected = 0;
    if (c <= 0x7F) { expected = 1; }
    else if ((c & 0xE0) == 0xC0) { expected = 2; }
    else if ((c & 0xF0) == 0xE0) { expected = 3; }
    else if ((c & 0xF8) == 0xF0) { expected = 4; }
    else { out += "\xEF\xBF\xBD"; ++i; continue; }

    if (i + expected > input.size()) {
      out += "\xEF\xBF\xBD"; ++i; continue;
    }
    bool valid = true;
    for (int j = 1; j < expected; ++j) {
      if ((static_cast<unsigned char>(input[i + j]) & 0xC0) != 0x80) {
        valid = false; break;
      }
    }
    if (valid) {
      out.append(input, i, expected);
      i += expected;
    } else {
      out += "\xEF\xBF\xBD"; ++i;
    }
  }
  return out;
}

static int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

SessionStore::SessionStore(const std::string& config_dir)
    : config_dir_(config_dir),
      sessions_dir_((fs::path(config_dir) / "sessions").string()) {
  ensure_session_dir();
  load();
}

void SessionStore::ensure_session_dir() {
  try {
    if (!fs::exists(sessions_dir_)) {
      fs::create_directories(sessions_dir_);
    }
  } catch (const std::exception& e) {
    log::error("SessionStore: failed to create sessions dir: " + std::string(e.what()));
  }
}

std::string SessionStore::session_file_path(const std::string& key) const {
  return (fs::path(sessions_dir_) / (key + ".json")).string();
}

void SessionStore::load() {
  // Load existing sessions from disk
  try {
    if (!fs::exists(sessions_dir_)) return;

    for (const auto& entry : fs::directory_iterator(sessions_dir_)) {
      if (!entry.is_regular_file()) continue;
      std::string path = entry.path().string();
      if (path.size() < 5 || path.substr(path.size() - 5) != ".json") continue;

      try {
        std::ifstream f(path);
        if (!f.is_open()) continue;

        json j;
        f >> j;

        Session s;
        s.key = j.value("key", "");
        s.display_name = j.value("displayName", s.key);
        s.created_at = j.value("createdAt", int64_t(0));
        s.updated_at = j.value("updatedAt", int64_t(0));

        if (j.contains("messages") && j["messages"].is_array()) {
          for (const auto& mj : j["messages"]) {
            Message m;
            m.role = mj.value("role", "");
            m.content = mj.value("content", "");
            m.timestamp = mj.value("timestamp", int64_t(0));
            m.run_id = mj.value("runId", "");
            m.tool_call_id = mj.value("toolCallId", "");
            m.tool_name = mj.value("toolName", "");
            s.messages.push_back(std::move(m));
          }
        }

        if (!s.key.empty()) {
          sessions_.push_back(std::move(s));
        }
      } catch (const std::exception& e) {
        log::warn("SessionStore: failed to load session from " + path + ": " + e.what());
      }
    }
  } catch (const std::exception& e) {
    log::error("SessionStore: failed to load sessions: " + std::string(e.what()));
  }
}

void SessionStore::scan_new_sessions() {
  // Must be called with mutex_ held.
  try {
    if (!fs::exists(sessions_dir_)) return;

    // Build set of known keys
    std::unordered_set<std::string> known;
    for (const auto& s : sessions_) {
      known.insert(s.key);
    }

    for (const auto& entry : fs::directory_iterator(sessions_dir_)) {
      if (!entry.is_regular_file()) continue;
      std::string path = entry.path().string();
      if (path.size() < 5 || path.substr(path.size() - 5) != ".json") continue;

      // Derive key from filename: sessions_dir/key.json
      std::string filename = entry.path().filename().string();
      std::string key = filename.substr(0, filename.size() - 5);
      if (known.count(key)) continue;

      try {
        std::ifstream f(path);
        if (!f.is_open()) continue;
        json j;
        f >> j;

        Session s;
        s.key = j.value("key", key);
        s.display_name = j.value("displayName", s.key);
        s.created_at = j.value("createdAt", int64_t(0));
        s.updated_at = j.value("updatedAt", int64_t(0));

        if (j.contains("messages") && j["messages"].is_array()) {
          for (const auto& mj : j["messages"]) {
            Message m;
            m.role = mj.value("role", "");
            m.content = mj.value("content", "");
            m.timestamp = mj.value("timestamp", int64_t(0));
            m.run_id = mj.value("runId", "");
            m.tool_call_id = mj.value("toolCallId", "");
            m.tool_name = mj.value("toolName", "");
            s.messages.push_back(std::move(m));
          }
        }

        if (!s.key.empty()) {
          sessions_.push_back(std::move(s));
        }
      } catch (const std::exception& e) {
        log::warn("SessionStore: failed to scan session from " + path + std::string(": ") + e.what());
      }
    }
  } catch (const std::exception& e) {
    log::error(std::string("SessionStore: failed to scan new sessions: ") + e.what());
  }
}

Session SessionStore::get_or_create(const std::string& key) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& s : sessions_) {
    if (s.key == key) {
      return s;
    }
  }

  Session s;
  s.key = key;
  s.display_name = key == "main" ? "Main" : key;
  s.created_at = now_ms();
  s.updated_at = s.created_at;
  sessions_.push_back(s);

  save();

  return s;
}

void SessionStore::add_message(const std::string& key, const Message& msg) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& s : sessions_) {
    if (s.key == key) {
      s.messages.push_back(msg);
      s.updated_at = now_ms();
      save();
      return;
    }
  }

  // Session doesn't exist, create it inline (can't call get_or_create — already locked)
  Session s;
  s.key = key;
  s.display_name = key == "main" ? "Main" : key;
  s.created_at = now_ms();
  s.updated_at = s.created_at;
  s.messages.push_back(msg);
  sessions_.push_back(s);

  save();
}

std::vector<Session> SessionStore::list_sessions() {
  std::lock_guard<std::mutex> lock(mutex_);
  scan_new_sessions();
  std::vector<Session> result;
  for (const auto& s : sessions_) {
    Session meta;
    meta.key = s.key;
    meta.display_name = s.display_name;
    meta.created_at = s.created_at;
    meta.updated_at = s.updated_at;
    result.push_back(std::move(meta));
  }
  return result;
}

bool SessionStore::delete_session(const std::string& key) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto it = sessions_.begin(); it != sessions_.end(); ++it) {
    if (it->key == key) {
      sessions_.erase(it);
      try {
        fs::remove(session_file_path(key));
      } catch (...) {}
      return true;
    }
  }
  return false;
}

bool SessionStore::reset_session(const std::string& key) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& s : sessions_) {
    if (s.key == key) {
      s.messages.clear();
      s.updated_at = now_ms();
      save();
      return true;
    }
  }
  return false;
}

bool SessionStore::patch_session(const std::string& key, const std::string& display_name) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& s : sessions_) {
    if (s.key == key) {
      if (!display_name.empty()) {
        s.display_name = display_name;
      }
      s.updated_at = now_ms();
      save();
      return true;
    }
  }
  return false;
}

void SessionStore::save() {
  ensure_session_dir();

  for (const auto& s : sessions_) {
    json j;
    j["key"] = s.key;
    j["displayName"] = s.display_name;
    j["createdAt"] = s.created_at;
    j["updatedAt"] = s.updated_at;

    json msgs = json::array();
    for (const auto& m : s.messages) {
      json mj;
      mj["role"] = m.role;
      mj["content"] = sanitize_utf8(m.content);
      mj["timestamp"] = m.timestamp;
      if (!m.run_id.empty()) mj["runId"] = m.run_id;
      if (!m.tool_call_id.empty()) mj["toolCallId"] = m.tool_call_id;
      if (!m.tool_name.empty()) mj["toolName"] = m.tool_name;
      msgs.push_back(std::move(mj));
    }
    j["messages"] = msgs;

    std::string path = session_file_path(s.key);
    try {
      std::ofstream f(path);
      if (f.is_open()) {
        f << j.dump(2);
      }
    } catch (const std::exception& e) {
      log::error("SessionStore: failed to save session " + s.key + ": " + e.what());
    }
  }
}

std::vector<Message> SessionStore::get_messages(const std::string& key, int limit) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (const auto& s : sessions_) {
    if (s.key == key) {
      if (limit <= 0 || static_cast<int>(s.messages.size()) <= limit) {
        return s.messages;
      }
      return std::vector<Message>(s.messages.end() - limit, s.messages.end());
    }
  }
  return {};
}

}  // namespace session
}  // namespace hiclaw
