#include "hiclaw/net/notification_handler.hpp"
#include "hiclaw/net/avatar_command.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>

namespace hiclaw {
namespace net {

using json = nlohmann::json;

const std::unordered_set<std::string> NotificationHandler::important_packages_ = {
  "com.tencent.mm",                    // WeChat
  "com.tencent.mobileqq",             // QQ
  "com.android.mms",                   // SMS (AOSP)
  "com.google.android.apps.messaging", // Google Messages
  "com.samsung.android.messaging",     // Samsung Messages
  "com.miui.smsextra",                 // Xiaomi SMS
  "com.coloros.sms",                   // OPPO/Realme SMS
  "com.huawei.message",               // Huawei SMS
  "com.oneplus.mms",                   // OnePlus SMS
  "com.iqoo.sms",                      // Vivo/iQOO SMS
  "com.android.messaging",            // AOSP Messaging
  "com.alibaba.android.rimet",        // DingTalk
  "com.eg.android.AlipayGphone",      // Alipay
  "com.ss.android.lark",              // Feishu/Lark
};

const std::vector<std::string> NotificationHandler::important_categories_ = {
  "msg", "call", "alarm", "email", "social"
};

const std::vector<std::string> NotificationHandler::messaging_substrings_ = {
  "sms", "mms", "messaging", "message"
};

NotificationHandler::NotificationHandler(EventCallback event_cb)
    : event_callback_(std::move(event_cb)) {}

bool NotificationHandler::is_important(const std::string& package_name, const std::string& category) const {
  if (important_packages_.count(package_name)) return true;

  if (!category.empty()) {
    for (const auto& cat : important_categories_) {
      if (category == cat) return true;
    }
  }

  std::string pkg_lower = package_name;
  std::transform(pkg_lower.begin(), pkg_lower.end(), pkg_lower.begin(), ::tolower);
  for (const auto& sub : messaging_substrings_) {
    if (pkg_lower.find(sub) != std::string::npos) return true;
  }

  return false;
}

bool NotificationHandler::on_notification_changed(const std::string& payload_json) {
  try {
    json payload = json::parse(payload_json);
    std::string change = payload.value("change", "");
    if (change != "posted") return false;

    std::string pkg = payload.value("packageName", "");
    std::string category = payload.value("category", "");
    std::string title = payload.value("title", "");
    std::string text = payload.value("text", "");

    if (!is_important(pkg, category)) return false;

    log::info("notification_handler: important notification from " + pkg + ": " + title);

    // Build display text
    std::string display;
    if (!title.empty() && !text.empty()) {
      display = title + ": " + text;
    } else if (!title.empty()) {
      display = title;
    } else if (!text.empty()) {
      display = text;
    } else {
      display = "new notification";
    }
    if (display.length() > 60) {
      display = display.substr(0, 57) + "...";
    }

    // Send avatar reaction
    std::vector<json> steps;
    steps.push_back(avatar_cmd::step("setState", {{"state", "watching"}, {"temporary", true}}, 0));
    steps.push_back(avatar_cmd::step("setBubble", {{"text", "\xf0\x9f\x92\xa1 " + display}}, 0));
    // 💡
    steps.push_back(avatar_cmd::step("playSound", {{"type", "notification"}}, 0));
    avatar_cmd::send(event_callback_, avatar_cmd::sequence(steps));

    return true;
  } catch (const std::exception& e) {
    log::info("notification_handler: parse error: " + std::string(e.what()));
    return false;
  }
}

}  // namespace net
}  // namespace hiclaw
