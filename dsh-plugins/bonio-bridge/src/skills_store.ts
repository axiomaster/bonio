/**
 * skills_store — scan SKILL.md bundles and manage enable/disable state.
 *
 * Mirrors hiclaw's SkillManager layout: <root>/skills/{builtin,installed}/<id>/SKILL.md
 * plus flat <root>/skills/<id>/SKILL.md bundles, and the DSH skill roots
 * (.dsh/skills and <dshHome>/skills). Frontmatter: YAML 'name' and 'description'.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

export interface SkillInfo {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  builtin: boolean;
}

function home(): string {
  const h = process.env.DSH_HOME || process.env.HOME || os.homedir();
  return h === '/root' ? '/data/local/home' : h;
}

/** Candidate skill roots, most specific first. */
function skillRoots(): string[] {
  const roots: string[] = [];
  // cwd-relative: bonio repo (skills/, server/conf/skills), dsh project root (.dsh/skills)
  const cwd = process.cwd();
  if (cwd) {
    roots.push(path.join(cwd, 'skills'));
    roots.push(path.join(cwd, 'server', 'conf', 'skills'));
    roots.push(path.join(cwd, '.dsh', 'skills'));
  }
  const h = home();
  roots.push(path.join(h, '.dsh', 'skills'));
  return roots;
}

/** Parse a SKILL.md file, returning frontmatter name/description or null. */
async function parseSkillMd(filePath: string): Promise<{ name: string; description: string } | null> {
  let raw: string;
  try {
    raw = await fs.readFile(filePath, 'utf8');
  } catch {
    return null;
  }
  const match = /^---\r?\n([\s\S]*?)\r?\n---/.exec(raw);
  if (!match) return null;
  const fm = match[1];
  const nameMatch = /^name:\s*(.+)$/m.exec(fm);
  const descMatch = /^description:\s*(.+)$/m.exec(fm);
  const strip = (s: string | undefined): string => (s ?? '').trim().replace(/^["']|["']$/g, '');
  const name = strip(nameMatch?.[1]);
  const description = strip(descMatch?.[1]);
  if (!name) return null;
  return { name, description };
}

/** Scan one root for <id>/SKILL.md bundles, flagging nested builtin/installed dirs. */
async function scanRoot(root: string, out: Map<string, SkillInfo>): Promise<void> {
  let entries: string[];
  try {
    entries = await fs.readdir(root);
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(root, entry);
    let stat: { isDirectory(): boolean } | null = null;
    try { stat = await fs.stat(full); } catch { continue; }
    if (!stat?.isDirectory()) continue;
    // nested layout: builtin/<id>, installed/<id>
    if (entry === 'builtin' || entry === 'installed') {
      await scanNested(full, entry === 'builtin', out);
      continue;
    }
    const md = path.join(full, 'SKILL.md');
    const parsed = await parseSkillMd(md);
    if (!parsed) continue;
    const id = entry;
    const existing = out.get(id);
    const builtin = existing?.builtin ?? false;
    if (!existing) {
      out.set(id, { id, name: parsed.name, description: parsed.description, enabled: true, builtin });
    } else if (parsed.name && !existing.name) {
      existing.name = parsed.name;
      existing.description = parsed.description;
    }
  }
}

async function scanNested(dir: string, builtin: boolean, out: Map<string, SkillInfo>): Promise<void> {
  let entries: string[];
  try {
    entries = await fs.readdir(dir);
  } catch {
    return;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry);
    let stat: { isDirectory(): boolean } | null = null;
    try { stat = await fs.stat(full); } catch { continue; }
    if (!stat?.isDirectory()) continue;
    const md = path.join(full, 'SKILL.md');
    const parsed = await parseSkillMd(md);
    if (!parsed) continue;
    out.set(entry, { id: entry, name: parsed.name, description: parsed.description, enabled: true, builtin });
  }
}

function statePath(): string {
  return path.join(home(), '.bonio', 'bridge-skills.json');
}

async function loadDisabled(): Promise<Set<string>> {
  try {
    const raw = await fs.readFile(statePath(), 'utf8');
    const parsed = JSON.parse(raw) as { disabled?: string[] };
    return new Set(Array.isArray(parsed?.disabled) ? parsed.disabled : []);
  } catch {
    return new Set();
  }
}

async function saveDisabled(disabled: Set<string>): Promise<void> {
  try {
    const dir = path.dirname(statePath());
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(statePath(), JSON.stringify({ disabled: [...disabled] }, null, 2), 'utf8');
  } catch {
    // non-fatal: state just won't persist across restarts
  }
}

export async function listSkills(): Promise<SkillInfo[]> {
  const map = new Map<string, SkillInfo>();
  for (const root of skillRoots()) {
    await scanRoot(root, map);
  }
  const disabled = await loadDisabled();
  return [...map.values()]
    .map((s) => ({ ...s, enabled: !disabled.has(s.id) }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

export async function setSkillEnabled(id: string, enabled: boolean): Promise<boolean> {
  const skills = await listSkills();
  if (!skills.some((s) => s.id === id)) return false;
  const disabled = await loadDisabled();
  if (enabled) {
    const before = disabled.size;
    disabled.delete(id);
    if (disabled.size === before) return false; // already in requested state
  } else {
    if (disabled.has(id)) return false; // already in requested state
    disabled.add(id);
  }
  await saveDisabled(disabled);
  return true;
}