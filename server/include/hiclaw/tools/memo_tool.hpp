#ifndef HICLAW_TOOLS_MEMO_TOOL_HPP
#define HICLAW_TOOLS_MEMO_TOOL_HPP

#include "hiclaw/types/message.hpp"
#include <string>

namespace hiclaw {
namespace tools {

types::ToolResult memo_save(const std::string& args_json);
types::ToolResult memo_list(const std::string& args_json);

}  // namespace tools
}  // namespace hiclaw

#endif
