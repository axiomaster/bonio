#ifndef HICLAW_SECURITY_PATH_GUARD_HPP
#define HICLAW_SECURITY_PATH_GUARD_HPP

#include <string>

namespace hiclaw {
namespace security {

/**
 * Check if a file path is allowed for tool access (file_read, file_write).
 * Blocks system dirs (e.g. /etc, /system, Windows\\System32) to reduce risk.
 * Returns true if access is allowed, false if path is sensitive.
 */
bool is_path_allowed(const std::string& path);

}  // namespace security
}  // namespace hiclaw

#endif
