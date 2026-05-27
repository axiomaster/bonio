#include "hiclaw/cron/scheduler.hpp"

#include "hiclaw/cron/schedule.hpp"
#include "hiclaw/net/async_agent.hpp"
#include "hiclaw/observability/log.hpp"

#include <nlohmann/json.hpp>

#include <chrono>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <random>

#ifdef _WIN32
#define timegm _mkgmtime
#endif

namespace hiclaw {
namespace cron {

namespace {

using json = nlohmann::json;

/// Current time in milliseconds since epoch.
int64_t now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

/// Convert milliseconds since epoch to time_t (seconds).
std::time_t ms_to_time(int64_t ms) {
  return static_cast<std::time_t>(ms / 1000);
}

/// Convert time_t (seconds) to milliseconds since epoch.
int64_t time_to_ms(std::time_t t) {
  return static_cast<int64_t>(t) * 1000;
}

std::string time_to_iso(std::time_t t) {
  std::tm* u = std::gmtime(&t);
  if (!u) return "";
  char buf[32];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           u->tm_year + 1900, u->tm_mon + 1, u->tm_mday,
           u->tm_hour, u->tm_min, u->tm_sec);
  return std::string(buf);
}

json run_record_to_json(const RunRecord& r) {
  return json{
      {"started_at", r.started_at},
      {"completed_at", r.completed_at},
      {"success", r.success},
      {"result_summary", r.result_summary},
  };
}

RunRecord json_to_run_record(const json& j) {
  RunRecord r;
  if (j.contains("started_at") && j["started_at"].is_number()) {
    r.started_at = j["started_at"].get<int64_t>();
  }
  if (j.contains("completed_at") && j["completed_at"].is_number()) {
    r.completed_at = j["completed_at"].get<int64_t>();
  }
  if (j.contains("success") && j["success"].is_boolean()) {
    r.success = j["success"].get<bool>();
  }
  if (j.contains("result_summary") && j["result_summary"].is_string()) {
    r.result_summary = j["result_summary"].get<std::string>();
  }
  return r;
}

json job_to_json(const SchedulerJob& job) {
  json j;
  j["id"] = job.id;
  j["session_key"] = job.session_key;
  j["schedule_type"] = job.schedule_type;
  j["every_ms"] = job.every_ms;
  j["at_timestamp"] = job.at_timestamp;
  j["cron_expr"] = job.cron_expr;
  j["prompt"] = job.prompt;
  j["max_count"] = job.max_count;
  j["max_duration_ms"] = job.max_duration_ms;
  j["run_count"] = job.run_count;
  j["created_at"] = job.created_at;
  j["next_run"] = job.next_run;
  j["enabled"] = job.enabled;

  json runs = json::array();
  for (const auto& r : job.recent_runs) {
    runs.push_back(run_record_to_json(r));
  }
  j["recent_runs"] = std::move(runs);
  return j;
}

SchedulerJob json_to_job(const json& j) {
  SchedulerJob job;
  if (j.contains("id") && j["id"].is_string()) job.id = j["id"].get<std::string>();
  if (j.contains("session_key") && j["session_key"].is_string()) job.session_key = j["session_key"].get<std::string>();
  if (j.contains("schedule_type") && j["schedule_type"].is_string()) job.schedule_type = j["schedule_type"].get<std::string>();
  if (j.contains("every_ms") && j["every_ms"].is_number()) job.every_ms = j["every_ms"].get<int64_t>();
  if (j.contains("at_timestamp") && j["at_timestamp"].is_number()) job.at_timestamp = j["at_timestamp"].get<int64_t>();
  if (j.contains("cron_expr") && j["cron_expr"].is_string()) job.cron_expr = j["cron_expr"].get<std::string>();
  if (j.contains("prompt") && j["prompt"].is_string()) job.prompt = j["prompt"].get<std::string>();
  if (j.contains("max_count") && j["max_count"].is_number()) job.max_count = j["max_count"].get<int>();
  if (j.contains("max_duration_ms") && j["max_duration_ms"].is_number()) job.max_duration_ms = j["max_duration_ms"].get<int64_t>();
  if (j.contains("run_count") && j["run_count"].is_number()) job.run_count = j["run_count"].get<int>();
  if (j.contains("created_at") && j["created_at"].is_number()) job.created_at = j["created_at"].get<int64_t>();
  if (j.contains("next_run") && j["next_run"].is_number()) job.next_run = j["next_run"].get<int64_t>();
  if (j.contains("enabled") && j["enabled"].is_boolean()) job.enabled = j["enabled"].get<bool>();

  if (j.contains("recent_runs") && j["recent_runs"].is_array()) {
    for (const auto& rj : j["recent_runs"]) {
      job.recent_runs.push_back(json_to_run_record(rj));
    }
  }
  return job;
}

}  // namespace

// ---------------------------------------------------------------------------
// CronScheduler
// ---------------------------------------------------------------------------

CronScheduler::CronScheduler(const std::string& config_dir)
    : config_dir_(config_dir) {}

CronScheduler::~CronScheduler() {
  stop();
}

void CronScheduler::start(std::shared_ptr<net::AsyncAgentManager> agent_manager) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (running_.load()) return;
  agent_manager_ = std::move(agent_manager);

