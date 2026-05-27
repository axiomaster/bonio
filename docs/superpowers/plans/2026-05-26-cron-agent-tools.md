# Cron Agent Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the HiClaw AI agent to create, list, remove, and inspect scheduled tasks through natural conversation, with an internal scheduler that dispatches tasks via the existing AsyncAgentManager pipeline.

**Architecture:** A `CronScheduler` class runs a background thread inside the Gateway process, checking for due jobs every second and dispatching them via `AsyncAgentManager.start_task()`. Cron tools (`cron.add/list/remove/runs`) are registered in the global tool registry and use a global `CronScheduler*` pointer (set during gateway startup). Jobs are persisted to `<config_dir>/cron/jobs.json`.

**Tech Stack:** C++17, nlohmann/json, std::thread, existing cron::Schedule parser.

---

### Task 1: CronScheduler Header + Data Model

**Files:**
- Create: `server/include/hiclaw/cron/scheduler.hpp`

- [ ] **Step 1: Create the CronScheduler header**

```cpp
// server/include/hiclaw/cron/scheduler.hpp
#pragma once

#include <string>
#include <vector>
#include <mutex>
#include <thread>
#include <atomic>
#include <cstdint>

namespace hiclaw {
namespace net {

class AsyncAgentManager;

}  // namespace net

namespace cron {

struct RunRecord {
  int64_t started_at = 0;
  int64_t completed_at = 0;
  bool success = false;
  std::string result_summary;  // First 200 chars
};

struct CronJob {
  // Identity
  std::string id;
  std::string session_key;

  // Schedule
  std::string schedule_type;  // "every" | "at" | "cron"
  int every_ms = 0;           // for "every": interval in ms
  int64_t at_timestamp = 0;   // for "at": Unix ms (one-shot)
  std::string cron_expr;      // for "cron": 5-field expression

  // Task
  std::string prompt;

  // Stop conditions
  int max_count = 0;          // 0 = unlimited
  int max_duration_ms = 0;    // 0 = unlimited

  // Runtime state
  int run_count = 0;
  int64_t created_at = 0;
  int64_t next_run = 0;       // Unix ms
  bool enabled = true;

  // Run history (last 20)
  std::vector<RunRecord> recent_runs;
};

class CronScheduler {
public:
  explicit CronScheduler(const std::string& config_dir);

  void start(std::shared_ptr<net::AsyncAgentManager> agent_manager);
  void stop();

  // CRUD (thread-safe)
  std::string add_job(const std::string& session_key,
                      const std::string& schedule_type,
                      int every_ms, int64_t at_timestamp,
                      const std::string& cron_expr,
                      const std::string& prompt,
                      int max_count, int max_duration_ms);
  bool remove_job(const std::string& job_id);
  std::vector<CronJob> list_jobs() const;
  std::vector<RunRecord> get_runs(const std::string& job_id) const;

private:
  void scheduler_loop();
  void compute_next_run(CronJob& job);
  void save_jobs();
  void load_jobs();
  std::string jobs_path() const;

  std::string config_dir_;
  std::shared_ptr<net::AsyncAgentManager> agent_manager_;
  std::vector<CronJob> jobs_;
  mutable std::mutex mutex_;
  std::thread thread_;
  std::atomic<bool> running_{false};
};

}  // namespace cron
}  // namespace hiclaw
```

- [ ] **Step 2: Commit**

```bash
git add server/include/hiclaw/cron/scheduler.hpp
git commit -m "feat: add CronScheduler header and data model"
```

---

### Task 2: CronScheduler Implementation

**Files:**
- Create: `server/src/cron/scheduler.cpp`

- [ ] **Step 1: Implement CronScheduler**

