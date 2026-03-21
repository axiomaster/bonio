#ifndef HICLAW_NET_GATEWAY_HPP
#define HICLAW_NET_GATEWAY_HPP

#include "hiclaw/config/config.hpp"
#include <string>

namespace hiclaw {
namespace net {

/**
 * Run gateway (WebSocket) server on port.
 * Protocol: connect.challenge -> connect RPC -> then agent.run / chat.run with {"message":"..."}.
 * If pairing_code is non-empty, only connections that send this as password in connect are accepted.
 * Config is passed by reference to allow config.set to modify it at runtime.
 * Blocks until process exits.
 */
void gateway_run(int port, config::Config& config, const std::string& pairing_code = "");

/**
 * Generate a one-time pairing code (e.g. 6 digits). Safe to print to console.
 */
std::string gateway_generate_pairing_code();

}  // namespace net
}  // namespace hiclaw

#endif