  load_jobs();

  // Recompute next_run for enabled recurring jobs so they fire correctly
  // after a server restart.
  int64_t now = now_ms();
  for (auto& job : jobs_) {
    if (job.enabled) {
      // Only recompute for recurring types; "at" jobs keep their timestamp.
      if (job.schedule_type == "every" || job.schedule_type == "cron") {
        if (job.next_run <= now) {
          job.next_run = compute_next_run(job);
        }
      }
    }
  }
  save_jobs();

  running_.store(true);
  thread_ = std::thread(&CronScheduler::scheduler_loop, this);
  log::info("CronScheduler started");
}

void CronScheduler::stop() {
  if (!running_.load()) return;
  running_.store(false);
  if (thread_.joinable()) {
    thread_.join();
  }
  log::info("CronScheduler stopped");
}

std::string CronScheduler::add_job(const std::string& session_key,
                                   const std::string& schedule_type,
                                   int64_t every_ms,
                                   int64_t at_timestamp,
                                   const std::string& cron_expr,
                                   const std::string& prompt,
                                   int max_count,
                                   int64_t max_duration_ms) {
  // Validate cron expression if type is "cron"
  if (schedule_type == "cron" && !cron_expr.empty()) {
    if (!validate_expr(cron_expr)) {
      log::warn("CronScheduler: invalid cron expression: " + cron_expr);
      return "";
    }
  }

  SchedulerJob job;
  job.id = generate_id();
  job.session_key = session_key;
  job.schedule_type = schedule_type;
  job.every_ms = every_ms;
  job.at_timestamp = at_timestamp;
  job.cron_expr = cron_expr;
  job.prompt = prompt;
  job.max_count = max_count;
  job.max_duration_ms = max_duration_ms;
  job.run_count = 0;
  job.created_at = now_ms();
  job.enabled = true;
  job.next_run = compute_next_run(job);

  if (job.next_run == 0 && schedule_type != "at") {
    log::warn("CronScheduler: could not compute next run for job");
    return "";
  }

  std::string new_id;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    jobs_.push_back(std::move(job));
    new_id = jobs_.back().id;
    save_jobs();
  }

  log::info("CronScheduler: added job " + new_id + " (type=" + schedule_type + ")");
  return new_id;
}

bool CronScheduler::remove_job(const std::string& id) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = std::find_if(jobs_.begin(), jobs_.end(),
                         [&](const SchedulerJob& j) { return j.id == id; });
  if (it == jobs_.end()) return false;
  jobs_.erase(it);
  save_jobs();
  log::info("CronScheduler: removed job " + id);
  return true;
}

std::vector<SchedulerJob> CronScheduler::list_jobs() {
  std::lock_guard<std::mutex> lock(mutex_);
  return jobs_;
}

std::vector<RunRecord> CronScheduler::get_runs(const std::string& id) {
  std::lock_guard<std::mutex> lock(mutex_);
  for (const auto& job : jobs_) {
    if (job.id == id) {
      return job.recent_runs;
    }
  }
  return {};
}

// ---------------------------------------------------------------------------
// scheduler_loop
// ---------------------------------------------------------------------------

