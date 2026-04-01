#ifndef HICLAW_NET_IDLE_MANAGER_HPP
#define HICLAW_NET_IDLE_MANAGER_HPP

#include "hiclaw/net/async_agent.hpp"
#include <mutex>
#include <random>
#include <string>

namespace hiclaw {
namespace net {

class IdleManager {
public:
  explicit IdleManager(EventCallback event_cb);

  void on_device_status(const std::string& payload_json);

private:
  EventCallback event_callback_;
  std::mutex mutex_;
  std::mt19937 rng_;

  int64_t last_wander_time_ms_ = 0;
  int64_t next_wander_interval_ms_ = 0;
  bool enabled_ = false;

  static constexpr int64_t MIN_INTERVAL_MS = 8000;
  static constexpr int64_t MAX_INTERVAL_MS = 20000;
  static constexpr float WANDER_RADIUS = 300.0f;

  void maybe_wander(float avatar_x, float avatar_y, const std::string& activity,
                    const std::string& motion, float screen_w, float screen_h);
  int64_t random_interval();
};

}  // namespace net
}  // namespace hiclaw

#endif
