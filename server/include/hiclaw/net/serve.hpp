#ifndef HICLAW_NET_SERVE_HPP
#define HICLAW_NET_SERVE_HPP

#include "hiclaw/config/config.hpp"
#include <string>

namespace hiclaw {
namespace net {

/**
 * Run HTTP server on port. One request at a time.
 * POST /run with JSON {"prompt":"..."} -> run agent, return {"content":"..."} or {"error":"..."}.
 * Blocks until process exits (no graceful shutdown in this minimal version).
 */
void serve(int port, const config::Config& config);

}  // namespace net
}  // namespace hiclaw

#endif
