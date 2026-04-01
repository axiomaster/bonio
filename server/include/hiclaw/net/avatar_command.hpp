#ifndef HICLAW_NET_AVATAR_COMMAND_HPP
#define HICLAW_NET_AVATAR_COMMAND_HPP

#include "hiclaw/net/async_agent.hpp"
#include <nlohmann/json.hpp>
#include <string>

namespace hiclaw {
namespace net {

/**
 * Helper to build avatar.command event payloads.
 * The client's AvatarCommandExecutor interprets these.
 */
namespace avatar_cmd {

inline nlohmann::json make(const std::string& action, const nlohmann::json& params = nlohmann::json::object()) {
  nlohmann::json cmd;
  cmd["action"] = action;
  cmd["params"] = params;
  return cmd;
}

inline nlohmann::json set_state(const std::string& state, bool temporary = false) {
  nlohmann::json p;
  p["state"] = state;
  if (temporary) p["temporary"] = true;
  return make("setState", p);
}

inline nlohmann::json move_to(float x, float y, const std::string& mode = "walk") {
  nlohmann::json p;
  p["x"] = x;
  p["y"] = y;
  p["mode"] = mode;
  return make("moveTo", p);
}

inline nlohmann::json set_bubble(const std::string& text) {
  nlohmann::json p;
  p["text"] = text;
  return make("setBubble", p);
}

inline nlohmann::json set_bubble(const std::string& text, int64_t bg_color, int64_t text_color = 0xFFFFFFFF) {
  nlohmann::json p;
  p["text"] = text;
  p["bgColor"] = bg_color;
  p["textColor"] = text_color;
  return make("setBubble", p);
}

inline nlohmann::json set_bubble_countdown(const std::string& text, const std::string& countdown) {
  nlohmann::json p;
  p["text"] = text;
  p["countdown"] = countdown;
  return make("setBubble", p);
}

inline nlohmann::json clear_bubble() {
  return make("clearBubble");
}

inline nlohmann::json tts(const std::string& text) {
  nlohmann::json p;
  p["text"] = text;
  return make("tts", p);
}

inline nlohmann::json stop_tts() {
  return make("stopTts");
}

inline nlohmann::json play_sound(const std::string& type = "notification") {
  nlohmann::json p;
  p["type"] = type;
  return make("playSound", p);
}

inline nlohmann::json set_color_filter(int64_t color) {
  nlohmann::json p;
  p["color"] = color;
  return make("setColorFilter", p);
}

inline nlohmann::json clear_color_filter() {
  nlohmann::json p;
  p["color"] = nullptr;
  return make("setColorFilter", p);
}

inline nlohmann::json set_position(float x, float y) {
  nlohmann::json p;
  p["x"] = x;
  p["y"] = y;
  return make("setPosition", p);
}

inline nlohmann::json cancel_movement() {
  return make("cancelMovement");
}

inline nlohmann::json perform_action(const std::string& type) {
  nlohmann::json p;
  p["type"] = type;
  return make("performAction", p);
}

inline nlohmann::json sequence(const std::vector<nlohmann::json>& steps) {
  nlohmann::json p;
  p["steps"] = nlohmann::json::array();
  for (const auto& s : steps) {
    p["steps"].push_back(s);
  }
  return make("sequence", p);
}

inline nlohmann::json step(const std::string& action, const nlohmann::json& params, int64_t delay_ms = 0) {
  nlohmann::json s;
  s["action"] = action;
  s["params"] = params;
  if (delay_ms > 0) s["delayMs"] = delay_ms;
  return s;
}

/**
 * Send an avatar.command event via the session event callback.
 */
inline void send(const EventCallback& cb, const nlohmann::json& cmd) {
  if (cb) {
    cb("avatar.command", cmd.dump());
  }
}

}  // namespace avatar_cmd

}  // namespace net
}  // namespace hiclaw

#endif
