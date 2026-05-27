#ifndef HICLAW_CRON_CRON_TOOL_HPP
#define HICLAW_CRON_CRON_TOOL_HPP

#include <string>

namespace hiclaw {
namespace cron {

class CronScheduler;

/// Set the global CronScheduler instance (called once at startup).
void set_cron_scheduler(CronScheduler* scheduler);

/// Set the session_key for the current thread (called before each agent run).
void set_session_key(const std::string& key);

/// Register cron tools (cron.add, cron.list, cron.remove, cron.runs) with the tool registry.
void register_cron_tools();

}  // namespace cron
}  // namespace hiclaw

#endif  // HICLAW_CRON_CRON_TOOL_HPP
