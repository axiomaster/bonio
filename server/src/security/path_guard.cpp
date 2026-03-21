#include "hiclaw/security/path_guard.hpp"
#include <algorithm>
#include <cctype>
#include <string>

namespace hiclaw {
namespace security {

namespace {

std::string normalize(const std::string& path) {
  std::string s = path;
  while (!s.empty() && (s.back() == '/' || s.back() == '\\')) s.pop_back();
  for (size_t i = 0; i < s.size(); ++i) {
    if (s[i] == '\\') s[i] = '/';
    else s[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(s[i])));
  }
  if (s.size() >= 2 && s[1] == ':') {
    if (s.size() >= 3 && s[2] == '/') { /* C:/... */ }
    else if (s.size() == 2) s += "/";
  }
  return s;
}

bool starts_with(const std::string& s, const std::string& prefix) {
  return s.size() >= prefix.size() &&
         std::equal(prefix.begin(), prefix.end(), s.begin());
}

}  // namespace

bool is_path_allowed(const std::string& path) {
  std::string s = normalize(path);
  if (s.empty()) return false;

  const char* blocked[] = {
    "/etc/", "/etc",
    "/system/", "/system",
    "/vendor/", "/vendor",
    "/data/local/tmp/",
    "c:/windows/system",
    "c:/program files",
    "c:/program files (x86)",
    "/proc/", "/proc",
    "/sys/", "/sys",
    nullptr
  };
  for (int i = 0; blocked[i]; ++i) {
    if (starts_with(s, blocked[i])) return false;
  }
  if (s.find("/../") != std::string::npos) return false;
  if (s.size() >= 3 && s.compare(0, 3, "../") == 0) return false;
  return true;
}

}  // namespace security
}  // namespace hiclaw
