#ifndef HICLAW_AGENT_AGENT_HPP
#define HICLAW_AGENT_AGENT_HPP

#include "hiclaw/config/config.hpp"
#include "hiclaw/types/message.hpp"
#include <atomic>
#include <functional>
#include <string>
#include <vector>

namespace hiclaw {
namespace agent {

struct RunResult {
  bool ok = false;
  std::string content;
  std::string error;
};

/**
 * Single-turn run: uses config.models + default_model to resolve provider (Ollama or OpenAI-compatible), then runs agent.
 */
RunResult run(const config::Config& config,
              const std::string& user_prompt,
              double temperature = 0.7);

/**
 * Stream callback type: called for each text delta received from the LLM.
 */
using TextStreamCallback = std::function<void(const std::string& /*delta_text*/)>;

/**
 * Tool call event for streaming tool_calls parsing.
 * OpenAI streaming sends tool_calls incrementally; this event signals
 * when a tool call is complete (all argument fragments accumulated).
 */
struct ToolCallEvent {
  std::string id;           // tool call ID (e.g., "call_abc123")
  std::string name;         // function name
  std::string arguments;    // complete arguments JSON string
  bool is_complete = false; // true when all chunks received
};

/**
 * Tool call callback type: called when a complete tool call is parsed.
 */
using ToolCallCallback = std::function<void(const ToolCallEvent&)>;

/**
 * Streaming version of run: invokes callback for each text chunk received.
 * The full accumulated content is returned in RunResult.content on success.
 * Optionally receives tool_call events when the LLM requests function calls.
 */
RunResult run_streaming(const config::Config& config,
                        const std::string& user_prompt,
                        double temperature,
                        TextStreamCallback text_callback,
                        ToolCallCallback tool_callback = nullptr);

/**
 * Optional executor for remote (device-side) tools. Called instead of tools::run_tool()
 * when tools::is_remote_tool() returns true. The executor should send the tool call
 * to the client and block until the result arrives (or timeout).
 */
using RemoteToolExecutor = std::function<types::ToolResult(
    const std::string& tool_call_id,
    const std::string& tool_name,
    const std::string& args_json)>;

/**
 * Multi-turn streaming run with conversation history and tool execution loop.
 * Loads prior messages, appends the new user message, calls the LLM with streaming,
 * and executes tool calls locally (up to max_tool_rounds iterations).
 * Remote tools (device-side) are dispatched via remote_executor if provided.
 * An optional aborted flag can be checked between rounds to support cancellation.
 */
RunResult run_streaming_with_history(
    const config::Config& config,
    const std::vector<types::Message>& history,
    const std::string& user_prompt,
    double temperature,
    TextStreamCallback text_callback,
    ToolCallCallback tool_callback = nullptr,
    const std::atomic<bool>* aborted = nullptr,
    int max_tool_rounds = 3,
    RemoteToolExecutor remote_executor = nullptr);

}  // namespace agent
}  // namespace hiclaw

#endif
