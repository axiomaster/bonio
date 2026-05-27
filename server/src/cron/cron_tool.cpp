#include "hiclaw/cron/cron_tool.hpp"
#include "hiclaw/cron/scheduler.hpp"
#include "hiclaw/observability/log.hpp"
#include "hiclaw/tools/tool.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#include <cstring>
#include <sstream>

namespace hiclaw {
namespace cron {

namespace {

using json = nlohmann::json;

// Global scheduler instance (set once at startup)
CronScheduler* g_scheduler = nullptr;

// Thread-local session key (set before each agent run)
thread_local std::string tl_session_key;

// --- Schedule parsing helpers ---

// Parse a duration string like "30s", "1m", "5m", "1h" to milliseconds.
// Returns 0 on failure.
int64_t parse_duration_ms(const std::string& s) {
  if (s.empty()) return 0;

  // Try to parse as plain number (treat as milliseconds)
  {
    char* end = nullptr;
    long long val = std::strtoll(s.c_str(), &end, 10);
    if (end != nullptr && *end == '\0' && val > 0) {
      return static_cast<int64_t>(val);
    }
  }

  // Parse with suffix
  char* end = nullptr;
  double val = std::strtod(s.c_str(), &end);
  if (end == nullptr || end == s.c_str() || val <= 0) return 0;

  std::string suffix(end);
  if (suffix == "s") return static_cast<int64_t>(val * 1000);
  if (suffix == "m") return static_cast<int64_t>(val * 60 * 1000);
  if (suffix == "h") return static_cast<int64_t>(val * 3600 * 1000);
  return 0;
}

// Parse the "schedule" field into schedule_type, every_ms, at_timestamp, cron_expr.
// Formats:
//   "every 1m"   -> type="every", every_ms=60000
//   "at +30m"    -> type="at", at_timestamp=now+1800000
//   "cron 0 9 * * *" -> type="cron", cron_expr="0 9 * * *"
bool parse_schedule(const std::string& schedule,
                    std::string& schedule_type,
                    int64_t& every_ms,
                    int64_t& at_timestamp,
                    std::string& cron_expr) {
  if (schedule.compare(0, 6, "every ") == 0) {
    std::string dur = schedule.substr(6);
    // trim
    while (!dur.empty() && dur.back() == ' ') dur.pop_back();
    int64_t ms = parse_duration_ms(dur);
    if (ms <= 0) return false;
    schedule_type = "every";
    every_ms = ms;
    return true;
  }
  if (schedule.compare(0, 3, "at ") == 0) {
    std::string rest = schedule.substr(3);
    while (!rest.empty() && rest.back() == ' ') rest.pop_back();
    // Support "+30m" style (offset from now)
    if (!rest.empty() && rest[0] == '+') {
      int64_t offset = parse_duration_ms(rest.substr(1));
      if (offset <= 0) return false;
      auto now_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::system_clock::now().time_since_epoch())
                        .count();
      schedule_type = "at";
      at_timestamp = now_ms + offset;
      return true;
    }
    // Support plain timestamp (ms since epoch)
    char* end = nullptr;
    long long ts = std::strtoll(rest.c_str(), &end, 10);
    if (end != nullptr && *end == '\0' && ts > 0) {
      schedule_type = "at";
      at_timestamp = static_cast<int64_t>(ts);
      return true;
    }
    return false;
  }
  if (schedule.compare(0, 5, "cron ") == 0) {
    std::string expr = schedule.substr(5);
    while (!expr.empty() && expr.back() == ' ') expr.pop_back();
    if (expr.empty()) return false;
    schedule_type = "cron";
    cron_expr = expr;
    return true;
  }
  return false;
}

// --- Tool implementations ---

types::ToolResult cron_add_impl(const std::string& args_json) {
  if (!g_scheduler) {
    return types::ToolResult{false, "", "cron scheduler not available"};
  }

  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  std::string schedule = params.contains("schedule") && params["schedule"].is_string()
                             ? params["schedule"].get<std::string>()
                             : "";
  std::string prompt = params.contains("prompt") && params["prompt"].is_string()
                           ? params["prompt"].get<std::string>()
                           : "";
  int max_count = 0;
  if (params.contains("maxCount") && params["maxCount"].is_number_integer()) {
    max_count = params["maxCount"].get<int>();
  }
  int64_t max_duration_ms = 0;
  if (params.contains("maxDuration") && params["maxDuration"].is_string()) {
    max_duration_ms = parse_duration_ms(params["maxDuration"].get<std::string>());
  }

  if (schedule.empty()) {
    return types::ToolResult{false, "", "missing 'schedule' argument"};
  }
  if (prompt.empty()) {
    return types::ToolResult{false, "", "missing 'prompt' argument"};
  }
  if (tl_session_key.empty()) {
    return types::ToolResult{false, "", "no session context for cron job"};
  }

  std::string schedule_type;
  int64_t every_ms = 0;
  int64_t at_timestamp = 0;
  std::string cron_expr;

  if (!parse_schedule(schedule, schedule_type, every_ms, at_timestamp, cron_expr)) {
    return types::ToolResult{false, "",
                             "invalid schedule format. Use: \"every 1m\", \"at +30m\", or \"cron 0 9 * * *\""};
  }

  std::string job_id = g_scheduler->add_job(
      tl_session_key, schedule_type, every_ms, at_timestamp, cron_expr,
      prompt, max_count, max_duration_ms);

  if (job_id.empty()) {
    return types::ToolResult{false, "", "failed to create cron job"};
  }

  log::info("cron_tool: created job " + job_id + " schedule=" + schedule);

  json result;
  result["jobId"] = job_id;
  result["schedule"] = schedule;
  result["type"] = schedule_type;
  result["prompt"] = prompt;
  return types::ToolResult{true, result.dump(), ""};
}

types::ToolResult cron_list_impl(const std::string& /*args_json*/) {
  if (!g_scheduler) {
    return types::ToolResult{false, "", "cron scheduler not available"};
  }

  auto jobs = g_scheduler->list_jobs();

  json arr = json::array();
  for (const auto& job : jobs) {
    json j;
    j["id"] = job.id;
    j["scheduleType"] = job.schedule_type;
    if (job.schedule_type == "every") {
      j["everyMs"] = job.every_ms;
    } else if (job.schedule_type == "at") {
      j["atTimestamp"] = job.at_timestamp;
    } else if (job.schedule_type == "cron") {
      j["cronExpr"] = job.cron_expr;
    }
    j["prompt"] = job.prompt;
    j["maxCount"] = job.max_count;
    j["maxDurationMs"] = job.max_duration_ms;
    j["runCount"] = job.run_count;
    j["enabled"] = job.enabled;
    arr.push_back(std::move(j));
  }

  json result;
  result["jobs"] = arr;
  result["count"] = arr.size();
  return types::ToolResult{true, result.dump(), ""};
}

types::ToolResult cron_remove_impl(const std::string& args_json) {
  if (!g_scheduler) {
    return types::ToolResult{false, "", "cron scheduler not available"};
  }

  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  std::string job_id = params.contains("jobId") && params["jobId"].is_string()
                           ? params["jobId"].get<std::string>()
                           : "";
  if (job_id.empty()) {
    return types::ToolResult{false, "", "missing 'jobId' argument"};
  }

  bool removed = g_scheduler->remove_job(job_id);
  if (!removed) {
    return types::ToolResult{false, "", "job not found: " + job_id};
  }

  log::info("cron_tool: removed job " + job_id);
  json result;
  result["removed"] = true;
  result["jobId"] = job_id;
  return types::ToolResult{true, result.dump(), ""};
}

types::ToolResult cron_runs_impl(const std::string& args_json) {
  if (!g_scheduler) {
    return types::ToolResult{false, "", "cron scheduler not available"};
  }

  json params;
  try {
    params = args_json.empty() ? json::object() : json::parse(args_json);
  } catch (const json::parse_error&) {
    return types::ToolResult{false, "", "invalid JSON arguments"};
  }

  std::string job_id = params.contains("jobId") && params["jobId"].is_string()
                           ? params["jobId"].get<std::string>()
                           : "";
  if (job_id.empty()) {
    return types::ToolResult{false, "", "missing 'jobId' argument"};
  }

  auto runs = g_scheduler->get_runs(job_id);

  json arr = json::array();
  for (const auto& run : runs) {
    json r;
    r["startedAt"] = run.started_at;
    r["completedAt"] = run.completed_at;
    r["success"] = run.success;
    r["resultSummary"] = run.result_summary;
    arr.push_back(std::move(r));
  }

  json result;
  result["jobId"] = job_id;
  result["runs"] = arr;
  result["count"] = arr.size();
  return types::ToolResult{true, result.dump(), ""};
}

}  // namespace

void set_cron_scheduler(CronScheduler* scheduler) {
  g_scheduler = scheduler;
}

void set_session_key(const std::string& key) {
  tl_session_key = key;
}

void register_cron_tools() {
  tools::register_tool("cron.add", cron_add_impl);
  tools::register_tool("cron.list", cron_list_impl);
  tools::register_tool("cron.remove", cron_remove_impl);
  tools::register_tool("cron.runs", cron_runs_impl);
}

}  // namespace cron
}  // namespace hiclaw
