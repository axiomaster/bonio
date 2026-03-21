#ifndef HICLAW_TYPES_MESSAGE_HPP
#define HICLAW_TYPES_MESSAGE_HPP

#include <string>
#include <vector>

namespace hiclaw {
namespace types {

constexpr const char* ROLE_SYSTEM = "system";
constexpr const char* ROLE_USER = "user";
constexpr const char* ROLE_ASSISTANT = "assistant";
constexpr const char* ROLE_TOOL = "tool";

struct Message {
  std::string role;
  std::string content;
};

struct ToolCall {
  std::string id;
  std::string name;
  std::string arguments;
};

struct ToolResult {
  bool success = true;
  std::string output;
  std::string error;
};

inline Message system_message(const std::string& content) {
  return {std::string(ROLE_SYSTEM), content};
}
inline Message user_message(const std::string& content) {
  return {std::string(ROLE_USER), content};
}
inline Message assistant_message(const std::string& content) {
  return {std::string(ROLE_ASSISTANT), content};
}
inline Message tool_message(const std::string& content) {
  return {std::string(ROLE_TOOL), content};
}

}  // namespace types
}  // namespace hiclaw

#endif