```cpp
// server/src/cron/scheduler.cpp
#include "hiclaw/cron/scheduler.hpp"
#include "hiclaw/net/async_agent.hpp"
#include "hiclaw/cron/schedule.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <random>
#include <algorithm>

namespace hiclaw {
namespace cron {

namespace {

using json = nlohmann::json;
namespace fs = std::filesystem;

std::string generate_id() {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<uint32_t> dist(0, 0xFFFFFF);
  std::ostringstream oss;
  oss << "cron_" << std::hex << dist(gen);
  return oss.str();
}

int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

std::string schedule_type_str(const std::string& type) {
  if (type == "every") return "every";
  if (type == "at") return "at";
  if (type == "cron") return "cron";
  return "unknown";
}

}  // namespace

CronScheduler::CronScheduler(const std::string& config_dir)
    : config_dir_(config_dir) {
  load_jobs();
  log::info("cron: scheduler created with " + std::to_string(jobs_.size()) + " jobs");
}

void CronScheduler::start(std::shared_ptr<net::AsyncAgentManager> agent_manager) {
  agent_manager_ = std::move(agent_manager);
  running_ = true;
  thread_ = std::thread(&CronScheduler::scheduler_loop, this);
  log::info("cron: scheduler thread started");
}

void CronScheduler::stop() {
  running_ = false;
  if (thread_.joinable()) {
    thread_.join();
  }
  log::info("cron: scheduler stopped");
}

std::string CronScheduler::add_job(const std::string& session_key,
                                    const std::string& schedule_type,
                                    int every_ms, int64_t at_timestamp,
                                    const std::string& cron_expr,
                                    const std::string& prompt,
                                    int max_count, int max_duration_ms) {
  std::lock_guard<std::mutex> lock(mutex_);

  CronJob job;
  job.id = generate_id();
  job.session_key = session_key;
  job.schedule_type = schedule_type;
  job.every_ms = every_ms;
  job.at_timestamp = at_timestamp;
  job.cron_expr = cron_expr;
  job.prompt = prompt;
  job.max_count = max_count;
  job.max_duration_ms = max_duration_ms;
  job.created_at = now_ms();
  job.run_count = 0;
  job.enabled = true;

  compute_next_run(job);
  if (job.next_run == 0) {
    log::warn("cron: failed to compute next_run for job");
    return "";
  }

  jobs_.push_back(job);
  save_jobs();

  log::info("cron: added job " + job.id +
            " schedule=" + job.schedule_type +
            " next_run=" + std::to_string(job.next_run));

  return job.id;
}

bool CronScheduler::remove_job(const std::string& job_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto it = jobs_.begin(); it != jobs_.end(); ++it) {
    if (it->id == job_id) {
      log::info("cron: removed job " + job_id);
      jobs_.erase(it);
      save_jobs();
      return true;
    }
  }
  return false;
}

std::vector<CronJob> CronScheduler::list_jobs() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return jobs_;
}

std::vector<RunRecord> CronScheduler::get_runs(const std::string& job_id) const {
  std::lock_guard<std::mutex> lock(mutex_);
  for (const auto& job : jobs_) {
    if (job.id == job_id) {
      return job.recent_runs;
    }
  }
  return {};
}

void CronScheduler::scheduler_loop() {
  while (running_) {
    auto loop_start = std::chrono::steady_clock::now();
    int64_t now = now_ms();

    {
      std::lock_guard<std::mutex> lock(mutex_);
      for (auto& job : jobs_) {
        if (!job.enabled) continue;
        if (job.next_run == 0 || now < job.next_run) continue;

        // Check stop conditions before dispatching
        if (job.max_count > 0 && job.run_count >= job.max_count) {
          job.enabled = false;
          log::info("cron: job " + job.id + " reached max_count=" +
                    std::to_string(job.max_count));
          continue;
        }
        if (job.max_duration_ms > 0 &&
            (now - job.created_at) >= job.max_duration_ms) {
          job.enabled = false;
          log::info("cron: job " + job.id + " reached max_duration");
          continue;
        }

        // Dispatch
        log::info("cron: dispatching job " + job.id +
                  " run #" + std::to_string(job.run_count + 1));

        RunRecord rec;
        rec.started_at = now;
        rec.success = false;

        if (agent_manager_) {
          try {
            std::string run_id = agent_manager_->start_task(
                job.session_key, job.prompt);
            rec.success = true;
            rec.result_summary = "started run " + run_id;
            log::info("cron: dispatched job " + job.id + " as run " + run_id);
          } catch (const std::exception& e) {
            rec.result_summary = std::string("error: ") + e.what();
            log::warn("cron: failed to dispatch job " + job.id + ": " + e.what());
          }
        } else {
          rec.result_summary = "no agent_manager";
          log::warn("cron: no agent_manager, skipping job " + job.id);
        }

        rec.completed_at = now_ms();
        job.recent_runs.push_back(std::move(rec));
        if (job.recent_runs.size() > 20) {
          job.recent_runs.erase(job.recent_runs.begin());
        }

        job.run_count++;

        // For "at" type (one-shot), disable after first run
        if (job.schedule_type == "at") {
          job.enabled = false;
        }

        compute_next_run(job);
      }
      save_jobs();
    }

    // Sleep remainder of 1 second
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - loop_start);
    auto sleep_ms = std::max(0LL, 1000LL - elapsed.count());
    if (sleep_ms > 0 && running_) {
      std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));
    }
  }
}

void CronScheduler::compute_next_run(CronJob& job) {
  int64_t now = now_ms();
  if (job.schedule_type == "every") {
    if (job.every_ms > 0) {
      // If just dispatched (next_run was in the past), add interval to now
      job.next_run = (job.next_run > 0 && job.next_run <= now)
                          ? now + job.every_ms
                          : now + job.every_ms;
    }
  } else if (job.schedule_type == "at") {
    job.next_run = job.at_timestamp;
  } else if (job.schedule_type == "cron") {
    std::time_t from = static_cast<std::time_t>(now / 1000);
    std::time_t next = next_run_after(job.cron_expr, from);
    if (next > 0) {
      job.next_run = static_cast<int64_t>(next) * 1000;
    } else {
      job.next_run = 0;
    }
  }
}

std::string CronScheduler::jobs_path() const {
  return (fs::path(config_dir_) / "cron" / "jobs.json").string();
}

void CronScheduler::save_jobs() {
  std::string dir = (fs::path(config_dir_) / "cron").string();
  std::error_code ec;
  fs::create_directories(dir, ec);
  if (ec) {
    log::error("cron: failed to create dir " + dir);
    return;
  }

  json arr = json::array();
  for (const auto& job : jobs_) {
    json j;
    j["id"] = job.id;
    j["sessionKey"] = job.session_key;
    j["scheduleType"] = job.schedule_type;
    j["everyMs"] = job.every_ms;
    j["atTimestamp"] = job.at_timestamp;
    j["cronExpr"] = job.cron_expr;
    j["prompt"] = job.prompt;
    j["maxCount"] = job.max_count;
    j["maxDurationMs"] = job.max_duration_ms;
    j["runCount"] = job.run_count;
    j["createdAt"] = job.created_at;
    j["nextRun"] = job.next_run;
    j["enabled"] = job.enabled;

    json runs = json::array();
    for (const auto& r : job.recent_runs) {
      runs.push_back({
          {"startedAt", r.started_at},
          {"completedAt", r.completed_at},
          {"success", r.success},
          {"resultSummary", r.result_summary}
      });
    }
    j["recentRuns"] = runs;
    arr.push_back(std::move(j));
  }

  std::string path = jobs_path();
  std::ofstream f(path);
  if (f) {
    f << arr.dump(2);
  } else {
    log::error("cron: failed to save jobs to " + path);
  }
}

void CronScheduler::load_jobs() {
  std::string path = jobs_path();
  std::ifstream f(path);
  if (!f) return;

  try {
    json arr = json::parse(f);
    if (!arr.is_array()) return;

    for (const auto& el : arr) {
      if (!el.is_object()) continue;
      CronJob job;
      job.id = el.value("id", "");
      if (job.id.empty()) continue;
      job.session_key = el.value("sessionKey", "");
      job.schedule_type = el.value("scheduleType", "");
      job.every_ms = el.value("everyMs", 0);
      job.at_timestamp = el.value("atTimestamp", int64_t(0));
      job.cron_expr = el.value("cronExpr", "");
      job.prompt = el.value("prompt", "");
      job.max_count = el.value("maxCount", 0);
      job.max_duration_ms = el.value("maxDurationMs", 0);
      job.run_count = el.value("runCount", 0);
      job.created_at = el.value("createdAt", int64_t(0));
      job.next_run = el.value("nextRun", int64_t(0));
      job.enabled = el.value("enabled", true);

      if (el.contains("recentRuns") && el["recentRuns"].is_array()) {
        for (const auto& r : el["recentRuns"]) {
          RunRecord rec;
          rec.started_at = r.value("startedAt", int64_t(0));
          rec.completed_at = r.value("completedAt", int64_t(0));
          rec.success = r.value("success", false);
          rec.result_summary = r.value("resultSummary", "");
          job.recent_runs.push_back(std::move(rec));
        }
      }

      // Recompute next_run for enabled recurring jobs
      if (job.enabled && job.schedule_type != "at") {
        compute_next_run(job);
      }

      jobs_.push_back(std::move(job));
    }
    log::info("cron: loaded " + std::to_string(jobs_.size()) + " jobs from " + path);
  } catch (const json::parse_error& e) {
    log::warn("cron: failed to parse jobs: " + std::string(e.what()));
  }
}

}  // namespace cron
}  // namespace hiclaw
```

