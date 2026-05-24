#ifndef HICLAW_NET_WECHAT_ADAPTER_HPP
#define HICLAW_NET_WECHAT_ADAPTER_HPP

#include "hiclaw/config/config.hpp"
#include "hiclaw/net/async_agent.hpp"
#include "hiclaw/net/gateway.hpp"
#include "hiclaw/net/ilink_http_client.hpp"
#include "hiclaw/net/tool_router.hpp"
#include "hiclaw/session/store.hpp"
#include <atomic>
#include <memory>
#include <string>
#include <thread>
#include <mutex>
#include <unordered_map>

namespace hiclaw {
namespace net {

/// WeChat channel adapter: receives messages from WeCom/ilink, dispatches to
/// the agent, and sends responses back.
class WeChatAdapter {
public:
  explicit WeChatAdapter(const config::Config& config,
                         GatewayBroadcastRef broadcast = nullptr,
                         WeChatSendRef desktop_sender = nullptr,
                         NodeInvokeRef node_invoker = nullptr,
                         ExternalRouterRegistry external_routers = nullptr);
  ~WeChatAdapter();

  WeChatAdapter(const WeChatAdapter&) = delete;
  WeChatAdapter& operator=(const WeChatAdapter&) = delete;

  /// Start the adapter in the calling thread (blocks until stop()).
  void start();

  /// Signal the adapter to stop.
  void stop();

private:
  void handle_message(const std::string& msg_id,
                      const std::string& user_id,
                      const std::string& chat_id,
                      const std::string& chat_type,
                      const std::string& content,
                      const std::string& callback_req_id);

  bool is_user_allowed(const std::string& user_id) const;
  bool is_duplicate(const std::string& msg_id);
  bool send_desktop_message(const std::string& session_key,
                            const std::string& content,
                            bool is_reply,
                            std::string& error_message);

  void run_ilink_loop();
  void handle_ilink_message(const IlinkHttpClient::Message& msg);
  std::string get_state_dir() const;

  const config::Config& config_;
  GatewayBroadcastRef broadcast_;
  WeChatSendRef desktop_sender_;
  NodeInvokeRef node_invoker_;
  ExternalRouterRegistry external_routers_;
  std::atomic<bool> running_{false};

  std::shared_ptr<session::SessionStore> session_store_;
  std::shared_ptr<ToolRouter> tool_router_;
  std::unique_ptr<AsyncAgentManager> agent_manager_;
  std::unique_ptr<class WecomWsClient> wecom_client_;
  std::unique_ptr<IlinkHttpClient> ilink_client_;

  // Reply contexts: session_key -> last callback_req_id (WeCom) or user_id (ilink)
  std::mutex reply_ctx_mutex_;
  std::unordered_map<std::string, std::string> pending_reply_ctx_;

  // Message deduplication
  std::mutex dedup_mutex_;
  std::unordered_map<std::string, int64_t> dedup_cache_;
};

}  // namespace net
}  // namespace hiclaw

#endif  // HICLAW_NET_WECHAT_ADAPTER_HPP
