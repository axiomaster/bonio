#ifndef HICLAW_TOOLS_MEMO_TOOL_HPP
#define HICLAW_TOOLS_MEMO_TOOL_HPP

#include "hiclaw/types/message.hpp"
#include <string>

namespace hiclaw {
namespace tools {

types::ToolResult memo_save(const std::string& args_json);
// include_images: gateway RPC responses carry coverImage base64 for the client
// UI; LLM tool calls must pass false — base64 payloads explode the context
// window (HTTP 400 from the provider on the next round).
types::ToolResult memo_list(const std::string& args_json, bool include_images = true);
types::ToolResult memo_get(const std::string& args_json, bool include_images = true);
types::ToolResult memo_delete(const std::string& args_json);

}  // namespace tools
}  // namespace hiclaw

#endif