- [ ] **Step 2: Update CMakeLists.txt to include scheduler.cpp**

Add `src/cron/scheduler.cpp` to the source list in `server/CMakeLists.txt` alongside the existing `src/cron/schedule.cpp` and `src/cron/store.cpp`.

- [ ] **Step 3: Build to verify compilation**

Run: `cd server && scripts\build-win-amd64.bat`
Expected: Build OK

- [ ] **Step 4: Commit**

```bash
git add server/src/cron/scheduler.cpp server/include/hiclaw/cron/scheduler.hpp
git commit -m "feat: implement CronScheduler with scheduler loop and job persistence"
```

---

### Task 3: Cron Tool Definitions + Registration

**Files:**
- Create: `server/include/hiclaw/cron/cron_tool.hpp`
- Create: `server/src/cron/cron_tool.cpp`
- Modify: `server/src/tools/tool.cpp:456-458` — register cron tools
- Modify: `server/src/agent/agent.cpp:122-161` — add cron tool definitions

- [ ] **Step 1: Create cron_tool.hpp**

```cpp
// server/include/hiclaw/cron/cron_tool.hpp
#pragma once

#include "hiclaw/tools/tool.hpp"
#include <memory>

namespace hiclaw {
namespace cron {

class CronScheduler;

/// Set the global CronScheduler instance (called once during gateway startup).
void set_cron_scheduler(CronScheduler* scheduler);

/// Register cron tools (cron.add, cron.list, cron.remove, cron.runs).
void register_cron_tools();

}  // namespace cron
}  // namespace hiclaw
```

