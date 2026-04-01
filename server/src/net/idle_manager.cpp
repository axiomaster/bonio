#include "hiclaw/net/idle_manager.hpp"
#include "hiclaw/net/avatar_command.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#include <cmath>

namespace hiclaw {
namespace net {

using json = nlohmann::json;

static int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

IdleManager::IdleManager(EventCallback event_cb)
    : event_callback_(std::move(event_cb)),
      rng_(static_cast<unsigned int>(std::chrono::steady_clock::now().time_since_epoch().count())),
      last_wander_time_ms_(now_ms()),
      next_wander_interval_ms_(random_interval()) {}

int64_t IdleManager::random_interval() {
  std::uniform_int_distribution<int64_t> dist(MIN_INTERVAL_MS, MAX_INTERVAL_MS);
  return dist(rng_);
}

void IdleManager::on_device_status(const std::string& payload_json) {
  std::lock_guard<std::mutex> lock(mutex_);
  try {
    json payload = json::parse(payload_json);
    enabled_ = payload.value("idleWanderEnabled", false);
    float avatar_x = payload.value("avatarX", 0.0f);
    float avatar_y = payload.value("avatarY", 0.0f);
    std::string activity = payload.value("avatarActivity", "idle");
    std::string motion = payload.value("avatarMotion", "stationary");
    float screen_w = payload.value("screenWidth", 1080.0f);
    float screen_h = payload.value("screenHeight", 2400.0f);

    if (!enabled_) return;

    maybe_wander(avatar_x, avatar_y, activity, motion, screen_w, screen_h);
  } catch (const std::exception& e) {
    log::info("idle_manager: failed to parse device.status: " + std::string(e.what()));
  }
}

void IdleManager::maybe_wander(float avatar_x, float avatar_y,
                                const std::string& activity, const std::string& motion,
                                float screen_w, float screen_h) {
  bool can_wander = (activity == "idle" || activity == "bored") && motion == "stationary";
  if (!can_wander) return;

  int64_t now = now_ms();
  if (now - last_wander_time_ms_ < next_wander_interval_ms_) return;

  last_wander_time_ms_ = now;
  next_wander_interval_ms_ = random_interval();

  std::uniform_real_distribution<float> dx_dist(-WANDER_RADIUS, WANDER_RADIUS);
  float tx = avatar_x + dx_dist(rng_);
  float ty = avatar_y + dx_dist(rng_);

  // Clamp within screen
  tx = std::max(0.0f, std::min(tx, screen_w - 100.0f));
  ty = std::max(100.0f, std::min(ty, screen_h - 100.0f));

  avatar_cmd::send(event_callback_, avatar_cmd::move_to(tx, ty, "walk"));
}

}  // namespace net
}  // namespace hiclaw
