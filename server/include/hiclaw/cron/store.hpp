#ifndef HICLAW_CRON_STORE_HPP
#define HICLAW_CRON_STORE_HPP

#include <ctime>
#include <string>
#include <vector>

namespace hiclaw {
namespace cron {

struct CronJob {
  std::string id;
  std::string expr;
  std::string prompt;
  std::string next_run_iso;  // UTC ISO format
  std::time_t next_run = 0;
};

/// Load jobs from config_dir/cron/jobs.json. Returns empty on missing file or parse error.
std::vector<CronJob> load_jobs(const std::string& config_dir);

/// Save jobs to config_dir/cron/jobs.json.
bool save_jobs(const std::string& config_dir, const std::vector<CronJob>& jobs);

/// Add agent job; returns new job id or empty on error.
std::string add_job(const std::string& config_dir, const std::string& expr, const std::string& prompt);

/// Update job next_run and persist.
bool update_job_next_run(const std::string& config_dir, const std::string& id, std::time_t next_run);

/// Generate a simple unique id.
std::string make_job_id();

}  // namespace cron
}  // namespace hiclaw

#endif