- [ ] **Step 2: Create cron_tool.cpp with schedule parsing and tool implementations**

```cpp
// server/src/cron/cron_tool.cpp
#include "hiclaw/cron/cron_tool.hpp"
#include "hiclaw/cron/scheduler.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <chrono>

namespace hiclaw {
namespace cron {

namespace {

using json = nlohmann::json;

CronScheduler* g_scheduler = nullptr;

int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::system_clock::now().time_since_epoch()).count();
}

// Parse duration string like "30s", "1m", "5m", "1h" to milliseconds.
// Returns 0 on parse failure.
int parse_duration_ms(const std::string& s) {
  if (s.empty()) return 0;
  try {
    double val = std::stod(s);
    if (s.find('h') != std::string::npos) return static_cast<int>(val * 3600000);
    if (s.find('m') != std::string::npos) return static_cast<int>(val * 60000);
    if (s.find('s') != std::string::npos) return static_cast<int>(val * 1000);
    return static_cast<int>(val * 1000);  // default: seconds
  } catch (...) {
    return 0;
  }
}

// Parse schedule string into type + params.
// "every 1m" → ("every", 60000)
// "at +30m"  → ("at", now+1800000)
// "cron 0 9 * * *" → ("cron", ...)
bool parse_schedule(const std::string& schedule,
                    std::string& out_type, int& out_every_ms,
                    int64_t& out_at_ts, std::string& out_cron_expr) {
  if (schedule.rfind("every ", 0) == 0) {
    out_type = "every";
    std::string dur = schedule.substr(6);
    // Trim
    while (!dur.empty() && dur.back() == ' ') dur.pop_back();
    out_every_ms = parse_duration_ms(dur);
    return out_every_ms > 0;
  }
  if (schedule.rfind("at ", 0) == 0) {
    out_type = "at";
    std::string offset = schedule.substr(3);
    while (!offset.empty() && offset.back() == ' ') offset.pop_back();
    int ms = 0;
    if (offset[0] == '+') {
      ms = parse_duration_ms(offset.substr(1));
    } else {
      ms = parse_duration_ms(offset);
    }
    if (ms <= 0) return false;
    out_at_ts = now_ms() + ms;
    return true;
  }
  if (schedule.rfind("cron ", 0) == 0) {
    out_type = "cron";
    out_cron_expr = schedule.substr(5);
    while (!out_cron_expr.empty() && out_cron_expr.front() == ' ')
      out_cron_expr.erase(out_cron_expr.begin());
    return !out_cron_expr.empty();
  }
  return false;
}

}  // namespace

void set_cron_scheduler(CronScheduler* scheduler) {
  g_scheduler = scheduler;
}

// --- Tool implementations ---

static types::ToolResult cron_add_impl(const std::string& args_json) {
  if (!g_scheduler) return types::ToolResult{false, "", "cron scheduler not available"};

  json params;
  try {
    params = json::parse(args_json);
  } catch (...) {
    return types::ToolResult{false, "", "invalid JSON"};
  }

  std::string schedule = params.value("schedule", "");
  std::string prompt = params.value("prompt", "");
  int max_count = params.value("maxCount", 0);
  std::string max_dur_str = params.value("maxDuration", "");
  int max_duration_ms = max_dur_str.empty() ? 0 : parse_duration_ms(max_dur_str);

  if (schedule.empty() || prompt.empty()) {
    return types::ToolResult{false, "", "schedule and prompt are required"};
  }

  std::string type, cron_expr;
  int every_ms = 0;
  int64_t at_ts = 0;
  if (!parse_schedule(schedule, type, every_ms, at_ts, cron_expr)) {
    return types::ToolResult{false, "",
        "invalid schedule format. Use: 'every <dur>', 'at <offset>', 'cron <expr>'"};
  }

  // session_key is passed via the args by the agent loop
  std::string session_key = params.value("_sessionKey", "main");

  std::string job_id = g_scheduler->add_job(
      session_key, type, every_ms, at_ts, cron_expr,
      prompt, max_count, max_duration_ms);

  if (job_id.empty()) {
    return types::ToolResult{false, "", "failed to create cron job"};
  }

  json result;
  result["jobId"] = job_id;
  result["schedule"] = schedule;
  result["prompt"] = prompt;
  if (max_count > 0) result["maxCount"] = max_count;
  return types::ToolResult{true, result.dump(), ""};
}

static types::ToolResult cron_list_impl(const std::string& /*args_json*/) {
  if (!g_scheduler) return types::ToolResult{false, "", "cron scheduler not available"};

  auto jobs = g_scheduler->list_jobs();
  json arr = json::array();
  for (const auto& job : jobs) {
    json j;
    j["id"] = job.id;
    j["scheduleType"] = job.schedule_type;
    j["prompt"] = job.prompt;
    j["runCount"] = job.run_count;
    j["enabled"] = job.enabled;
    j["nextRun"] = job.next_run;
    if (job.max_count > 0) j["maxCount"] = job.max_count;
    arr.push_back(std::move(j));
  }

  json result;
  result["jobs"] = arr;
  result["count"] = static_cast<int>(arr.size());
  return types::ToolResult{true, result.dump(), ""};
}

static types::ToolResult cron_remove_impl(const std::string& args_json) {
  if (!g_scheduler) return types::ToolResult{false, "", "cron scheduler not available"};

  json params;
  try {
    params = json::parse(args_json);
  } catch (...) {
    return types::ToolResult{false, "", "invalid JSON"};
  }

  std::string job_id = params.value("jobId", "");
  if (job_id.empty()) {
    return types::ToolResult{false, "", "jobId is required"};
  }

  bool removed = g_scheduler->remove_job(job_id);
  if (!removed) {
    return types::ToolResult{false, "", "job not found: " + job_id};
  }

  json result;
  result["removed"] = true;
  result["jobId"] = job_id;
  return types::ToolResult{true, result.dump(), ""};
}

static types::ToolResult cron_runs_impl(const std::string& args_json) {
  if (!g_scheduler) return types::ToolResult{false, "", "cron scheduler not available"};

  json params;
  try {
    params = json::parse(args_json);
  } catch (...) {
    return types::ToolResult{false, "", "invalid JSON"};
  }

  std::string job_id = params.value("jobId", "");
  if (job_id.empty()) {
    return types::ToolResult{false, "", "jobId is required"};
  }

  auto runs = g_scheduler->get_runs(job_id);
  json arr = json::array();
  for (const auto& r : runs) {
    arr.push_back({
        {"startedAt", r.started_at},
        {"completedAt", r.completed_at},
        {"success", r.success},
        {"resultSummary", r.result_summary}
    });
  }

  json result;
  result["jobId"] = job_id;
  result["runs"] = arr;
  return types::ToolResult{true, result.dump(), ""};
}

void register_cron_tools() {
  register_tool("cron.add", cron_add_impl);
  register_tool("cron.list", cron_list_impl);
  register_tool("cron.remove", cron_remove_impl);
  register_tool("cron.runs", cron_runs_impl);
}

}  // namespace cron
}  // namespace hiclaw
```

