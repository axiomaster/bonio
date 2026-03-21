#ifndef HICLAW_MEMORY_MEMORY_HPP
#define HICLAW_MEMORY_MEMORY_HPP

#include <string>
#include <vector>

namespace hiclaw {
namespace memory {

struct MemoryEntry {
  std::string id;
  std::string key;
  std::string content;
  std::string category;
  std::string timestamp;
};

/// Set base directory for memory storage (e.g. config_dir or ".hiclaw"). Called by agent before run.
void set_base_path(const std::string& path);
std::string get_base_path();

/// Store a memory. category: "core", "daily", "conversation", or custom. Returns false on error.
bool store(const std::string& key, const std::string& content, const std::string& category);

/// Recall memories matching query (substring in content/key). Returns up to limit entries.
std::vector<MemoryEntry> recall(const std::string& query, size_t limit);

/// Forget memory by key. Returns true if found and removed.
bool forget(const std::string& key);

}  // namespace memory
}  // namespace hiclaw

#endif
