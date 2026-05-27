#ifndef HICLAW_CRON_SCHEDULER_HPP
#define HICLAW_CRON_SCHEDULER_HPP

#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace hiclaw {

namespace net {
class AsyncAgentManager;
}  // namespace net

namespace cron {

/// Record of a single job execution.
struct RunRecord {
  int64_t started_at = 0;      // ms since epoch
  int64_t completed_at = 0;    // ms since epoch
  bool success = false;
  std::string result_summary;
};

/// A scheduled cron job with richer metadata than the legacy store CronJob.
struct SchedulerJob {
  std::string id;
  std::string session_key;     // which session to run the prompt in
  std::string schedule_type;   // "every", "at", or "cron"

  // Schedule parameters (used depending on schedule_type)
  int64_t every_ms = 0;            // for "every"
  int64_t at_timestamp = 0;        // for "at" — ms since epoch
  std::string cron_expr;           // for "cron" — 5-field expression

  std::string prompt;              // message sent to agent

  // Limits
  int max_count = 0;               // 0 = unlimited
  int64_t max_duration_ms = 0;     // 0 = unlimited

  // Runtime state
  int run_count = 0;
  int64_t created_at = 0;          // ms since epoch
  int64_t next_run = 0;            // ms since epoch
  bool enabled = true;

  /// Keep last N run records (max 20).
  static constexpr size_t kMaxRecentRuns = 20;
  std::vector<RunRecord> recent_runs;
};

/// Threaded scheduler that dispatches cron jobs through AsyncAgentManager.
class CronScheduler {
 public:
  explicit CronScheduler(const std::string& config_dir);

  ~CronScheduler();

  // Not copyable
  CronScheduler(const CronScheduler&) = delete;
  CronScheduler& operator=(const CronScheduler&) = delete;

  /// Start the scheduler loop in a background thread.
  void start(std::shared_ptr<net::AsyncAgentManager> agent_manager);

  /// Stop the scheduler loop and join the background thread.
  void stop();

  /// Create a new job. Returns the job id, or empty on error.
  std::string add_job(const std::string& session_key,
                      const std::string& schedule_type,
                      int64_t every_ms,
                      int64_t at_timestamp,
                      const std::string& cron_expr,
                      const std::string& prompt,
                      int max_count = 0,
                      int64_t max_duration_ms = 0);

  /// Remove a job by id. Returns true if found and removed.
  bool remove_job(const std::string& id);

  /// List all jobs (copies under lock).
  std::vector<SchedulerJob> list_jobs();

  /// Get recent runs for a specific job. Returns empty if not found.
  std::vector<RunRecord> get_runs(const std::string& id);

 private:
  /// Main loop: ticks every second, dispatches due jobs.
  void scheduler_loop();

  /// Compute the next run time (ms since epoch) for a job.
  int64_t compute_next_run(const SchedulerJob& job);

  /// Persist all jobs to disk.
  void save_jobs();

  /// Load jobs from disk (called once at start).
  void load_jobs();

  /// Path to the jobs JSON file.
  std::string jobs_path() const;

  /// Generate a unique job id: "cron_" + hex random.
  static std::string generate_id();

  std::string config_dir_;
  std::shared_ptr<net::AsyncAgentManager> agent_manager_;

  std::mutex mutex_;
  std::vector<SchedulerJob> jobs_;
  std::thread thread_;
  std::atomic<bool> running_{false};
};

}  // namespace cron
}  // namespace hiclaw

#endif  // HICLAW_CRON_SCHEDULER_HPP
