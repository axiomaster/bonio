#ifndef HICLAW_NET_ASYNC_AGENT_HPP
#define HICLAW_NET_ASYNC_AGENT_HPP

#include "hiclaw/config/config.hpp"
#include "hiclaw/net/tool_router.hpp"
#include "hiclaw/session/store.hpp"
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

namespace hiclaw {
namespace net {

// Event callback type: event_name, payload_json
using EventCallback = std::function<void(const std::string&, const std::string&)>;

// Async task state
struct AsyncTask {
  std::string run_id;
  std::string session_key;
  std::string message;
  std::atomic<bool> aborted{false};
  std::thread worker;

  ~AsyncTask() {
    // Detach thread if still joinable to avoid std::terminate
    if (worker.joinable()) {
      worker.detach();
    }
  }
};

// Async Agent Manager
class AsyncAgentManager {
public:
  AsyncAgentManager(const config::Config& config, EventCallback callback,
                    std::shared_ptr<session::SessionStore> session_store = nullptr,
                    std::shared_ptr<ToolRouter> tool_router = nullptr);
  ~AsyncAgentManager();

  // Disable copy
  AsyncAgentManager(const AsyncAgentManager&) = delete;
  AsyncAgentManager& operator=(const AsyncAgentManager&) = delete;

  // Start new async task, returns run_id
  std::string start_task(const std::string& session_key, const std::string& message);

  // Abort task
  bool abort_task(const std::string& run_id);

  // Check if task exists
  bool has_task(const std::string& run_id) const;

private:
  void run_task(std::shared_ptr<AsyncTask> task);
  void send_event(const std::string& event_name, const std::string& payload_json);

  const config::Config& config_;
  EventCallback event_callback_;
  std::shared_ptr<session::SessionStore> session_store_;
  std::shared_ptr<ToolRouter> tool_router_;

  mutable std::mutex tasks_mutex_;
  std::unordered_map<std::string, std::shared_ptr<AsyncTask>> tasks_;
};

}  // namespace net
}  // namespace hiclaw

#endif
