import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export interface BonioMemo {
  id: string;
  title: string;
  content: string;
  source: string;
  createdAt: number;
  tags?: string[];
  sourceApp?: string;
  pageTitle?: string;
  pageLink?: string;
}

export interface SaveMemoInput {
  title: string;
  content: string;
  source?: string;
  tags?: string[];
  sourceApp?: string;
  pageTitle?: string;
  pageLink?: string;
}

function memoDir(): string {
  const home = process.env.DSH_HOME || process.env.HOME || '/data/local/home';
  return path.join(home === '/root' ? '/data/local/home' : home, '.bonio', 'memos');
}

function text(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function tags(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const unique = new Set<string>();
  for (const tag of value) {
    const normalized = text(tag);
    if (normalized) unique.add(normalized.replace(/^#+/, ''));
  }
  return unique.size > 0 ? [...unique].slice(0, 3) : undefined;
}

function normalizeMemo(value: unknown): BonioMemo | null {
  if (!value || typeof value !== 'object') return null;
  const raw = value as Record<string, unknown>;
  const id = text(raw.id);
  const title = text(raw.title);
  const content = text(raw.content);
  if (!id || !title || !content) return null;
  const createdAt = typeof raw.createdAt === 'number' && Number.isFinite(raw.createdAt)
    ? raw.createdAt
    : Number(id) || 0;
  return {
    id,
    title,
    content,
    source: text(raw.source) || 'dsh',
    createdAt,
    tags: tags(raw.tags),
    sourceApp: text(raw.sourceApp),
    pageTitle: text(raw.pageTitle),
    pageLink: text(raw.pageLink),
  };
}

function memoPath(id: string): string | null {
  return /^[A-Za-z0-9_-]+$/.test(id) ? path.join(memoDir(), `${id}.json`) : null;
}

export async function saveMemo(input: SaveMemoInput): Promise<BonioMemo> {
  const title = text(input.title);
  const content = text(input.content);
  if (!title || !content) throw new Error('memo title and content are required');

  const memo: BonioMemo = {
    id: `${Date.now()}-${randomUUID().slice(0, 8)}`,
    title,
    content,
    source: text(input.source) || 'dsh',
    createdAt: Date.now(),
    tags: tags(input.tags),
    sourceApp: text(input.sourceApp),
    pageTitle: text(input.pageTitle),
    pageLink: text(input.pageLink),
  };
  await fs.mkdir(memoDir(), { recursive: true });
  await fs.writeFile(path.join(memoDir(), `${memo.id}.json`), JSON.stringify(memo, null, 2), 'utf8');
  return memo;
}

export async function listMemos(limit = 100): Promise<BonioMemo[]> {
  let files: string[] = [];
  try {
    files = await fs.readdir(memoDir());
  } catch {
    return [];
  }
  const memos: BonioMemo[] = [];
  for (const file of files) {
    if (!file.endsWith('.json')) continue;
    try {
      const parsed = normalizeMemo(JSON.parse(await fs.readFile(path.join(memoDir(), file), 'utf8')));
      if (parsed) memos.push(parsed);
    } catch {
      // A partially written or legacy-invalid file must not hide other memories.
    }
  }
  return memos.sort((a, b) => b.createdAt - a.createdAt).slice(0, Math.max(1, Math.min(limit, 200)));
}

export async function getMemo(id: string): Promise<BonioMemo | null> {
  const target = memoPath(id);
  if (!target) return null;
  try {
    return normalizeMemo(JSON.parse(await fs.readFile(target, 'utf8')));
  } catch {
    return null;
  }
}

export async function deleteMemo(id: string): Promise<boolean> {
  const target = memoPath(id);
  if (!target) return false;
  try {
    await fs.unlink(target);
    return true;
  } catch (error: unknown) {
    if ((error as { code?: string }).code === 'ENOENT') return false;
    throw error;
  }
}
