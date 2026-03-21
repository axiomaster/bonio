#ifndef HICLAW_SKILLS_SKILL_MANAGER_HPP
#define HICLAW_SKILLS_SKILL_MANAGER_HPP

#include <string>
#include <vector>
#include <map>

namespace hiclaw {
namespace skills {

/**
 * A skill loaded from a SKILL.md file.
 * Compatible with Claude Code / OpenClaw skill format:
 *   - YAML frontmatter: name, description
 *   - Markdown body: full agent instructions
 */
struct Skill {
  std::string id;            // directory name, e.g. "phone-use-android"
  std::string name;          // from frontmatter "name:" field
  std::string description;   // from frontmatter "description:" field
  std::string body;          // full markdown body (after frontmatter)
  bool builtin = false;
  bool enabled = true;
};

/**
 * Manages loading, installing, and querying skills.
 *
 * Directory layout under workspace:
 *   skills/
 *     builtin/          — shipped with hiclaw
 *       time-utils/
 *         SKILL.md
 *       ...
 *     installed/        — user-installed
 *       my-skill/
 *         SKILL.md
 *       ...
 */
class SkillManager {
public:
  explicit SkillManager(const std::string& workspace_dir);

  /** Load all skills from builtin/ and installed/ directories. */
  void load_all();

  /** Return the list of loaded skills. */
  const std::vector<Skill>& skills() const { return skills_; }

  /**
   * Build a lightweight skill index for the system prompt.
   * Lists only name + description per skill so the LLM can decide
   * which skill to load via skill.read (progressive disclosure L1).
   */
  std::string build_skill_index_prompt() const;

  /**
   * Get a skill by name (frontmatter name or directory id).
   * Returns nullptr if not found.
   */
  const Skill* find(const std::string& name_or_id) const;

  /**
   * Install a skill from a directory (copies to installed/).
   * The source must contain a SKILL.md.
   * Returns empty string on success, or error message.
   */
  std::string install(const std::string& source_path);

  /**
   * Install a skill from SKILL.md content (for RPC / remote install).
   * Creates installed/<skill_id>/SKILL.md with the given content.
   * Reloads the skill into the in-memory list.
   * Returns empty string on success, or error message.
   */
  std::string install_from_content(const std::string& skill_id, const std::string& skill_md_content);

  /**
   * Remove an installed skill by id (directory name).
   * Also removes it from the in-memory list.
   * Returns true if found and removed.
   */
  bool remove(const std::string& skill_id);

  /**
   * Enable a skill by id. Persists to disabled.json.
   * Returns true if the skill exists and was disabled.
   */
  bool enable(const std::string& skill_id);

  /**
   * Disable a skill by id. Persists to disabled.json.
   * Returns true if the skill exists and was enabled.
   */
  bool disable(const std::string& skill_id);

private:
  void load_disabled();
  void save_disabled() const;
  bool load_skill_dir(const std::string& dir_path, bool is_builtin);
  static bool parse_skill_md(const std::string& md_path, Skill& out);

  std::string workspace_dir_;
  std::string builtin_dir_;
  std::string installed_dir_;
  std::vector<Skill> skills_;
};

/**
 * Global singleton: load skills once, share across agent/gateway/CLI.
 * Call init() early; afterwards instance() returns the pointer.
 */
void init_global(const std::string& workspace_dir);
SkillManager* instance();

}  // namespace skills
}  // namespace hiclaw

#endif
