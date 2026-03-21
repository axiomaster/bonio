#include "hiclaw/skills/skill_manager.hpp"
#include "hiclaw/observability/log.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <memory>
#include <set>
#include <sstream>

namespace hiclaw {
namespace skills {

namespace fs = std::filesystem;

SkillManager::SkillManager(const std::string& workspace_dir)
    : workspace_dir_(workspace_dir),
      builtin_dir_((fs::path(workspace_dir) / "skills" / "builtin").string()),
      installed_dir_((fs::path(workspace_dir) / "skills" / "installed").string()) {}

void SkillManager::load_all() {
  skills_.clear();

  try {
    fs::create_directories(builtin_dir_);
    fs::create_directories(installed_dir_);
  } catch (const std::exception& e) {
    log::warn("SkillManager: failed to create skill dirs: " + std::string(e.what()));
  }

  if (fs::exists(builtin_dir_)) {
    for (const auto& entry : fs::directory_iterator(builtin_dir_)) {
      if (entry.is_directory()) {
        load_skill_dir(entry.path().string(), true);
      }
    }
  }

  if (fs::exists(installed_dir_)) {
    for (const auto& entry : fs::directory_iterator(installed_dir_)) {
      if (entry.is_directory()) {
        load_skill_dir(entry.path().string(), false);
      }
    }
  }

  load_disabled();
  log::info("SkillManager: loaded " + std::to_string(skills_.size()) + " skills");
}

bool SkillManager::load_skill_dir(const std::string& dir_path, bool is_builtin) {
  std::string md_path = (fs::path(dir_path) / "SKILL.md").string();
  if (!fs::exists(md_path)) {
    log::warn("SkillManager: no SKILL.md in " + dir_path);
    return false;
  }

  Skill skill;
  if (!parse_skill_md(md_path, skill)) {
    return false;
  }

  skill.id = fs::path(dir_path).filename().string();
  skill.builtin = is_builtin;

  if (skill.name.empty()) {
    skill.name = skill.id;
  }

  for (const auto& existing : skills_) {
    if (existing.id == skill.id) {
      log::warn("SkillManager: duplicate skill id '" + skill.id + "', skipping " + dir_path);
      return false;
    }
  }

  log::info("SkillManager: loaded skill '" + skill.name + "'" +
            (is_builtin ? " [builtin]" : " [installed]"));
  skills_.push_back(std::move(skill));
  return true;
}

/**
 * Parse YAML frontmatter delimited by "---" lines.
 * Extracts simple "key: value" pairs for name and description.
 */
bool SkillManager::parse_skill_md(const std::string& md_path, Skill& out) {
  try {
    std::ifstream f(md_path);
    if (!f.is_open()) {
      log::error("SkillManager: cannot open " + md_path);
      return false;
    }

    std::string content((std::istreambuf_iterator<char>(f)),
                         std::istreambuf_iterator<char>());

    // Check for YAML frontmatter (starts with "---")
    if (content.size() < 3 || content.substr(0, 3) != "---") {
      // No frontmatter — treat entire content as body
      out.body = content;
      return true;
    }

    // Find closing "---"
    size_t end_pos = content.find("\n---", 3);
    if (end_pos == std::string::npos) {
      out.body = content;
      return true;
    }

    std::string frontmatter = content.substr(3, end_pos - 3);
    // Body starts after the closing "---\n"
    size_t body_start = end_pos + 4;  // skip "\n---"
    if (body_start < content.size() && content[body_start] == '\n') {
      body_start++;
    }
    if (body_start < content.size() && content[body_start] == '\r') {
      body_start++;
    }
    if (body_start < content.size() && content[body_start] == '\n') {
      body_start++;
    }
    out.body = (body_start < content.size()) ? content.substr(body_start) : "";

    // Simple YAML parsing: extract "name:" and "description:" values
    std::istringstream fm_stream(frontmatter);
    std::string line;
    while (std::getline(fm_stream, line)) {
      // Remove \r
      if (!line.empty() && line.back() == '\r') line.pop_back();
      // Trim leading whitespace
      size_t start = line.find_first_not_of(" \t");
      if (start == std::string::npos) continue;
      line = line.substr(start);

      auto extract_value = [](const std::string& l, const std::string& key) -> std::string {
        if (l.size() <= key.size()) return "";
        if (l.compare(0, key.size(), key) != 0) return "";
        std::string val = l.substr(key.size());
        // Trim whitespace
        size_t s = val.find_first_not_of(" \t");
        if (s == std::string::npos) return "";
        val = val.substr(s);
        // Remove surrounding quotes if present
        if (val.size() >= 2 &&
            ((val.front() == '"' && val.back() == '"') ||
             (val.front() == '\'' && val.back() == '\''))) {
          val = val.substr(1, val.size() - 2);
        }
        return val;
      };

      std::string v;
      if (!(v = extract_value(line, "name:")).empty()) {
        out.name = v;
      } else if (!(v = extract_value(line, "description:")).empty()) {
        out.description = v;
      }
    }

    return true;
  } catch (const std::exception& e) {
    log::error("SkillManager: failed to parse " + md_path + ": " + e.what());
    return false;
  }
}

std::string SkillManager::build_skill_index_prompt() const {
  if (skills_.empty()) return "";

  std::ostringstream ss;
  bool has_enabled = false;
  for (const auto& skill : skills_) {
    if (skill.enabled) { has_enabled = true; break; }
  }
  if (!has_enabled) return "";

  ss << "\n\n## Available Skills\n\n"
     << "IMPORTANT: When a user request matches any skill below, you MUST call `skill.read` with the skill name BEFORE attempting the task. "
     << "The skill contains the exact shell commands and instructions needed. Do NOT guess commands without loading the skill first.\n\n";

  for (const auto& skill : skills_) {
    if (!skill.enabled) continue;
    ss << "- **" << skill.name << "**: " << skill.description << "\n";
  }

  return ss.str();
}

const Skill* SkillManager::find(const std::string& name_or_id) const {
  for (const auto& s : skills_) {
    if (!s.enabled) continue;
    if (s.id == name_or_id || s.name == name_or_id) {
      return &s;
    }
  }
  return nullptr;
}

std::string SkillManager::install(const std::string& source_path) {
  fs::path src(source_path);
  if (!fs::exists(src) || !fs::is_directory(src)) {
    return "source path does not exist or is not a directory: " + source_path;
  }

  fs::path skill_md = src / "SKILL.md";
  if (!fs::exists(skill_md)) {
    return "no SKILL.md found in " + source_path;
  }

  // Derive skill id from directory name
  std::string skill_id = src.filename().string();

  fs::path dest = fs::path(installed_dir_) / skill_id;
  try {
    if (fs::exists(dest)) {
      fs::remove_all(dest);
    }
    fs::copy(src, dest, fs::copy_options::recursive | fs::copy_options::overwrite_existing);
  } catch (const std::exception& e) {
    return "failed to copy skill: " + std::string(e.what());
  }

  log::info("SkillManager: installed skill '" + skill_id + "' to " + dest.string());
  return "";
}

std::string SkillManager::install_from_content(const std::string& skill_id, const std::string& skill_md_content) {
  if (skill_id.empty()) return "skill id is empty";
  if (skill_md_content.empty()) return "SKILL.md content is empty";

  fs::path dest_dir = fs::path(installed_dir_) / skill_id;
  try {
    fs::create_directories(dest_dir);
    std::string md_path = (dest_dir / "SKILL.md").string();
    std::ofstream f(md_path);
    if (!f.is_open()) return "failed to create " + md_path;
    f << skill_md_content;
    f.close();
  } catch (const std::exception& e) {
    return "failed to write skill: " + std::string(e.what());
  }

  // Remove existing entry with same id (in case of update)
  skills_.erase(
    std::remove_if(skills_.begin(), skills_.end(),
      [&](const Skill& s) { return s.id == skill_id; }),
    skills_.end());

  // Load the newly installed skill into memory
  load_skill_dir(dest_dir.string(), false);
  load_disabled();

  log::info("SkillManager: installed skill '" + skill_id + "' from content");
  return "";
}

bool SkillManager::remove(const std::string& skill_id) {
  fs::path target = fs::path(installed_dir_) / skill_id;
  if (!fs::exists(target)) {
    return false;
  }
  try {
    fs::remove_all(target);
    // Remove from in-memory list
    skills_.erase(
      std::remove_if(skills_.begin(), skills_.end(),
        [&](const Skill& s) { return s.id == skill_id; }),
      skills_.end());
    log::info("SkillManager: removed skill '" + skill_id + "'");
    return true;
  } catch (const std::exception& e) {
    log::error("SkillManager: failed to remove '" + skill_id + "': " + e.what());
    return false;
  }
}

void SkillManager::load_disabled() {
  std::string path = (fs::path(workspace_dir_) / "skills" / "disabled.json").string();
  if (!fs::exists(path)) return;
  try {
    std::ifstream f(path);
    if (!f.is_open()) return;
    nlohmann::json j = nlohmann::json::parse(f);
    if (!j.is_array()) return;
    std::set<std::string> disabled_ids;
    for (const auto& item : j) {
      if (item.is_string()) disabled_ids.insert(item.get<std::string>());
    }
    for (auto& skill : skills_) {
      if (disabled_ids.count(skill.id)) {
        skill.enabled = false;
      }
    }
  } catch (const std::exception& e) {
    log::warn("SkillManager: failed to read disabled.json: " + std::string(e.what()));
  }
}

void SkillManager::save_disabled() const {
  nlohmann::json arr = nlohmann::json::array();
  for (const auto& skill : skills_) {
    if (!skill.enabled) arr.push_back(skill.id);
  }
  std::string dir = (fs::path(workspace_dir_) / "skills").string();
  try {
    fs::create_directories(dir);
    std::string path = (fs::path(dir) / "disabled.json").string();
    std::ofstream f(path);
    if (f.is_open()) {
      f << arr.dump(2);
    }
  } catch (const std::exception& e) {
    log::error("SkillManager: failed to save disabled.json: " + std::string(e.what()));
  }
}

bool SkillManager::enable(const std::string& skill_id) {
  for (auto& s : skills_) {
    if (s.id == skill_id || s.name == skill_id) {
      if (s.enabled) return false;
      s.enabled = true;
      save_disabled();
      log::info("SkillManager: enabled skill '" + s.id + "'");
      return true;
    }
  }
  return false;
}

bool SkillManager::disable(const std::string& skill_id) {
  for (auto& s : skills_) {
    if (s.id == skill_id || s.name == skill_id) {
      if (!s.enabled) return false;
      s.enabled = false;
      save_disabled();
      log::info("SkillManager: disabled skill '" + s.id + "'");
      return true;
    }
  }
  return false;
}

// --- Global singleton ---

static std::unique_ptr<SkillManager> g_instance;

void init_global(const std::string& workspace_dir) {
  g_instance = std::make_unique<SkillManager>(workspace_dir);
  g_instance->load_all();
}

SkillManager* instance() {
  return g_instance.get();
}

}  // namespace skills
}  // namespace hiclaw
