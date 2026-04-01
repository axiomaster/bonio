#ifndef HICLAW_NET_INTENT_ROUTER_HPP
#define HICLAW_NET_INTENT_ROUTER_HPP

#include "hiclaw/net/async_agent.hpp"
#include <string>

namespace hiclaw {
namespace net {

/**
 * Server-side classification of user voice input.
 * Replaces client-side isScreenCaptureCommand / isSummarizeCommand / classifyVoiceCommand.
 */
class IntentRouter {
public:
  enum class Intent {
    Chat,
    ScreenCapture,
    Summarize,
    CallAnswer,
    CallReject,
    Unknown,
  };

  explicit IntentRouter(EventCallback event_cb,
                        std::shared_ptr<AsyncAgentManager> agent_mgr = nullptr);

  /**
   * Handle a raw STT final result. Classifies intent and dispatches:
   * - ScreenCapture / Summarize -> sends avatar.command + triggers agent task
   * - CallAnswer / CallReject -> returns the action for CallHandler
   * - Chat -> sends as a chat message via agent
   */
  void on_stt_result(const std::string& payload_json);

  /**
   * Classify text intent for use by CallHandler during active calls.
   * Returns "answer", "reject", or empty string.
   */
  std::string classify_call_command(const std::string& text, const std::string& last_tts);

private:
  static Intent classify_intent(const std::string& text);
  static bool contains_any(const std::string& text, const std::vector<std::string>& keywords);

  EventCallback event_callback_;
  std::shared_ptr<AsyncAgentManager> agent_mgr_;
};

}  // namespace net
}  // namespace hiclaw

#endif
