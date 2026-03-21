#include "hiclaw/cron/schedule.hpp"
#include "hiclaw/cron/store.hpp"
#include <nlohmann/json.hpp>
#include <chrono>
#ifdef _WIN32
#define timegm _mkgmtime
#endif
#include <filesystem>
#include <fstream>
#include <random>
#include <sstream>

namespace hiclaw {
namespace cron {

namespace {

using json = nlohmann::json;

std::string time_to_iso(std::time_t t) {
  std::tm* u = std::gmtime(&t);
  if (!u) return "";
  char buf[32];
  snprintf(buf, sizeof(buf), "%04d-%02d-%02dT%02d:%02d:%02dZ",
           u->tm_year + 1900, u->tm_mon + 1, u->tm_mday,
           u->tm_hour, u->tm_min, u->tm_sec);
  return std::string(buf);
}

std::time_t iso_to_time(const std::string& s) {
  int y = 0, mo = 0, d = 0, h = 0, mi = 0, sec = 0;
  if (sscanf(s.c_str(), "%d-%d-%dT%d:%d:%d", &y, &mo, &d, &h, &mi, &sec) < 6)
    return 0;
  std::tm t = {};
  t.tm_year = y - 1900;
  t.tm_mon = mo - 1;
  t.tm_mday = d;
  t.tm_hour = h;
  t.tm_min = mi;
  t.tm_sec = sec;
  t.tm_isdst = 0;
#ifdef _WIN32
  return _mkgmtime(&t);
#else
  return timegm(&t);
#endif
}

std::string cron_dir(const std::string& config_dir) {
  std::string base = config_dir.empty() ? ".hiclaw" : config_dir;
  return (std::filesystem::path(base) / "cron").string();
}

std::string jobs_path(const std::string& config_dir) {
  return (std::filesystem::path(cron_dir(config_dir)) / "jobs.json").string();
}

}  // namespace

std::string make_job_id() {
  static std::mt19937 rng(static_cast<unsigned>(std::chrono::steady_clock::now().time_since_epoch().count()));
  char buf[16];
  snprintf(buf, sizeof(buf), "job_%08x", rng());
  return std::string(buf);
}

std::vector<CronJob> load_jobs(const std::string& config_dir) {
  std::vector<CronJob> jobs;
  std::string path = jobs_path(config_dir);
  std::ifstream f(path);
  if (!f) return jobs;
  try {
    json j = json::parse(f);
    if (!j.is_array()) return jobs;
    for (const json& el : j) {
      if (!el.is_object() || !el.contains("id") || !el["id"].is_string()) continue;
      CronJob job;
      job.id = el["id"].get<std::string>();
      if (el.contains("expr") && el["expr"].is_string()) job.expr = el["expr"].get<std::string>();
      if (el.contains("prompt") && el["prompt"].is_string()) job.prompt = el["prompt"].get<std::string>();
      if (el.contains("next_run_iso") && el["next_run_iso"].is_string()) job.next_run_iso = el["next_run_iso"].get<std::string>();
      job.next_run = iso_to_time(job.next_run_iso);
      jobs.push_back(std::move(job));
    }
  } catch (const json::parse_error&) {}
  return jobs;
}

bool save_jobs(const std::string& config_dir, const std::vector<CronJob>& jobs) {
  std::string dir = cron_dir(config_dir);
  std::error_code ec;
  std::filesystem::create_directories(dir, ec);
  if (ec) return false;
  std::string path = jobs_path(config_dir);
  json arr = json::array();
  for (const CronJob& job : jobs) {
    arr.push_back({{"id", job.id}, {"expr", job.expr}, {"prompt", job.prompt}, {"next_run_iso", job.next_run_iso}});
  }
  std::ofstream f(path);
  if (!f) return false;
  f << arr.dump();
  return true;
}

std::string add_job(const std::string& config_dir, const std::string& expr, const std::string& prompt) {
  if (!validate_expr(expr)) return "";
  std::time_t now = std::time(nullptr);
  std::time_t next = next_run_after(expr, now);
  if (next == 0) return "";
  std::vector<CronJob> jobs = load_jobs(config_dir);
  CronJob job;
  job.id = make_job_id();
  job.expr = expr;
  job.prompt = prompt;
  job.next_run_iso = time_to_iso(next);
  job.next_run = next;
  jobs.push_back(job);
  if (!save_jobs(config_dir, jobs)) return "";
  return job.id;
}

bool update_job_next_run(const std::string& config_dir, const std::string& id, std::time_t next_run) {
  std::vector<CronJob> jobs = load_jobs(config_dir);
  for (auto& j : jobs) {
    if (j.id == id) {
      j.next_run = next_run;
      j.next_run_iso = time_to_iso(next_run);
      return save_jobs(config_dir, jobs);
    }
  }
  return false;
}

}  // namespace cron
}  // namespace hiclaw
