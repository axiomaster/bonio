#ifndef HICLAW_NET_GATEWAY_HPP
#define HICLAW_NET_GATEWAY_HPP

#include "hiclaw/config/config.hpp"
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>

namespace hiclaw {
namespace net {

/// Shared broadcast function: gateway_run sets it, other components call it.
/// Initially a no-op; becomes live once the WebSocket server starts accepting connections.
using GatewayBroadcastFn = std::function<void(const std::string& event_name,
                                               const std::string& payload_json)>;
using GatewayBroadcastRef = std::shared_ptr<GatewayBroadcastFn>;

/// Shared WeChat send function: WeChatAdapter sets it once the channel client is ready.
/// Returns true when the message was accepted by the channel.
using WeChatSendFn = std::function<bool(const std::string& session_key,
                                        const std::string& content,
                                        bool is_reply,
                                        std::string& error_message)>;
using WeChatSendRef = std::shared_ptr<WeChatSendFn>;

/// Shared node invoke function: gateway_run populates it to allow non-gateway sessions
/// (e.g. WeChat adapter) to route remote tool calls to connected desktop/mobile nodes.
/// Returns true if the request was sent to a connected node.
using NodeInvokeFn = std::function<bool(const std::string& tool_call_id,
                                         const std::string& invoke_payload_json)>;
using NodeInvokeRef = std::shared_ptr<NodeInvokeFn>;

/// Create a shared node invoke function (initially a no-op that returns false).
inline NodeInvokeRef make_node_invoker() {
  return std::make_shared<NodeInvokeFn>(
      [](const std::string&, const std::string&) -> bool { return false; });
}

/// External tool router registration: allows non-gateway sessions to register
/// their ToolRouter for a specific tool_call_id so that node.invoke.result
/// can be routed back to the correct session.
class ToolRouter;
using ExternalRouterRegistry = std::shared_ptr<std::unordered_map<std::string, ToolRouter*>>;
inline ExternalRouterRegistry make_external_router_registry() {
  return std::make_shared<std::unordered_map<std::string, ToolRouter*>>();
}

/// Create a shared broadcast function (initially a no-op).
inline GatewayBroadcastRef make_gateway_broadcast() {
  return std::make_shared<GatewayBroadcastFn>([](const std::string&, const std::string&) {});
}

/// Create a shared WeChat sender (initially reports unavailable).
inline WeChatSendRef make_wechat_sender() {
  return std::make_shared<WeChatSendFn>(
      [](const std::string&, const std::string&, bool, std::string& error_message) {
        error_message = "WeChat adapter is not ready";
        return false;
      });
}

/**
 * Run gateway (WebSocket) server on port.
 * Protocol: connect.challenge -> connect RPC -> then agent.run / chat.run with {"message":"..."}.
 * If pairing_code is non-empty, only connections that send this as password in connect are accepted.
 * Config is passed by reference to allow config.set to modify it at runtime.
 * broadcast: if non-null, gateway_run will populate it with a function that
 *            pushes events to all connected operator sessions. Other components
 *            (e.g. WeChatAdapter) can call it to broadcast events.
 * Blocks until process exits.
 */
void gateway_run(int port, config::Config& config, const std::string& pairing_code = "",
                 GatewayBroadcastRef broadcast = nullptr,
                 WeChatSendRef wechat_sender = nullptr,
                 NodeInvokeRef node_invoker = nullptr,
                 ExternalRouterRegistry external_routers = nullptr);

/**
 * Generate a one-time pairing code (e.g. 6 digits). Safe to print to console.
 */
std::string gateway_generate_pairing_code();

}  // namespace net
}  // namespace hiclaw

#endif
