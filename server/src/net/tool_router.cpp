#include "hiclaw/net/tool_router.hpp"

namespace hiclaw {
namespace net {

std::future<ToolResult> ToolRouter::register_tool_call(const std::string& tool_call_id) {
  std::lock_guard<std::mutex> lock(mutex_);

  auto& promise = pending_[tool_call_id];
  return promise.get_future();
}

bool ToolRouter::complete_tool_call(const std::string& tool_call_id, const ToolResult& result) {
  std::lock_guard<std::mutex> lock(mutex_);

  auto it = pending_.find(tool_call_id);
  if (it == pending_.end()) {
    return false;  // Tool call not found or already completed
  }

  it->second.set_value(result);
  pending_.erase(it);
  return true;
}

bool ToolRouter::has_pending(const std::string& tool_call_id) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return pending_.find(tool_call_id) != pending_.end();
}

void ToolRouter::cancel_all() {
  std::lock_guard<std::mutex> lock(mutex_);

  // Set an empty result for all pending calls to unblock waiting threads
  for (auto& kv : pending_) {
    try {
      kv.second.set_value(ToolResult{false, "", "cancelled"});
    } catch (const std::future_error&) {
      // Promise already satisfied, ignore
    }
  }
  pending_.clear();
}

size_t ToolRouter::pending_count() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return pending_.size();
}

}  // namespace net
}  // namespace hiclaw
