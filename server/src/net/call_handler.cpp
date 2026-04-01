#include "hiclaw/net/call_handler.hpp"
#include "hiclaw/net/avatar_command.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#include <thread>
#include <vector>

namespace hiclaw {
namespace net {

namespace {
using json = nlohmann::json;

constexpr int COUNTDOWN_SECONDS = 10;

std::string get_str(const json& j, const char* key) {
  if (j.contains(key) && j[key].is_string()) return j[key].get<std::string>();
  return "";
}
}  // namespace

CallHandler::CallHandler(EventCallback event_cb)
    : event_callback_(std::move(event_cb)) {}

CallHandler::~CallHandler() {
  handling_ = false;
  user_responded_ = true;
  if (call_thread_.joinable()) {
    call_thread_.detach();
  }
}

void CallHandler::on_incoming_call(const std::string& payload_json) {
  if (handling_) {
    log::info("call_handler: already handling a call, ignoring new incoming");
    return;
  }

  std::string number;
  std::string contact_name;
  try {
    json payload = json::parse(payload_json);
    number = get_str(payload, "number");
    contact_name = get_str(payload, "contactName");
  } catch (const std::exception& e) {
    log::info("call_handler: failed to parse incoming_call payload: " + std::string(e.what()));
    return;
  }

  if (number.empty()) {
    log::info("call_handler: incoming call with empty number, ignoring");
    return;
  }

  log::info("call_handler: incoming call from " + number + " (" + contact_name + ")");

  handling_ = true;
  user_responded_ = false;
  tts_done_ = false;
  user_action_ = "";
  current_number_ = number;
  current_is_spam_ = false;

  if (call_thread_.joinable()) {
    call_thread_.detach();
  }
  call_thread_ = std::thread([this, number, contact_name]() {
    run_call_flow(number, contact_name);
  });
}

void CallHandler::on_user_response(const std::string& payload_json) {
  std::lock_guard<std::mutex> lock(mutex_);
  try {
    json payload = json::parse(payload_json);
    user_action_ = get_str(payload, "action");
    user_responded_ = true;
    log::info("call_handler: user response: " + user_action_);
  } catch (...) {
    user_action_ = "reject";
    user_responded_ = true;
  }
}

void CallHandler::on_call_ended(const std::string& payload_json) {
  log::info("call_handler: call ended externally");
  handling_ = false;
  user_responded_ = true;
  user_action_ = "ended";

  // Reset avatar to idle
  std::vector<json> steps;
  steps.push_back(avatar_cmd::step("cancelMovement", json::object(), 0));
  steps.push_back(avatar_cmd::step("setState", {{"state", "idle"}}, 0));
  steps.push_back(avatar_cmd::step("setColorFilter", {{"color", nullptr}}, 0));
  steps.push_back(avatar_cmd::step("clearBubble", json::object(), 0));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));
}

void CallHandler::on_call_answered(const std::string& payload_json) {
  log::info("call_handler: call answered externally");
  handling_ = false;
  user_responded_ = true;
  tts_done_ = true;
  user_action_ = "answered";
}

void CallHandler::on_tts_done(const std::string& payload_json) {
  log::info("call_handler: TTS playback finished on client");
  tts_done_ = true;
}

bool CallHandler::is_handling() const {
  return handling_;
}

