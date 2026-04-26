#ifndef HICLAW_NET_GATEWAY_HPP
#define HICLAW_NET_GATEWAY_HPP

#include "hiclaw/config/config.hpp"
#include <functional>
#include <memory>
#include <string>

namespace hiclaw {
namespace net {

/// Shared broadcast function: gateway_run sets it, other components call it.
/// Initially a no-op; becomes live once the WebSocket server starts accepting connections.
using GatewayBroadcastFn = std::function<void(const std::string& event_name,
                                               const std::string& payload_json)>;
using GatewayBroadcastRef = std::shared_ptr<GatewayBroadcastFn>;

/// Create a shared broadcast function (initially a no-op).
inline GatewayBroadcastRef make_gateway_broadcast() {
  return std::make_shared<GatewayBroadcastFn>([](const std::string&, const std::string&) {});
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
                 GatewayBroadcastRef broadcast = nullptr);

/**
 * Generate a one-time pairing code (e.g. 6 digits). Safe to print to console.
 */
std::string gateway_generate_pairing_code();

}  // namespace net
}  // namespace hiclaw

#endif