- [ ] **Step 3: Register cron tools in tool.cpp**

In `server/src/tools/tool.cpp`, add `#include "hiclaw/cron/cron_tool.hpp"` at the top (after the other includes), and add the cron tool registration call inside `register_builtin_tools()` after the memo tools:

```cpp
  register_tool("memo.save", [](const std::string& args_json) -> ToolResult { return memo_save(args_json); });
  register_tool("memo.list", [](const std::string& args_json) -> ToolResult { return memo_list(args_json); });
  // Cron tools
  cron::register_cron_tools();
```

- [ ] **Step 4: Add cron tool definitions to all_tools_array() in agent.cpp**

In `server/src/agent/agent.cpp`, add these tool definitions inside `all_tools_array()` (after the remote tools loop, before `return tools;`):

```cpp
  // Cron tools
  tools.push_back(json::parse(R"({"type":"function","function":{"name":"cron.add","description":"Create a scheduled task that runs periodically or at a specific time. Use 'every' for intervals (e.g. 'every 1m', 'every 5m', 'every 1h'), 'at' for one-shot delayed execution (e.g. 'at +30m', 'at +1h'), 'cron' for cron expressions (e.g. 'cron 0 9 * * *' for daily at 9am). Results are automatically sent to the user.","parameters":{"type":"object","properties":{"schedule":{"type":"string","description":"Schedule: 'every 1m' | 'at +30m' | 'cron 0 9 * * *'"},"prompt":{"type":"string","description":"What the agent should do on each execution"},"maxCount":{"type":"integer","description":"Maximum number of executions (0=unlimited, default 0)","default":0},"maxDuration":{"type":"string","description":"Maximum total duration (e.g. '1h', '30m'). Empty=unlimited.","default":""}},"required":["schedule","prompt"]}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"cron.list","description":"List all scheduled tasks with their status, schedule, and run count.","parameters":{"type":"object","properties":{}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"cron.remove","description":"Remove/stop a scheduled task by its ID.","parameters":{"type":"object","properties":{"jobId":{"type":"string","description":"The cron job ID to remove"}},"required":["jobId"]}}})"));

  tools.push_back(json::parse(R"({"type":"function","function":{"name":"cron.runs","description":"View execution history for a scheduled task.","parameters":{"type":"object","properties":{"jobId":{"type":"string","description":"The cron job ID"}},"required":["jobId"]}}})"));
```

