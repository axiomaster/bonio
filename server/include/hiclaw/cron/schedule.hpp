#ifndef HICLAW_CRON_SCHEDULE_HPP
#define HICLAW_CRON_SCHEDULE_HPP

#include <ctime>
#include <string>

namespace hiclaw {
namespace cron {

/**
 * Parse 5-field cron expression (min hour day month dow).
 * Supports: * , N , N-M , star-slash-M (e.g. every 5 minutes).
 * Returns next run time (UTC) after from, or 0 on error.
 */
std::time_t next_run_after(const std::string& expr, std::time_t from);

/// Validate expression; returns true if valid.
bool validate_expr(const std::string& expr);

}  // namespace cron
}  // namespace hiclaw

#endif
