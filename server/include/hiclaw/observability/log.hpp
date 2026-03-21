#ifndef HICLAW_OBSERVABILITY_LOG_HPP
#define HICLAW_OBSERVABILITY_LOG_HPP

#include <string>

namespace hiclaw {
namespace log {

enum class Level { Off = 0, Error = 1, Warn = 2, Info = 3, Debug = 4, Trace = 5 };

/// Set level from string: "off", "error", "warn", "info", "debug", "trace". Or from env hiclaw_log.
void set_level(const std::string& name);
void set_level(Level l);
Level get_level();

/// Set workspace root; logs will be written to workspace/logs/ (created if needed). Call after config load.
void set_log_dir(const std::string& workspace_dir);

void error(const std::string& msg);
void warn(const std::string& msg);
void info(const std::string& msg);
void debug(const std::string& msg);
void trace(const std::string& msg);

}  // namespace log
}  // namespace hiclaw

#endif
