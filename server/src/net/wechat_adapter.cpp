#include "hiclaw/net/wechat_adapter.hpp"
#include "hiclaw/net/wecom_ws_client.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#include <thread>

#ifdef _WIN32
#include <direct.h>
#define MKDIR(p) _mkdir(p)
#else
#include <sys/stat.h>
#define MKDIR(p) mkdir(p, 0755)
#endif

namespace hiclaw {
namespace net {

namespace {

using json = nlohmann::json;

static const int kDedupTtlSeconds = 300;  // 5 minutes

}  // namespace

WeChatAdapter::WeChatAdapter(const config::Config& config)
    : config_(config) {
  session_store_ = std::make_shared<session::SessionStore>(config.config_dir);

  // Event callback: captures final response and sends to WeChat
  auto event_callback = [this](const std::string& event_name,
                               const std::string& payload_json) {
    if (event_name != "chat") return;
    try {
      auto j = json::parse(payload_json);
      std::string session_key = j.value("sessionKey", "");
      std::string state = j.value("state", "");

      if (state == "final") {
        std::string content = j.value("message", "");
        if (content.empty()) return;

        // Look up the reply context for this session
        std::string reply_to;
        {
          std::lock_guard<std::mutex> lock(reply_ctx_mutex_);
          auto it = pending_reply_ctx_.find(session_key);
          if (it != pending_reply_ctx_.end()) {
            reply_to = it->second;
            pending_reply_ctx_.erase(it);
          }
        }

        if (!reply_to.empty() && wecom_client_) {
          wecom_client_->reply(reply_to, content);
          log::info("wechat: sent reply for session " + session_key +
                    " (" + std::to_string(content.size()) + " chars)");
        } else if (!reply_to.empty() && ilink_client_) {
          ilink_client_->send_message(reply_to, content);
          log::info("wechat: sent ilink reply for session " + session_key +
                    " (" + std::to_string(content.size()) + " chars)");
        }
      } else if (state == "error") {
        std::string error_msg = j.value("errorMessage", "Agent error");

        std::string reply_to;
        {
          std::lock_guard<std::mutex> lock(reply_ctx_mutex_);
          auto it = pending_reply_ctx_.find(session_key);
          if (it != pending_reply_ctx_.end()) {
            reply_to = it->second;
            pending_reply_ctx_.erase(it);
          }
        }

        if (!reply_to.empty() && wecom_client_) {
          wecom_client_->reply(reply_to, "[Error] " + error_msg);
        } else if (!reply_to.empty() && ilink_client_) {
          ilink_client_->send_message(reply_to, "[Error] " + error_msg);
        }
      }
    } catch (const json::parse_error& e) {
      log::warn("wechat: failed to parse event: " + std::string(e.what()));
    }
  };

  // No ToolRouter — WeChat sessions have no device node for remote tools
  agent_manager_ = std::make_unique<AsyncAgentManager>(
      config_, event_callback, session_store_, nullptr);
}

WeChatAdapter::~WeChatAdapter() {
  stop();
}

void WeChatAdapter::start() {
  running_ = true;
  const auto& wc = config_.wechat;

  log::info("wechat: adapter starting, mode=" + wc.mode);

  if (wc.mode == "weixin") {
    std::string state_dir = get_state_dir();
    MKDIR(state_dir.c_str());

    ilink_client_ = std::make_unique<IlinkHttpClient>(
        wc.weixin.token, wc.weixin.base_url, state_dir);
    run_ilink_loop();
  } else if (wc.mode == "wecom") {
    wecom_client_ = std::make_unique<WecomWsClient>(
        wc.wecom.bot_id, wc.wecom.bot_secret);

    auto on_message = [this](const std::string& msg_id,
                             const std::string& user_id,
                             const std::string& chat_id,
                             const std::string& chat_type,
                             const std::string& content,
                             const std::string& callback_req_id) {
      handle_message(msg_id, user_id, chat_id, chat_type, content, callback_req_id);
    };

    wecom_client_->run(on_message);
  } else {
    log::error("wechat: unsupported mode '" + wc.mode + "'");
  }

  running_ = false;
}

void WeChatAdapter::stop() {
  running_ = false;
  if (wecom_client_) {
    wecom_client_->stop();
  }
  if (ilink_client_) {
    ilink_client_->stop();
  }
}

void WeChatAdapter::handle_message(const std::string& msg_id,
                                   const std::string& user_id,
                                   const std::string& chat_id,
                                   const std::string& chat_type,
                                   const std::string& content,
                                   const std::string& callback_req_id) {
  if (!running_) return;

  // Access control
  if (!is_user_allowed(user_id)) {
    log::warn("wechat: message from unauthorized user: " + user_id);
    return;
  }

  // Deduplication
  if (is_duplicate(msg_id)) {
    log::debug("wechat: duplicate message " + msg_id);
    return;
  }

  // Build session key
  std::string session_key;
  if (chat_type == "group") {
    session_key = "wechat:wecom:" + chat_id + ":" + user_id;
  } else {
    session_key = "wechat:wecom:" + user_id;
  }

  log::info("wechat: message from " + user_id +
            " session=" + session_key +
            " content=(" + std::to_string(content.size()) + " chars)");

  // Save reply context for this session
  {
    std::lock_guard<std::mutex> lock(reply_ctx_mutex_);
    pending_reply_ctx_[session_key] = callback_req_id;
  }

  // Save user message to session store
  session::Message user_msg;
  user_msg.role = "user";
  user_msg.content = content;
  user_msg.timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  session_store_->add_message(session_key, user_msg);

  // Start agent task
  agent_manager_->start_task(session_key, content);
}

bool WeChatAdapter::is_user_allowed(const std::string& user_id) const {
  const auto& allow = config_.wechat.allow_from;
  if (allow.empty()) return true;  // Empty = allow all
  for (const auto& u : allow) {
    if (u == user_id || u == "*") return true;
  }
  return false;
}

bool WeChatAdapter::is_duplicate(const std::string& msg_id) {
  if (msg_id.empty()) return false;

  auto now = std::chrono::duration_cast<std::chrono::seconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();

  std::lock_guard<std::mutex> lock(dedup_mutex_);

  // Evict expired entries
  for (auto it = dedup_cache_.begin(); it != dedup_cache_.end(); ) {
    if (now - it->second > kDedupTtlSeconds) {
      it = dedup_cache_.erase(it);
    } else {
      ++it;
    }
  }

  auto it = dedup_cache_.find(msg_id);
  if (it != dedup_cache_.end()) return true;

  dedup_cache_[msg_id] = now;
  return false;
}

std::string WeChatAdapter::get_state_dir() const {
  return config_.config_dir + "/weixin";
}

void WeChatAdapter::run_ilink_loop() {
  log::info("wechat: ilink polling loop started");

  int backoff_ms = 1000;
  static const int kMaxBackoffMs = 30000;

  while (running_) {
    std::vector<IlinkHttpClient::Message> msgs;
    if (!ilink_client_->get_updates(msgs)) {
      if (!running_) break;
      log::warn("wechat: ilink getUpdates failed, retry in " +
                std::to_string(backoff_ms) + "ms");
      std::this_thread::sleep_for(std::chrono::milliseconds(backoff_ms));
      backoff_ms = std::min(backoff_ms * 2, kMaxBackoffMs);
      continue;
    }

    // Reset backoff on success
    backoff_ms = 1000;

    for (auto& msg : msgs) {
      if (!running_) break;
      // Only handle user messages (type=1)
      if (msg.message_type != 1) continue;
      if (msg.content.empty()) continue;
      handle_ilink_message(msg);
    }
  }

  log::info("wechat: ilink polling loop stopped");
}

void WeChatAdapter::handle_ilink_message(const IlinkHttpClient::Message& msg) {
  if (!running_) return;

  std::string user_id = msg.from_user_id;

  // Access control
  if (!is_user_allowed(user_id)) {
    log::warn("wechat: ilink message from unauthorized user: " + user_id);
    return;
  }

  // Deduplication
  std::string dedup_key = user_id + "|" + std::to_string(msg.message_id);
  if (is_duplicate(dedup_key)) {
    log::debug("wechat: ilink duplicate message " + std::to_string(msg.message_id));
    return;
  }

  // Session key
  std::string session_key = "wechat:weixin:" + user_id;

  log::info("wechat: ilink message from " + user_id +
            " session=" + session_key +
            " content=(" + std::to_string(msg.content.size()) + " chars)");

  // Save reply context: session_key -> user_id (for ilink, reply to = user_id)
  {
    std::lock_guard<std::mutex> lock(reply_ctx_mutex_);
    pending_reply_ctx_[session_key] = user_id;
  }

  // Save user message to session store
  session::Message user_msg;
  user_msg.role = "user";
  user_msg.content = msg.content;
  user_msg.timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
  session_store_->add_message(session_key, user_msg);

  // Start agent task
  agent_manager_->start_task(session_key, msg.content);
}

}  // namespace net
}  // namespace hiclaw
