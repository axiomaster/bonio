#ifndef HICLAW_NET_ILINK_HTTP_CLIENT_HPP
#define HICLAW_NET_ILINK_HTTP_CLIENT_HPP

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace hiclaw {
namespace net {

/// HTTP client for WeChat ilink bot API (personal WeChat).
class IlinkHttpClient {
public:
  struct Message {
    int64_t message_id = 0;
    int64_t seq = 0;
    std::string from_user_id;
    std::string to_user_id;
    std::string content;
    std::string context_token;
    int message_type = 0;   // 1=user, 2=bot
    int message_state = 0;
  };

  explicit IlinkHttpClient(const std::string& token,
                            const std::string& base_url,
                            const std::string& state_dir);
  ~IlinkHttpClient();

  IlinkHttpClient(const IlinkHttpClient&) = delete;
  IlinkHttpClient& operator=(const IlinkHttpClient&) = delete;

  /// Long-poll for new messages (blocking). Returns false on error.
  bool get_updates(std::vector<Message>& msgs);

  /// Send text message (auto-chunk to 3800 chars, retry on ret=-2).
  bool send_message(const std::string& to_user_id,
                    const std::string& content);

  /// Signal the polling loop to stop.
  void stop();

private:
  bool do_post(const std::string& path, const std::string& body,
               int& ret_code, int& err_code, std::string& resp_body);
  bool do_get(const std::string& url, std::string& resp_body);

  std::string extract_text(const void* item_list_json);
  std::string generate_client_id();

  bool load_cursor(std::string& cursor);
  bool save_cursor(const std::string& cursor);
  bool load_context_token(const std::string& user_id, std::string& token);
  bool save_context_token(const std::string& user_id, const std::string& token);
  bool load_all_context_tokens();
  bool save_all_context_tokens();

  std::string token_;
  std::string base_url_;
  std::string state_dir_;
  std::string client_id_;
  std::string x_wechat_uin_;
  std::atomic<bool> running_{true};

  std::mutex ctx_mutex_;
  std::unordered_map<std::string, std::string> context_tokens_;
};

}  // namespace net
}  // namespace hiclaw

#endif  // HICLAW_NET_ILINK_HTTP_CLIENT_HPP
