#ifndef HICLAW_NET_HEALTH_MONITOR_HPP
#define HICLAW_NET_HEALTH_MONITOR_HPP

#include "hiclaw/net/async_agent.hpp"
#include <atomic>
#include <chrono>
#include <mutex>
#include <string>

namespace hiclaw {
namespace net {

class HealthMonitor {
public:
  explicit HealthMonitor(EventCallback event_cb);

  void on_device_status(const std::string& payload_json);

private:
  void check_and_nag();
  void send_gentle_nag();
  void send_strong_nag();

  EventCallback event_callback_;
  std::mutex mutex_;

  bool enabled_ = false;
  int64_t screen_on_accum_ms_ = 0;
  int64_t last_status_time_ms_ = 0;
  int64_t last_nag_time_ms_ = 0;
  int nag_level_ = 0;

  static constexpr int late_night_start_hour_ = 23;
  static constexpr int late_night_end_hour_ = 6;
  static constexpr int64_t max_continuous_use_ms_ = 2 * 60 * 60 * 1000LL;
  static constexpr int64_t nag_cooldown_ms_ = 15 * 60 * 1000LL;
};

}  // namespace net
}  // namespace hiclaw

#endif
