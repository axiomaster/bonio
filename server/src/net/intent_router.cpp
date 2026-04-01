#include "hiclaw/net/intent_router.hpp"
#include "hiclaw/net/avatar_command.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <vector>

namespace hiclaw {
namespace net {

using json = nlohmann::json;

IntentRouter::IntentRouter(EventCallback event_cb, std::shared_ptr<AsyncAgentManager> agent_mgr)
    : event_callback_(std::move(event_cb)), agent_mgr_(std::move(agent_mgr)) {}

bool IntentRouter::contains_any(const std::string& text, const std::vector<std::string>& keywords) {
  for (const auto& kw : keywords) {
    if (text.find(kw) != std::string::npos) return true;
  }
  return false;
}

static std::vector<std::string> make_capture_keywords() {
  std::vector<std::string> v;
  v.push_back("save this");
  v.push_back("remember this");
  v.push_back("note this");
  v.push_back("screenshot");
  v.push_back("take a picture");
  v.push_back("capture this");
  v.push_back("save what");
  v.push_back("\xe8\xae\xb0\xe4\xb8\x80\xe4\xb8\x8b");
  v.push_back("\xe5\xb8\xae\xe6\x88\x91\xe5\xad\x98");
  v.push_back("\xe4\xbf\x9d\xe5\xad\x98\xe4\xb8\x80\xe4\xb8\x8b");
  v.push_back("\xe5\xb8\xae\xe6\x88\x91\xe8\xae\xb0");
  v.push_back("\xe6\x88\xaa\xe5\x9b\xbe");
  v.push_back("\xe6\x88\xaa\xe4\xb8\xaa\xe5\x9b\xbe");
  v.push_back("\xe6\x8b\x8d\xe4\xb8\x8b\xe6\x9d\xa5");
  return v;
}

static std::vector<std::string> make_summarize_keywords() {
  std::vector<std::string> v;
  v.push_back("summarize");
  v.push_back("summary");
  v.push_back("read this");
  v.push_back("too long");
  v.push_back("what does this say");
  v.push_back("tldr");
  v.push_back("read it");
  v.push_back("\xe5\xa4\xaa\xe9\x95\xbf\xe4\xba\x86");
  v.push_back("\xe5\xb8\xae\xe6\x88\x91\xe6\x80\xbb\xe7\xbb\x93");
  v.push_back("\xe6\x80\xbb\xe7\xbb\x93\xe4\xb8\x80\xe4\xb8\x8b");
  v.push_back("\xe5\xb8\xae\xe6\x88\x91\xe7\x9c\x8b\xe7\x9c\x8b");
  v.push_back("\xe5\xb8\xae\xe6\x88\x91\xe8\xaf\xbb");
  v.push_back("\xe8\xaf\xbb\xe4\xb8\x80\xe4\xb8\x8b");
  v.push_back("\xe7\x9c\x8b\xe4\xb8\x80\xe4\xb8\x8b");
  v.push_back("\xe8\xaf\xbb\xe7\xbb\x99\xe6\x88\x91\xe5\x90\xac");
  return v;
}

IntentRouter::Intent IntentRouter::classify_intent(const std::string& text) {
  static const auto capture_kw = make_capture_keywords();
  static const auto summarize_kw = make_summarize_keywords();

  std::string lower = text;
  std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

  if (contains_any(lower, summarize_kw)) return Intent::Summarize;
  if (contains_any(lower, capture_kw)) return Intent::ScreenCapture;
  return Intent::Chat;
}

void IntentRouter::on_stt_result(const std::string& payload_json) {
  try {
    json payload = json::parse(payload_json);
    std::string text = payload.value("text", "");
    std::string context = payload.value("context", "");

    if (text.empty()) return;

    log::info("intent_router: classifying STT result: " + text.substr(0, 50));

    auto intent = classify_intent(text);

    switch (intent) {
      case Intent::ScreenCapture: {
        log::info("intent_router: screen_capture intent detected");
        std::vector<json> steps;
        steps.push_back(avatar_cmd::step("setState", {{"state", "thinking"}}, 0));
        steps.push_back(avatar_cmd::step("setBubble", {{"text", "Taking screenshot..."}}, 0));
        avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

        json capture_cmd;
        capture_cmd["action"] = "screen_capture";
        capture_cmd["userText"] = text;
        event_callback_("intent.execute", capture_cmd.dump());
        break;
      }
      case Intent::Summarize: {
        log::info("intent_router: summarize intent detected");
        std::vector<json> steps;
        steps.push_back(avatar_cmd::step("setState", {{"state", "speaking"}}, 0));
        steps.push_back(avatar_cmd::step("setBubble", {{"text", "Let me have my clone read it"}}, 0));
        avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

        json summarize_cmd;
        summarize_cmd["action"] = "summarize";
        summarize_cmd["userText"] = text;
        event_callback_("intent.execute", summarize_cmd.dump());
        break;
      }
      case Intent::Chat:
      default: {
        log::info("intent_router: chat intent, forwarding to agent");
        json chat_cmd;
        chat_cmd["action"] = "chat";
        chat_cmd["text"] = text;
        event_callback_("intent.execute", chat_cmd.dump());
        break;
      }
    }
  } catch (const std::exception& e) {
    log::info("intent_router: failed to parse stt.final_result: " + std::string(e.what()));
  }
}

static std::vector<std::string> make_reject_keywords() {
  std::vector<std::string> v;
  v.push_back("\xe6\x8c\x82\xe6\x96\xad");
  v.push_back("\xe6\x8c\x82\xe6\x8e\x89");
  v.push_back("\xe6\x8b\x92\xe6\x8e\xa5");
  v.push_back("\xe4\xb8\x8d\xe6\x8e\xa5");
  v.push_back("\xe6\x8b\x92\xe7\xbb\x9d");
  v.push_back("\xe6\x8c\x82\xe4\xba\x86");
  v.push_back("reject");
  v.push_back("hang up");
  v.push_back("decline");
  return v;
}

static std::vector<std::string> make_answer_keywords() {
  std::vector<std::string> v;
  v.push_back("\xe6\x8e\xa5\xe5\x90\xac");
  v.push_back("\xe6\x8e\xa5\xe7\x94\xb5\xe8\xaf\x9d");
  v.push_back("\xe6\x8e\xa5\xe4\xb8\x80\xe4\xb8\x8b");
  v.push_back("\xe5\xb8\xae\xe6\x88\x91\xe6\x8e\xa5");
  v.push_back("answer");
  v.push_back("pick up");
  v.push_back("accept");
  return v;
}

std::string IntentRouter::classify_call_command(const std::string& text, const std::string& last_tts) {
  std::string lower = text;
  std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

  if (lower.empty()) return "";

  // Echo guard
  if (!last_tts.empty() && last_tts.find(lower) != std::string::npos) {
    log::info("intent_router: echo detected, ignoring: " + text);
    return "";
  }

  static const auto reject_kw = make_reject_keywords();
  static const auto answer_kw = make_answer_keywords();

  if (contains_any(lower, reject_kw)) return "reject";
  if (contains_any(lower, answer_kw)) return "answer";
  return "";
}

}  // namespace net
}  // namespace hiclaw