- [ ] **Step 5: Pass session_key to cron tool via args injection**

The `cron.add` tool needs the current session key to bind the job. In `server/src/agent/agent.cpp`, locate the tool execution loop (around line 849 where `tools::run_tool(tc.name, tc.arguments)` is called). Before the call, inject `_sessionKey` into the arguments if the tool starts with `cron.`:

Find this pattern:
```cpp
    tr = tools::run_tool(tc.name, tc.arguments);
```

Replace with:
```cpp
    std::string tool_args = tc.arguments;
    if (tc.name.rfind("cron.", 0) == 0) {
      // Inject session_key for cron tools
      try {
        auto j = nlohmann::json::parse(tool_args);
        j["_sessionKey"] = session_key;
        tool_args = j.dump();
      } catch (...) {}
    }
    tr = tools::run_tool(tc.name, tool_args);
```

This requires `session_key` to be available at that scope. Check that `session_key` is a parameter of the enclosing function or captured in the lambda. If not, thread it through from `run_streaming_with_history`.

- [ ] **Step 6: Build to verify compilation**

Run: `cd server && scripts\build-win-amd64.bat`
Expected: Build OK

- [ ] **Step 7: Commit**

```bash
git add server/include/hiclaw/cron/cron_tool.hpp server/src/cron/cron_tool.cpp server/src/tools/tool.cpp server/src/agent/agent.cpp
git commit -m "feat: add cron agent tools (cron.add/list/remove/runs)"
```

---

### Task 4: Gateway Integration

**Files:**
- Modify: `server/src/net/gateway.cpp:585-638` — create shared CronScheduler
- Modify: `server/src/main.cpp:215-244` — wire CronScheduler into gateway

- [ ] **Step 1: Add CronScheduler to gateway.cpp**

In `server/src/net/gateway.cpp`, add the include at the top:
```cpp
#include "hiclaw/cron/scheduler.hpp"
#include "hiclaw/cron/cron_tool.hpp"
```

In `run_wspp_server()`, before `server.set_open_handler(...)`, create a shared CronScheduler and start it:

```cpp
  // Shared CronScheduler for all sessions
  auto cron_session_store = std::make_shared<session::SessionStore>(config.config_dir);
  auto cron_scheduler = std::make_shared<cron::CronScheduler>(config.config_dir);
  // Will be started after first session creates an agent_manager (or we create one here)
  // For now, the scheduler uses the broadcast-based agent manager below.
```

Wait — the CronScheduler needs an AsyncAgentManager. Each WsppSession has its own. For cron tasks, we need a shared one. Create a shared agent manager for cron:

```cpp
  // Shared AsyncAgentManager for cron tasks (not tied to any WebSocket connection)
  auto cron_tool_router = std::make_shared<ToolRouter>();
  auto cron_agent_manager = std::make_shared<AsyncAgentManager>(
      config,
      [&server, &sessions](const std::string& event_name, const std::string& payload) {
        // Broadcast cron events to all connected operator sessions
        nlohmann::json ev;
        ev["type"] = "event";
        ev["event"] = event_name;
        try {
          ev["payload"] = nlohmann::json::parse(payload);
        } catch (...) {
          ev["payload"] = payload;
        }
        std::string msg = ev.dump();
        server.get_io_service().post([&server, &sessions, msg = std::move(msg)]() {
          for (auto& kv : sessions) {
            if (kv.second.connected) {
              try {
                server.send(kv.first, msg, websocketpp::frame::opcode::text);
              } catch (...) {}
            }
          }
        });
      },
      cron_session_store,
      cron_tool_router);

  // Wire node routing for cron tasks (same as WeChat adapter)
  // ... (use the existing node_invoker mechanism)

  auto cron_scheduler = std::make_shared<cron::CronScheduler>(config.config_dir);
  cron_scheduler->start(cron_agent_manager);
  cron::set_cron_scheduler(cron_scheduler.get());
```

This needs to be placed after the `node_invoker` setup (line ~583) and before `server.set_open_handler(...)` (line 585).

Also register the cron tool_router in the external_routers so remote tools work:

