#ifndef HICLAW_NET_WECOM_WS_CLIENT_HPP
#define HICLAW_NET_WECOM_WS_CLIENT_HPP

#include <functional>
#include <string>
#include <atomic>
#include <mutex>

namespace hiclaw {
namespace net {

/// Callback for inbound WeCom messages.
/// Arguments: (msg_id, user_id, chat_id, chat_type, content, callback_req_id)
using WecomMessageCallback = std::function<void(
    const std::string&, const std::string&, const std::string&,
    const std::string&, const std::string&, const std::string&)>;

/// WeCom intelligent-bot WebSocket long-connection client.
/// Connects to wss://openws.work.weixin.qq.com using the aibot protocol.
class WecomWsClient {
public:
  WecomWsClient(const std::string& bot_id, const std::string& bot_secret);
  ~WecomWsClient();

  /// Connect and run the message loop. Blocks until stop() is called.
  void run(WecomMessageCallback on_message);

  /// Signal to stop the connection loop.
  void stop();

  /// Reply to a callback message using aibot_respond_msg (stream format).
  bool reply(const std::string& callback_req_id, const std::string& content);

private:
  std::string next_req_id(const std::string& prefix);
  bool send_frame(const std::string& json_frame);
  bool subscribe();

  std::string bot_id_;
  std::string bot_secret_;
  std::atomic<bool> running_{false};
  std::atomic<int64_t> req_seq_{0};
  std::mutex write_mutex_;

  // Opaque pointer to hv::WebSocketClient (avoid including libhv headers here)
  void* ws_client_ = nullptr;
  WecomMessageCallback on_message_;
};

}  // namespace net
}  // namespace hiclaw

#endif  // HICLAW_NET_WECOM_WS_CLIENT_HPP
