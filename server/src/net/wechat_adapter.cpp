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

WeChatAdapter::WeChatAdapter(const config::Config& config,
                             GatewayBroadcastRef broadcast,
                             WeChatSendRef desktop_sender,
                             NodeInvokeRef node_invoker,
                             ExternalRouterRegistry external_routers)
    : config_(config), broadcast_(broadcast), desktop_sender_(desktop_sender),
      node_invoker_(node_invoker), external_routers_(external_routers) {
  session_store_ = std::make_shared<session::SessionStore>(config.config_dir);

  // Create a ToolRouter so remote tools (screen.capture, etc.) can be used
  tool_router_ = std::make_shared<ToolRouter>();

  if (desktop_sender_) {
    *desktop_sender_ = [this](const std::string& session_key,
                              const std::string& content,
                              bool is_reply,
                              std::string& error_message) {
      return send_desktop_message(session_key, content, is_reply, error_message);
    };
  }

  // Event callback: captures final response and sends to WeChat, plus
  // forwards all agent/chat events to connected gateway clients.
  auto event_callback = [this](const std::string& event_name,
                               const std::string& payload_json) {
    // Route node.invoke.request to connected desktop node
    if (event_name == "node.invoke.request") {
      if (node_invoker_ && *node_invoker_) {
        try {
          auto j = json::parse(payload_json);
          std::string invoke_id = j.value("id", "");
          std::string tool_call_id = invoke_id;
          if (tool_call_id.rfind("invoke_", 0) == 0) {
            tool_call_id = tool_call_id.substr(7);
          }
          // Register in external router before sending
          if (external_routers_ && tool_router_) {
            (*external_routers_)[tool_call_id] = tool_router_.get();
          }
          bool sent = (*node_invoker_)(tool_call_id, payload_json);
          if (!sent) {
            log::warn("wechat: no connected node for remote tool " + tool_call_id);
            // Complete with error so agent doesn't hang
            tool_router_->complete_tool_call(tool_call_id,
                ToolResult{false, "", "No connected device node available"});
          }
        } catch (const std::exception& e) {
          log::warn("wechat: failed to route node.invoke.request: " + std::string(e.what()));
        }
      } else {
        log::warn("wechat: node.invoke.request but no node_invoker available");
      }
      return;
    }

    // Forward all agent/chat events to gateway operator sessions
    if (broadcast_ && *broadcast_) {
      if (event_name == "agent" || event_name == "chat") {
        (*broadcast_)(event_name, payload_json);
      }
    }

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

  // Pass ToolRouter so remote tools are available when a desktop node is connected
  agent_manager_ = std::make_unique<AsyncAgentManager>(
      config_, event_callback, session_store_, tool_router_);
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
  if (desktop_sender_) {
    *desktop_sender_ = [](const std::string&, const std::string&, bool, std::string& error_message) {
      error_message = "WeChat adapter is stopped";
      return false;
    };
  }
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

bool WeChatAdapter::send_desktop_message(const std::string& session_key,
                                         const std::string& content,
                                         bool is_reply,
                                         std::string& error_message) {
  if (!running_) {
    error_message = "WeChat adapter is not running";
    return false;
  }

  static const std::string kWeixinPrefix = "wechat:weixin:";
  static const std::string kWecomPrefix = "wechat:wecom:";

  if (session_key.rfind(kWeixinPrefix, 0) == 0) {
    std::string user_id = session_key.substr(kWeixinPrefix.size());
    if (user_id.empty()) {
      error_message = "missing WeChat user id";
      return false;
    }
    if (!is_user_allowed(user_id)) {
      error_message = "WeChat user is not allowed";
      return false;
    }
    if (!ilink_client_) {
      error_message = "personal WeChat client is not ready";
      return false;
    }
    std::string mirrored_content = is_reply ? content : ("[来自 Bonio Desktop]\n" + content);
    if (!ilink_client_->send_message(user_id, mirrored_content)) {
      error_message = "failed to send message to personal WeChat";
      return false;
    }
    log::info("wechat: sent desktop message for session " + session_key +
              " (" + std::to_string(content.size()) + " chars)");
    return true;
  }

  if (session_key.rfind(kWecomPrefix, 0) == 0) {
    error_message = "Enterprise WeChat proactive send is not supported by this channel";
    return false;
  }

  error_message = "not a WeChat session";
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
