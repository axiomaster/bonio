#include "hiclaw/cron/schedule.hpp"
#include <algorithm>
#include <cstdlib>
#include <sstream>
#include <string>
#include <vector>

#ifdef _WIN32
#define timegm _mkgmtime
#endif

namespace hiclaw {
namespace cron {

namespace {

struct Field {
  bool any = true;   // *
  int value = 0;     // single value
  int step = 1;      // for */step
  int min_val = 0;
  int max_val = 0;
};

bool parse_field(const std::string& s, int min_v, int max_v, Field& out) {
  out = Field{};
  out.min_val = min_v;
  out.max_val = max_v;
  if (s == "*") {
    out.any = true;
    return true;
  }
  out.any = false;
  if (s.size() >= 2 && s[0] == '*' && s[1] == '/') {
    out.step = std::stoi(s.substr(2));
    if (out.step <= 0) return false;
    return true;
  }
  out.value = std::stoi(s);
  if (out.value < min_v || out.value > max_v) return false;
  return true;
}

bool matches(const Field& f, int v) {
  if (f.any) return true;
  if (f.step > 1)
    return v >= f.min_val && v <= f.max_val && (v - f.min_val) % f.step == 0;
  return v == f.value;
}

int days_in_month(int year, int month) {
  if (month < 1 || month > 12) return 31;
  static const int d[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  int n = d[month - 1];
  if (month == 2 && (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)))
    n = 29;
  return n;
}

}  // namespace

bool validate_expr(const std::string& expr) {
  std::istringstream is(expr);
  std::string parts[5];
  for (int i = 0; i < 5 && (is >> parts[i]); ++i) {}
  if (!(is >> parts[0]).fail()) return false;  // too many
  Field f[5];
  return parse_field(parts[0], 0, 59, f[0]) &&
         parse_field(parts[1], 0, 23, f[1]) &&
         parse_field(parts[2], 1, 31, f[2]) &&
         parse_field(parts[3], 1, 12, f[3]) &&
         parse_field(parts[4], 0, 6, f[4]);
}

std::time_t next_run_after(const std::string& expr, std::time_t from) {
  std::istringstream is(expr);
  std::string parts[5];
  for (int i = 0; i < 5; ++i) {
    if (!(is >> parts[i])) return 0;
  }
  Field min_f, hour_f, dom_f, month_f, dow_f;
  if (!parse_field(parts[0], 0, 59, min_f)) return 0;
  if (!parse_field(parts[1], 0, 23, hour_f)) return 0;
  if (!parse_field(parts[2], 1, 31, dom_f)) return 0;
  if (!parse_field(parts[3], 1, 12, month_f)) return 0;
  if (!parse_field(parts[4], 0, 6, dow_f)) return 0;

  std::tm t = {};
  {
    std::tm* u = std::gmtime(&from);
    if (!u) return 0;
    t = *u;
  }
  t.tm_sec = 0;
  t.tm_min++;
  if (t.tm_min > 59) { t.tm_min = 0; t.tm_hour++; }
  if (t.tm_hour > 23) { t.tm_hour = 0; t.tm_mday++; }
  if (t.tm_mday > 31) { t.tm_mday = 1; t.tm_mon++; }
  if (t.tm_mon > 11) { t.tm_mon = 0; t.tm_year++; }

  const int max_iter = 366 * 24 * 60;
  for (int iter = 0; iter < max_iter; iter++) {
    if (t.tm_mday < 1 || t.tm_mday > days_in_month(t.tm_year + 1900, t.tm_mon + 1)) {
      t.tm_mday = 1;
      t.tm_mon++;
      if (t.tm_mon > 11) { t.tm_mon = 0; t.tm_year++; }
      continue;
    }
    std::tm t2 = t;
    t2.tm_isdst = 0;
    std::time_t candidate = timegm(&t2);
    if (candidate == static_cast<std::time_t>(-1)) return 0;
    if (candidate <= from) {
      t.tm_min++;
      if (t.tm_min > 59) { t.tm_min = 0; t.tm_hour++; }
      if (t.tm_hour > 23) { t.tm_hour = 0; t.tm_mday++; }
      if (t.tm_mday > 31) { t.tm_mday = 1; t.tm_mon++; }
      if (t.tm_mon > 11) { t.tm_mon = 0; t.tm_year++; }
      continue;
    }
    std::tm* normalized = std::gmtime(&candidate);
    if (!normalized) return 0;
    int dow = normalized->tm_wday;
    if (dow == 0) dow = 7;
    dow--;
    if (dow < 0) dow = 6;

    if (!matches(min_f, normalized->tm_min)) { t.tm_min++; if (t.tm_min > 59) { t.tm_min = 0; t.tm_hour++; } continue; }
    if (!matches(hour_f, normalized->tm_hour)) { t.tm_hour++; if (t.tm_hour > 23) { t.tm_hour = 0; t.tm_mday++; } continue; }
    if (!matches(dom_f, normalized->tm_mday)) { t.tm_mday++; continue; }
    if (!matches(month_f, normalized->tm_mon + 1)) { t.tm_mon++; if (t.tm_mon > 11) { t.tm_mon = 0; t.tm_year++; } continue; }
    if (!matches(dow_f, dow)) { t.tm_mday++; continue; }

    return candidate;
  }
  return 0;
}

}  // namespace cron
}  // namespace hiclaw