```cpp
  // Wire cron tool_router for remote tool execution
  if (external_routers) {
    // CronScheduler's remote tool calls will be routed through node_invoker
    // which is already set up above.
  }
```

- [ ] **Step 2: Handle node.invoke.request from cron tasks**

The cron's AsyncAgentManager needs to route `node.invoke.request` to connected node sessions. Use the same pattern as the WeChatAdapter — capture `node_invoker` and `external_routers` in the event callback.

In the cron event callback, add `node.invoke.request` routing (same logic as wechat_adapter.cpp lines 53-80):

```cpp
      // Route node.invoke.request to connected desktop node
      if (event_name == "node.invoke.request" && node_invoker && *node_invoker) {
        try {
          auto j = nlohmann::json::parse(payload);
          std::string invoke_id = j.value("id", "");
          std::string tool_call_id = invoke_id;
          if (tool_call_id.rfind("invoke_", 0) == 0) {
            tool_call_id = tool_call_id.substr(7);
          }
          if (external_routers && cron_tool_router) {
            (*external_routers)[tool_call_id] = cron_tool_router.get();
          }
          bool sent = (*node_invoker)(tool_call_id, payload);
          if (!sent) {
            cron_tool_router->complete_tool_call(tool_call_id,
                ToolResult{false, "", "No connected device node available"});
          }
        } catch (const std::exception& e) {
          log::warn("cron: failed to route node.invoke.request: " + std::string(e.what()));
        }
        return;
      }
```

- [ ] **Step 3: Stop CronScheduler on server shutdown**

At the end of `run_wspp_server()`, before `server.run()` returns, stop the scheduler:

After `server.run()` (line 1827), add:
```cpp
  cron_scheduler->stop();
```

- [ ] **Step 4: Build to verify compilation**

Run: `cd server && scripts\build-win-amd64.bat`
Expected: Build OK

