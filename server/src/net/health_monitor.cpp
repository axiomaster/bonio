#include "hiclaw/net/health_monitor.hpp"
#include "hiclaw/net/avatar_command.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <ctime>

namespace hiclaw {
namespace net {

using json = nlohmann::json;

static int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

HealthMonitor::HealthMonitor(EventCallback event_cb)
    : event_callback_(std::move(event_cb)), last_status_time_ms_(now_ms()) {}

void HealthMonitor::on_device_status(const std::string& payload_json) {
  std::lock_guard<std::mutex> lock(mutex_);
  try {
    json payload = json::parse(payload_json);
    bool screen_on = payload.value("screenOn", false);
    int hour = payload.value("hour", -1);
    enabled_ = payload.value("healthNagEnabled", false);

    int64_t now = now_ms();
    int64_t delta = now - last_status_time_ms_;
    if (delta < 0) delta = 0;
    last_status_time_ms_ = now;

    if (screen_on) {
      screen_on_accum_ms_ += delta;
    } else {
      screen_on_accum_ms_ = 0;
    }

    if (!enabled_) {
      nag_level_ = 0;
      return;
    }

    // Determine late night
    bool is_late = false;
    if (hour >= 0) {
      is_late = (hour >= late_night_start_hour_ || hour < late_night_end_hour_);
    }

    bool continuous_overuse = is_late && (screen_on_accum_ms_ >= max_continuous_use_ms_);
    bool should_nag = is_late || continuous_overuse;

    if (!should_nag) {
      nag_level_ = 0;
      return;
    }

    if (now - last_nag_time_ms_ < nag_cooldown_ms_) return;

    nag_level_++;
    last_nag_time_ms_ = now;

    if (nag_level_ <= 1) {
      send_gentle_nag();
    } else {
      send_strong_nag();
    }
  } catch (const std::exception& e) {
    log::info("health_monitor: failed to parse device.status: " + std::string(e.what()));
  }
}

void HealthMonitor::send_gentle_nag() {
  log::info("health_monitor: sending gentle nag");
  // sequence: setState sleeping -> setBubble -> delay 5s -> clearBubble
  std::vector<json> steps;
  steps.push_back(avatar_cmd::step("setState", {{"state", "sleeping"}}, 0));
  steps.push_back(avatar_cmd::step("setBubble", {{"text", "\xe4\xb8\xbb\xe4\xba\xba\xef\xbc\x8c\xe5\xa5\xbd\xe6\x99\x9a\xe4\xba\x86\xe5\x96\xb5\xe2\x80\xa6"}}, 5000));
  // "主人，好晚了喵…"
  steps.push_back(avatar_cmd::step("clearBubble", json::object(), 0));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));
}

void HealthMonitor::send_strong_nag() {
  log::info("health_monitor: sending strong nag");
  // sequence: moveTo center -> angry + bubble + tts -> delay -> confused -> walkTo edge -> sleeping
  std::vector<json> steps;
  // Move to screen center (approximate; client will clamp)
  steps.push_back(avatar_cmd::step("moveTo", {{"x", 450}, {"y", 1000}, {"mode", "run"}}, 2000));
  steps.push_back(avatar_cmd::step("setState", {{"state", "angry"}}, 0));
  steps.push_back(avatar_cmd::step("setBubble", {{"text", "\xe8\xbf\x98\xe4\xb8\x8d\xe7\x9d\xa1\xe8\xa7\x89\xef\xbc\x81""BoJi\xe7\x9a\x84\xe6\xaf\x9b\xe9\x83\xbd\xe8\xa6\x81\xe6\x8e\x89\xe5\x85\x89\xe4\xba\x86\xef\xbc\x81\xe5\xbf\xab\xe5\x85\xb3\xe6\x8e\x89\xe6\x89\x8b\xe6\x9c\xba\xe7\x9d\xa1\xe8\xa7\x89\xe5\x96\xb5\xef\xbc\x81"}}, 0));
  // "还不睡觉！BoJi的毛都要掉光了！快关掉手机睡觉喵！"
  steps.push_back(avatar_cmd::step("tts", {{"text", "\xe8\xbf\x98\xe4\xb8\x8d\xe7\x9d\xa1\xe8\xa7\x89\xef\xbc\x81\xe5\xbf\xab\xe5\x85\xb3\xe6\x8e\x89\xe6\x89\x8b\xe6\x9c\xba\xe7\x9d\xa1\xe8\xa7\x89\xe5\x96\xb5\xef\xbc\x81"}}, 5000));
  // "还不睡觉！快关掉手机睡觉喵！"
  steps.push_back(avatar_cmd::step("setState", {{"state", "confused"}}, 0));
  steps.push_back(avatar_cmd::step("setBubble", {{"text", "\xe5\x94\xa4\xe2\x80\xa6"}}, 2000));
  // "唤…"
  steps.push_back(avatar_cmd::step("clearBubble", json::object(), 0));
  steps.push_back(avatar_cmd::step("moveTo", {{"x", 60}, {"y", 1700}, {"mode", "walk"}}, 3000));
  steps.push_back(avatar_cmd::step("setState", {{"state", "sleeping"}}, 0));
  avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));
}

}  // namespace net
}  // namespace hiclaw
