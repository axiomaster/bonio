#ifndef HICLAW_SESSION_STORE_HPP
#define HICLAW_SESSION_STORE_HPP

#include <string>
#include <vector>
#include <cstdint>
#include <mutex>

namespace hiclaw {
namespace session {

/**
 * A single message in a conversation session.
 */
struct Message {
  std::string role;       // "user" | "assistant" | "system" | "tool"
  std::string content;    // Text content
  int64_t timestamp = 0;  // Unix timestamp (milliseconds)
  std::string run_id;     // Associated run ID (for tracking)
  std::string tool_call_id;  // For tool messages
  std::string tool_name;     // For tool messages
};

/**
 * A conversation session.
 */
struct Session {
  std::string key;              // Session key (e.g., "main")
  std::string display_name;     // Human-readable name
  int64_t created_at = 0;       // Unix timestamp (milliseconds)
  int64_t updated_at = 0;       // Unix timestamp (milliseconds)
  std::vector<Message> messages;
};

/**
 * SessionStore manages conversation sessions with persistence.
 */
class SessionStore {
public:
  explicit SessionStore(const std::string& config_dir);
  ~SessionStore() = default;

  // Disable copy
  SessionStore(const SessionStore&) = delete;
  SessionStore& operator=(const SessionStore&) = delete;

  /**
   * Get or create a session by key.
   */
  Session get_or_create(const std::string& key);

  /**
   * Add a message to a session.
   */
  void add_message(const std::string& key, const Message& msg);

  /**
   * List all sessions (metadata only, no messages).
   */
  std::vector<Session> list_sessions();

  /**
   * Delete a session.
   */
  bool delete_session(const std::string& key);

  /**
   * Clear all messages in a session but keep the session itself.
   */
  bool reset_session(const std::string& key);

  /**
   * Update session metadata (display name).
   */
  bool patch_session(const std::string& key, const std::string& display_name);

  /**
   * Save all sessions to disk.
   */
  void save();

  /**
   * Get messages for a session (with optional limit).
   */
  std::vector<Message> get_messages(const std::string& key, int limit = 0);

private:
  void load();
  void ensure_session_dir();
  std::string session_file_path(const std::string& key) const;

  mutable std::mutex mutex_;
  std::string config_dir_;
  std::string sessions_dir_;
  std::vector<Session> sessions_;
};

}  // namespace session
}  // namespace hiclaw

#endif
