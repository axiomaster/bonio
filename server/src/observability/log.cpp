#include "hiclaw/observability/log.hpp"
#include <spdlog/spdlog.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_sinks.h>
#include <filesystem>
#include <memory>
#include <mutex>

namespace hiclaw {
namespace log {

namespace {

using level_enum = spdlog::level::level_enum;

constexpr level_enum to_spdlog(Level l) {
  switch (l) {
    case Level::Off: return level_enum::off;
    case Level::Error: return level_enum::err;
    case Level::Warn: return level_enum::warn;
    case Level::Info: return level_enum::info;
    case Level::Debug: return level_enum::debug;
    case Level::Trace: return level_enum::trace;
  }
  return level_enum::info;
}

Level from_spdlog(level_enum l) {
  switch (l) {
    case level_enum::off: return Level::Off;
    case level_enum::err: return Level::Error;
    case level_enum::warn: return Level::Warn;
    case level_enum::info: return Level::Info;
    case level_enum::debug: return Level::Debug;
    case level_enum::trace: return Level::Trace;
    default: return Level::Info;
  }
}

std::shared_ptr<spdlog::logger> g_logger;
std::string g_log_dir;
level_enum g_level = level_enum::info;
std::mutex g_mutex;

std::shared_ptr<spdlog::logger> make_hiclaw_logger() {
  std::vector<spdlog::sink_ptr> sinks;
  sinks.push_back(std::make_shared<spdlog::sinks::stderr_sink_mt>());
  if (!g_log_dir.empty()) {
    std::string log_dir = g_log_dir + "/logs";
    std::error_code ec;
    std::filesystem::create_directories(log_dir, ec);
    if (!ec) {
      std::string path = log_dir + "/hiclaw.log";
      try {
        auto file_sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(path, false);
        sinks.push_back(std::move(file_sink));
      } catch (...) {}
    }
  }
  auto logger = std::make_shared<spdlog::logger>("hiclaw", sinks.begin(), sinks.end());
  logger->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
  logger->set_level(g_level);
  return logger;
}

std::shared_ptr<spdlog::logger> get_logger() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_logger)
    g_logger = make_hiclaw_logger();
  return g_logger;
}

}  // namespace

void set_level(const std::string& name) {
  if (name == "off") set_level(Level::Off);
  else if (name == "error") set_level(Level::Error);
  else if (name == "warn") set_level(Level::Warn);
  else if (name == "info") set_level(Level::Info);
  else if (name == "debug") set_level(Level::Debug);
  else if (name == "trace") set_level(Level::Trace);
}

void set_level(Level l) {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_level = to_spdlog(l);
  if (g_logger)
    g_logger->set_level(g_level);
  else {
    g_logger = make_hiclaw_logger();
  }
}

Level get_level() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_logger) return Level::Info;
  return from_spdlog(g_logger->level());
}

void set_log_dir(const std::string& workspace_dir) {
  if (workspace_dir.empty()) return;
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_log_dir == workspace_dir) return;
  g_log_dir = workspace_dir;
  g_logger = make_hiclaw_logger();
}

void error(const std::string& msg) {
  get_logger()->error("{}", msg);
}

void warn(const std::string& msg) {
  get_logger()->warn("{}", msg);
}

void info(const std::string& msg) {
  get_logger()->info("{}", msg);
}

void debug(const std::string& msg) {
  get_logger()->debug("{}", msg);
}

void trace(const std::string& msg) {
  get_logger()->trace("{}", msg);
}

}  // namespace log
}  // namespace hiclaw
