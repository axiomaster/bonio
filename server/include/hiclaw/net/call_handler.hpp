#ifndef HICLAW_NET_CALL_HANDLER_HPP
#define HICLAW_NET_CALL_HANDLER_HPP

#include "hiclaw/net/async_agent.hpp"
#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

namespace hiclaw {
namespace net {

/**
 * CallHandler manages the server-side logic for incoming phone calls:
 * - Countdown timer management
 * - TTS/STT coordination
 * - Answer/reject decision via call.action events to the client
 */
class CallHandler {
public:
  explicit CallHandler(EventCallback event_cb);
  ~CallHandler();

  CallHandler(const CallHandler&) = delete;
  CallHandler& operator=(const CallHandler&) = delete;

  void on_incoming_call(const std::string& payload_json);
  void on_user_response(const std::string& payload_json);
  void on_call_ended(const std::string& payload_json);
  void on_call_answered(const std::string& payload_json);
  void on_tts_done(const std::string& payload_json);
  bool is_handling() const;

private:
  void run_call_flow(const std::string& number, const std::string& contact_name);
  void send_event(const std::string& event_name, const std::string& payload_json);
  void send_tts(const std::string& text);
  void send_stt_start();
  void send_stt_stop();
  void send_countdown(int remaining);
  void execute_answer();
  void execute_reject();
  bool lookup_spam(const std::string& number);
  bool detect_spam_from_contact(const std::string& contact_name);

  EventCallback event_callback_;

  mutable std::mutex mutex_;
  std::atomic<bool> handling_{false};
  std::atomic<bool> user_responded_{false};
  std::atomic<bool> tts_done_{false};
  std::string user_action_;
  std::string current_number_;
  bool current_is_spam_ = false;
  std::thread call_thread_;
};

}  // namespace net
}  // namespace hiclaw

#endif
