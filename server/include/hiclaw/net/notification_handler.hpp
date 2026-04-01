#ifndef HICLAW_NET_NOTIFICATION_HANDLER_HPP
#define HICLAW_NET_NOTIFICATION_HANDLER_HPP

#include "hiclaw/net/async_agent.hpp"
#include <string>
#include <unordered_set>
#include <vector>

namespace hiclaw {
namespace net {

class NotificationHandler {
public:
  explicit NotificationHandler(EventCallback event_cb);

  /**
   * Evaluate a notifications.changed event.
   * If important, sends avatar.command for reaction and returns true.
   */
  bool on_notification_changed(const std::string& payload_json);

private:
  bool is_important(const std::string& package_name, const std::string& category) const;

  EventCallback event_callback_;

  static const std::unordered_set<std::string> important_packages_;
  static const std::vector<std::string> important_categories_;
  static const std::vector<std::string> messaging_substrings_;
};

}  // namespace net
}  // namespace hiclaw

#endif
