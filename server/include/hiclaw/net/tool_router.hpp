#ifndef HICLAW_NET_TOOL_ROUTER_HPP
#define HICLAW_NET_TOOL_ROUTER_HPP

#include <string>
#include <unordered_map>
#include <mutex>
#include <future>
#include <memory>

namespace hiclaw {
namespace net {

/**
 * Result of a tool invocation returned by the client.
 */
struct ToolResult {
  bool success = false;
  std::string output;    // JSON or text output
  std::string error;     // Error message if !success
};

/**
 * ToolRouter manages pending tool calls and their results.
 * Used to coordinate between the agent (which initiates tool calls)
 * and the gateway (which receives results from clients).
 */
class ToolRouter {
public:
  ToolRouter() = default;
  ~ToolRouter() = default;

  // Disable copy
  ToolRouter(const ToolRouter&) = delete;
  ToolRouter& operator=(const ToolRouter&) = delete;

  /**
   * Register a pending tool call and get a future for its result.
   * Called by the agent when a tool call is initiated.
   *
   * @param tool_call_id The unique ID of the tool call
   * @return A future that will be fulfilled when the result arrives
   */
  std::future<ToolResult> register_tool_call(const std::string& tool_call_id);

  /**
   * Complete a pending tool call with a result.
   * Called by the gateway when a node.invoke.result is received.
   *
   * @param tool_call_id The unique ID of the tool call
   * @param result The result from the client
   * @return true if the tool call was found and completed, false otherwise
   */
  bool complete_tool_call(const std::string& tool_call_id, const ToolResult& result);

  /**
   * Check if a tool call is pending.
   */
  bool has_pending(const std::string& tool_call_id) const;

  /**
   * Cancel all pending tool calls (e.g., on session close).
   */
  void cancel_all();

  /**
   * Get the number of pending tool calls.
   */
  size_t pending_count() const;

private:
  mutable std::mutex mutex_;
  std::unordered_map<std::string, std::promise<ToolResult>> pending_;
};

}  // namespace net
}  // namespace hiclaw

#endif