- [ ] **Step 5: Commit**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat: integrate CronScheduler into gateway with shared agent manager"
```

---

### Task 5: Gateway RPC Handlers

**Files:**
- Modify: `server/src/net/gateway.cpp` — add cron RPC methods

- [ ] **Step 1: Add cron.list RPC handler**

After the `sessions.delete` handler in `gateway.cpp`, add:

```cpp
    // cron.list — return all scheduled tasks
    if (method == "cron.list") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      auto jobs = cron_scheduler->list_jobs();
      nlohmann::json arr = nlohmann::json::array();
      for (const auto& job : jobs) {
        nlohmann::json j;
        j["id"] = job.id;
        j["sessionKey"] = job.session_key;
        j["scheduleType"] = job.schedule_type;
        j["everyMs"] = job.every_ms;
        j["cronExpr"] = job.cron_expr;
        j["prompt"] = job.prompt;
        j["maxCount"] = job.max_count;
        j["maxDurationMs"] = job.max_duration_ms;
        j["runCount"] = job.run_count;
        j["createdAt"] = job.created_at;
        j["nextRun"] = job.next_run;
        j["enabled"] = job.enabled;
        arr.push_back(std::move(j));
      }

      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;
      res["ok"] = true;
      res["payload"] = {{"jobs", arr}, {"count", arr.size()}};
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }
```

- [ ] **Step 2: Add cron.add RPC handler**

```cpp
    // cron.add — create a scheduled task
    if (method == "cron.add") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res";
        res["id"] = id;
        res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string schedule, prompt, session_key_rpc, max_dur_str;
      int max_count = 0;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          schedule = wspp_get_string(j["params"], "schedule");
          prompt = wspp_get_string(j["params"], "prompt");
          session_key_rpc = wspp_get_string(j["params"], "sessionKey");
          if (session_key_rpc.empty()) session_key_rpc = "main";
          if (j["params"].contains("maxCount") && j["params"]["maxCount"].is_number_integer()) {
            max_count = j["params"]["maxCount"].get<int>();
          }
          max_dur_str = wspp_get_string(j["params"], "maxDuration");
        }
      } catch (...) {}

      if (schedule.empty() || prompt.empty()) {
        nlohmann::json res;
        res["type"] = "res"; res["id"] = id; res["ok"] = false;
        res["error"] = {{"message", "schedule and prompt required"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      // Parse and create
      std::string type, cron_expr;
      int every_ms = 0;
      int64_t at_ts = 0;
      nlohmann::json res;
      res["type"] = "res";
      res["id"] = id;

      // Inline schedule parsing (same as cron_tool.cpp)
      bool ok = false;
      if (schedule.rfind("every ", 0) == 0) {
        type = "every";
        // Parse duration
        std::string dur = schedule.substr(6);
        double val = 0;
        try { val = std::stod(dur); } catch (...) {}
        if (dur.find('h') != std::string::npos) every_ms = static_cast<int>(val * 3600000);
        else if (dur.find('m') != std::string::npos) every_ms = static_cast<int>(val * 60000);
        else every_ms = static_cast<int>(val * 1000);
        ok = every_ms > 0;
      } else if (schedule.rfind("at ", 0) == 0) {
        type = "at";
        std::string offset = schedule.substr(3);
        double val = 0;
        try { val = std::stod(offset[0] == '+' ? offset.substr(1) : offset); } catch (...) {}
        int ms = 0;
        if (offset.find('h') != std::string::npos) ms = static_cast<int>(val * 3600000);
        else if (offset.find('m') != std::string::npos) ms = static_cast<int>(val * 60000);
        else ms = static_cast<int>(val * 1000);
        at_ts = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count() + ms;
        ok = ms > 0;
      } else if (schedule.rfind("cron ", 0) == 0) {
        type = "cron";
        cron_expr = schedule.substr(5);
        ok = !cron_expr.empty();
      }

      if (!ok) {
        res["ok"] = false;
        res["error"] = {{"message", "invalid schedule format"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      int max_duration_ms = 0;
      if (!max_dur_str.empty()) {
        double dv = 0;
        try { dv = std::stod(max_dur_str); } catch (...) {}
        if (max_dur_str.find('h') != std::string::npos) max_duration_ms = static_cast<int>(dv * 3600000);
        else if (max_dur_str.find('m') != std::string::npos) max_duration_ms = static_cast<int>(dv * 60000);
        else max_duration_ms = static_cast<int>(dv * 1000);
      }
      std::string job_id = cron_scheduler->add_job(
          session_key_rpc, type, every_ms, at_ts, cron_expr,
          prompt, max_count, max_duration_ms);

      res["ok"] = !job_id.empty();
      res["payload"] = {{"jobId", job_id}};
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }
```

- [ ] **Step 3: Add cron.remove RPC handler**

```cpp
    // cron.remove — stop and remove a scheduled task
    if (method == "cron.remove") {
      if (!it->second.connected) {
        nlohmann::json res;
        res["type"] = "res"; res["id"] = id; res["ok"] = false;
        res["error"] = {{"code", "UNAUTHORIZED"}, {"message", "connect first"}};
        try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
        return;
      }

      std::string job_id;
      try {
        nlohmann::json j = nlohmann::json::parse(payload);
        if (j.contains("params") && j["params"].is_object()) {
          job_id = wspp_get_string(j["params"], "jobId");
        }
      } catch (...) {}

      bool removed = !job_id.empty() && cron_scheduler->remove_job(job_id);

      nlohmann::json res;
      res["type"] = "res"; res["id"] = id;
      res["ok"] = removed;
      if (!removed) res["error"] = {{"message", "job not found: " + job_id}};
      try { server.send(hdl, res.dump(), websocketpp::frame::opcode::text); } catch (...) {}
      return;
    }
```

- [ ] **Step 4: Build to verify compilation**

Run: `cd server && scripts\build-win-amd64.bat`
Expected: Build OK

- [ ] **Step 5: Commit**

```bash
git add server/src/net/gateway.cpp
git commit -m "feat: add gateway RPC handlers for cron.list/add/remove"
```

---

### Task 6: End-to-End Test + Desktop Bundle

**Files:** No code changes, manual testing

- [ ] **Step 1: Build and launch the full stack**

```bash
# Build server
cd server && scripts\build-win-amd64.bat

# Build desktop
cd desktop && flutter build windows

# Bundle hiclaw
cd desktop && powershell -File scripts\bundle-hiclaw.ps1
```

- [ ] **Step 2: Launch and test via WeChat/desktop chat**

Start `scripts\build-and-run.bat`, then send test messages:

Test 1 — "every 1m" with maxCount:
```
用户: "每分钟截一次屏，截3次后停止"
期望: Agent creates cron.add(schedule="every 1m", prompt="截取屏幕并发送截图", maxCount=3)
验证: 每分钟收到截图，3次后自动停止
```

Test 2 — "at" one-shot:
```
用户: "30秒后提醒我喝水"
期望: Agent creates cron.add(schedule="at +30s", prompt="提醒用户喝水")
验证: 30秒后收到提醒
```

Test 3 — "stop":
```
用户: "停止所有截屏任务"
期望: Agent calls cron.list → cron.remove
验证: 任务被删除，不再执行
```

- [ ] **Step 3: Verify session history persistence**

After tasks execute, check `~/.bonio/sessions/` for the cron session's chat history containing execution results.

- [ ] **Step 4: Verify gateway restart recovery**

1. Create a cron job
2. Kill and restart the gateway
3. Verify the job is still in the list and executes on schedule

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: cron agent tools — complete end-to-end integration"
```