void CronScheduler::scheduler_loop() {
  while (running_.load()) {
    int64_t now = now_ms();

    {
      std::lock_guard<std::mutex> lock(mutex_);
      bool dirty = false;
      for (auto& job : jobs_) {
        if (!job.enabled) continue;
        if (job.next_run <= 0) continue;
        if (now < job.next_run) continue;

        // --- Dispatch job ---
        char dispatch_buf[128];
        snprintf(dispatch_buf, sizeof(dispatch_buf),
                 "CronScheduler: dispatching job %s (run #%d)", job.id.c_str(), job.run_count + 1);
        log::info(dispatch_buf);

        RunRecord rec;
        rec.started_at = now;

        std::string result_summary;
        bool success = false;

        if (!agent_manager_) {
          result_summary = "no agent_manager";
        } else {
          try {
            std::string run_id = agent_manager_->start_task(job.session_key, job.prompt);
            if (!run_id.empty()) {
              success = true;
              result_summary = "run_id=" + run_id;
            } else {
              result_summary = "start_task returned empty run_id";
            }
          } catch (const std::exception& e) {
            result_summary = std::string("error: ") + e.what();
          }
        }

        rec.completed_at = now_ms();
        rec.success = success;
        rec.result_summary = result_summary;

        job.run_count++;
        dirty = true;

        // Append run record, trimming to kMaxRecentRuns
        job.recent_runs.push_back(std::move(rec));
        if (job.recent_runs.size() > SchedulerJob::kMaxRecentRuns) {
          job.recent_runs.erase(job.recent_runs.begin(),
                                job.recent_runs.begin() +
                                    (job.recent_runs.size() - SchedulerJob::kMaxRecentRuns));
        }

        // --- Check stop conditions ---
        bool should_disable = false;

        // max_count reached
        if (job.max_count > 0 && job.run_count >= job.max_count) {
          should_disable = true;
          char mc_buf[128];
          snprintf(mc_buf, sizeof(mc_buf),
                   "CronScheduler: job %s reached max_count=%d", job.id.c_str(), job.max_count);
          log::info(mc_buf);
        }

        // max_duration_ms exceeded
        if (job.max_duration_ms > 0) {
          int64_t elapsed = now_ms() - job.created_at;
          if (elapsed >= job.max_duration_ms) {
            should_disable = true;
            char md_buf[160];
            snprintf(md_buf, sizeof(md_buf),
                     "CronScheduler: job %s exceeded max_duration_ms=%lld",
                     job.id.c_str(), static_cast<long long>(job.max_duration_ms));
            log::info(md_buf);
          }
        }

        // "at" type is one-shot
        if (job.schedule_type == "at") {
          should_disable = true;
        }

        if (should_disable) {
          job.enabled = false;
          job.next_run = 0;
        } else {
          job.next_run = compute_next_run(job);
        }
      }

      if (dirty) save_jobs();
    }

    // Sleep for 1 second
    std::this_thread::sleep_for(std::chrono::seconds(1));
  }
}

// ---------------------------------------------------------------------------
// compute_next_run
// ---------------------------------------------------------------------------

int64_t CronScheduler::compute_next_run(const SchedulerJob& job) {
  int64_t now = now_ms();

  if (job.schedule_type == "every") {
    if (job.every_ms <= 0) return 0;
    return now + job.every_ms;
  }

  if (job.schedule_type == "at") {
    return job.at_timestamp;
  }

  if (job.schedule_type == "cron") {
    if (job.cron_expr.empty()) return 0;
    std::time_t from = ms_to_time(now);
    std::time_t next = next_run_after(job.cron_expr, from);
    if (next <= 0) return 0;
    return time_to_ms(next);
  }

  return 0;
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

void CronScheduler::save_jobs() {
  // Caller must hold mutex_.
  std::string dir = (std::filesystem::path(config_dir_) / "cron").string();
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  if (ec) {
    log::error("CronScheduler: cannot create dir " + dir + ": " + ec.message());
    return;
  }

  std::string path = jobs_path();
  json arr = json::array();
  for (const auto& job : jobs_) {
    arr.push_back(job_to_json(job));
  }

  std::ofstream f(path);
  if (!f) {
    log::error("CronScheduler: cannot write " + path);
    return;
  }
  f << arr.dump(2);
}

void CronScheduler::load_jobs() {
  // Caller must hold mutex_.
  jobs_.clear();
  std::string path = jobs_path();
  std::ifstream f(path);
  if (!f) return;

  try {
    json j = json::parse(f);
    if (!j.is_array()) return;
    for (const json& el : j) {
      if (!el.is_object()) continue;
      jobs_.push_back(json_to_job(el));
    }
  } catch (const json::parse_error& e) {
    log::error("CronScheduler: parse error in " + path + ": " + e.what());
  }
}

std::string CronScheduler::jobs_path() const {
  return (std::filesystem::path(config_dir_) / "cron" / "scheduler_jobs.json").string();
}

// ---------------------------------------------------------------------------
// generate_id
// ---------------------------------------------------------------------------

std::string CronScheduler::generate_id() {
  static std::mt19937 rng(
      static_cast<unsigned>(std::chrono::steady_clock::now().time_since_epoch().count()));
  char buf[24];
  snprintf(buf, sizeof(buf), "cron_%08x", rng());
  return std::string(buf);
}

}  // namespace cron
}  // namespace hiclaw
