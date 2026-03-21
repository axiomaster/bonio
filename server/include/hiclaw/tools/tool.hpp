#ifndef HICLAW_TOOLS_TOOL_HPP
#define HICLAW_TOOLS_TOOL_HPP

#include "hiclaw/types/message.hpp"
#include <functional>
#include <string>
#include <vector>

namespace hiclaw {
namespace tools {

using ToolResult = types::ToolResult;

/// Tool registry: name -> executor. args_json is the raw "arguments" string from the model.
using ToolExecutor = std::function<ToolResult(const std::string& args_json)>;

void register_tool(const std::string& name, ToolExecutor exec);
ToolResult run_tool(const std::string& name, const std::string& args_json);
std::vector<std::string> list_tool_names();

/// Returns true if the tool should be executed remotely on the client device
/// (e.g. screen.capture, camera.snap) rather than locally on the server.
bool is_remote_tool(const std::string& name);

/// Built-in tools (shell, file_read, file_write) are registered on first use.
void register_builtin_tools();

}  // namespace tools
}  // namespace hiclaw

#endif