void CallHandler::run_call_flow(const std::string& number, const std::string& contact_name) {
  bool is_spam = lookup_spam(number) || detect_spam_from_contact(contact_name);
  current_is_spam_ = is_spam;
  tts_done_ = false;

  log::info("call_handler: starting call flow for " + number + " (spam=" + (is_spam ? "true" : "false") + ")");

  // FUTURE: Replace hardcoded flow with LLM-driven skill.

  // Send avatar choreography via avatar.command sequence
  {
    std::string display = contact_name.empty() ? number : contact_name;
    std::vector<json> steps;

    if (is_spam) {
      steps.push_back(avatar_cmd::step("setColorFilter", {{"color", 0x66FF0000}}, 0));
      steps.push_back(avatar_cmd::step("setBubble", {
        {"text", "spam call from " + display},
        {"bgColor", static_cast<int64_t>(0xFFD32F2F)},
        {"textColor", static_cast<int64_t>(0xFFFFFFFF)}
      }, 0));
    } else {
      steps.push_back(avatar_cmd::step("setColorFilter", json::object(), 0));
      steps.push_back(avatar_cmd::step("setBubble", {
        {"text", display + " is calling"},
        {"bgColor", static_cast<int64_t>(0xFF388E3C)},
        {"textColor", static_cast<int64_t>(0xFFFFFFFF)}
      }, 0));
    }
    steps.push_back(avatar_cmd::step("setState", {{"state", "watching"}}, 0));
    // Portal animation: move to notification banner area
    steps.push_back(avatar_cmd::step("moveTo", {{"x", 450}, {"y", 330}, {"mode", "portal"}}, 2500));
    steps.push_back(avatar_cmd::step("setState", {{"state", "listening"}}, 0));
    avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

    // Also send a chat message via event
    json chat_msg;
    chat_msg["text"] = "\xe6\x9d\xa5\xe7\x94\xb5\xe6\x8f\x90\xe7\xa4\xba\xef\xbc\x9a" + display +
        (is_spam ? " (\xe7\x96\x91\xe4\xbc\xbc\xe9\xaa\x9a\xe6\x89\xb0\xe7\x94\xb5\xe8\xaf\x9d)" : "");
    // "来电提示：{display} (疑似骚扰电话)"
    chat_msg["role"] = "assistant";
    send_event("chat.local_message", chat_msg.dump());
  }

  std::this_thread::sleep_for(std::chrono::milliseconds(800));
  if (!handling_) return;

  // TTS announcement — avoid trigger keywords (接听/挂) to prevent STT echo
  std::string display = contact_name.empty() ? number : contact_name;
  if (is_spam) {
    send_tts("\xe4\xb8\xbb\xe4\xba\xba\xef\xbc\x8c" + display +
             "\xe6\x89\x93\xe6\x9d\xa5\xe7\x94\xb5\xe8\xaf\x9d\xe4\xba\x86\xef\xbc\x8c"
             "\xe7\x9c\x8b\xe7\x9d\x80\xe5\x83\x8f\xe9\xaa\x9a\xe6\x89\xb0\xe7\x94\xb5\xe8\xaf\x9d\xef\xbc\x8c"
             "\xe8\xa6\x81\xe6\x88\x91\xe5\xb8\xae\xe4\xbd\xa0\xe5\xa4\x84\xe7\x90\x86\xe6\x8e\x89\xe5\x90\x97\xef\xbc\x9f");
    // "主人，{display}打来电话了，看着像骚扰电话，要我帮你处理掉吗？"
  } else {
    send_tts("\xe4\xb8\xbb\xe4\xba\xba\xef\xbc\x8c" + display +
             "\xe7\xbb\x99\xe4\xbd\xa0\xe6\x89\x93\xe7\x94\xb5\xe8\xaf\x9d\xe4\xba\x86\xef\xbc\x8c"
             "\xe4\xbd\xa0\xe7\x9c\x8b\xe6\x80\x8e\xe4\xb9\x88\xe5\xa4\x84\xe7\x90\x86\xef\xbc\x9f");
    // "主人，{display}给你打电话了，你看怎么处理？"
  }

  // Wait for client TTS playback to finish (with 8s timeout fallback)
  for (int wait = 0; wait < 80 && handling_ && !tts_done_; ++wait) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  // Extra 300ms silence gap after TTS ends to avoid mic picking up tail echo
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  if (!handling_) return;

  // Start STT for user voice command
  send_stt_start();

  // Countdown loop
  for (int remaining = COUNTDOWN_SECONDS; remaining > 0 && handling_; --remaining) {
    send_countdown(remaining);
    for (int tick = 0; tick < 10 && handling_; ++tick) {
      if (user_responded_) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (user_responded_) break;
  }

  send_stt_stop();

  if (!handling_) return;

  // Determine final action
  std::string final_action;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (user_action_ == "answer") {
      final_action = "answer";
    } else if (user_action_ == "reject" || user_action_ == "hangup") {
      final_action = "reject";
    } else if (user_action_ == "ended" || user_action_ == "answered") {
      handling_ = false;
      return;
    } else {
      final_action = is_spam ? "reject" : "reject";
    }
  }

  log::info("call_handler: executing action: " + final_action);
  send_countdown(0);

  // Tell client to execute the telephony action
  if (final_action == "answer") {
    execute_answer();
  } else {
    execute_reject();
  }

  handling_ = false;
}

void CallHandler::send_event(const std::string& event_name, const std::string& payload_json) {
  if (event_callback_) {
    event_callback_(event_name, payload_json);
  }
}

void CallHandler::send_tts(const std::string& text) {
  // Use avatar.command for TTS and state
  std::vector<json> steps;
  steps.push_back(avatar_cmd::step("setState", {{"state", "speaking"}}, 0));
  steps.push_back(avatar_cmd::step("setBubble", {{"text", text}}, 0));
  steps.push_back(avatar_cmd::step("tts", {{"text", text}}, 0));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

  // Also keep legacy call.tts for TTS completion callback
  json p;
  p["text"] = text;
  send_event("call.tts", p.dump());
}

void CallHandler::send_stt_start() {
  json p;
  p["keywords"] = json::array({
    "\xe6\x8e\xa5\xe5\x90\xac",   // 接听
    "\xe6\x8c\x82\xe6\x96\xad",   // 挂断
    "\xe6\x8b\x92\xe6\x8e\xa5",   // 拒接
    "answer", "reject", "hang up", "pick up"
  });
  send_event("call.stt.start", p.dump());
}

void CallHandler::send_stt_stop() {
  send_event("call.stt.stop", "{}");
}

void CallHandler::send_countdown(int remaining) {
  // Send via avatar.command for server-driven bubble updates
  if (remaining > 0) {
    std::string countdown_text = std::to_string(remaining) + "s";
    std::string bubble_text;
    int64_t bg_color;
    if (current_is_spam_) {
      bubble_text = "Spam! Auto-reject in " + std::to_string(remaining) + "s";
      bg_color = static_cast<int64_t>(0xFFD32F2F);
    } else {
      bubble_text = "Incoming call " + std::to_string(remaining) + "s";
      bg_color = static_cast<int64_t>(0xFF388E3C);
    }
    json cmd = avatar_cmd::make("setBubble", {
      {"text", bubble_text},
      {"bgColor", bg_color},
      {"textColor", static_cast<int64_t>(0xFFFFFFFF)},
      {"countdown", countdown_text}
    });
    avatar_cmd::send(event_callback_, cmd);
  } else {
    avatar_cmd::send(event_callback_, avatar_cmd::clear_bubble());
  }
}

void CallHandler::execute_answer() {
  log::info("call_handler: sending call.action answer with avatar choreography");
  // Avatar choreography for answering
  std::vector<json> steps;
  steps.push_back(avatar_cmd::step("setState", {{"state", "happy"}}, 0));
  steps.push_back(avatar_cmd::step("setBubble", {
    {"text", "Connecting..."},
    {"bgColor", static_cast<int64_t>(0xFF388E3C)},
    {"textColor", static_cast<int64_t>(0xFFFFFFFF)}
  }, 500));
  steps.push_back(avatar_cmd::step("performAction", {{"type", "tap"}}, 300));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

  json p;
  p["action"] = "answer";
  send_event("call.action", p.dump());

  // Post-action cleanup via avatar.command (delayed)
  std::vector<json> cleanup;
  cleanup.push_back(avatar_cmd::step("cancelMovement", json::object(), 1500));
  cleanup.push_back(avatar_cmd::step("setState", {{"state", "idle"}}, 0));
  cleanup.push_back(avatar_cmd::step("setColorFilter", {{"color", nullptr}}, 0));
  cleanup.push_back(avatar_cmd::step("clearBubble", json::object(), 0));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(cleanup));

  json chat_msg;
  chat_msg["text"] = "Answering call...";
  chat_msg["role"] = "assistant";
  send_event("chat.local_message", chat_msg.dump());
}

void CallHandler::execute_reject() {
  log::info("call_handler: sending call.action reject with avatar choreography");
  // Avatar choreography for rejecting
  std::vector<json> steps;
  steps.push_back(avatar_cmd::step("setState", {{"state", "angry"}}, 0));
  steps.push_back(avatar_cmd::step("setBubble", {
    {"text", "Rejecting!"},
    {"bgColor", static_cast<int64_t>(0xFFD32F2F)},
    {"textColor", static_cast<int64_t>(0xFFFFFFFF)}
  }, 500));
  steps.push_back(avatar_cmd::step("performAction", {{"type", "tap"}}, 300));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

  json p;
  p["action"] = "reject";
  send_event("call.action", p.dump());

  // Post-action cleanup
  std::vector<json> cleanup;
  cleanup.push_back(avatar_cmd::step("cancelMovement", json::object(), 1500));
  cleanup.push_back(avatar_cmd::step("setState", {{"state", "idle"}}, 0));
  cleanup.push_back(avatar_cmd::step("setColorFilter", {{"color", nullptr}}, 0));
  cleanup.push_back(avatar_cmd::step("clearBubble", json::object(), 0));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(cleanup));

  json chat_msg;
  chat_msg["text"] = "Rejecting call";
  chat_msg["role"] = "assistant";
  send_event("chat.local_message", chat_msg.dump());
}

bool CallHandler::lookup_spam(const std::string& number) {
  // TODO: Integrate with spam database or skill
  // Future: query a spam detection API or local blocklist
  log::info("call_handler: spam lookup for " + number + " -> not spam (placeholder)");
  return false;
}

bool CallHandler::detect_spam_from_contact(const std::string& contact_name) {
  if (contact_name.empty()) return false;
  static const std::vector<std::string> spam_keywords = {
    "\xe5\xb9\xbf\xe5\x91\x8a",       // 广告
    "\xe6\x8e\xa8\xe9\x94\x80",       // 推销
    "\xe9\xaa\x9a\xe6\x89\xb0",       // 骚扰
    "\xe8\xaf\x88\xe9\xaa\x97",       // 诈骗
    "\xe4\xb8\xad\xe4\xbb\x8b",       // 中介
    "\xe8\xb4\xb7\xe6\xac\xbe",       // 贷款
    "\xe4\xbf\x9d\xe9\x99\xa9",       // 保险
    "\xe5\x9e\x83\xe5\x9c\xbe",       // 垃圾
    "spam",
    "scam",
    "telemarket",
    "adverti",
  };
  for (const auto& kw : spam_keywords) {
    if (contact_name.find(kw) != std::string::npos) {
      log::info("call_handler: contact name '" + contact_name + "' matches spam keyword");
      return true;
    }
  }
  return false;
}


}  // namespace net
}  // namespace hiclaw
