import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
function memoDir() {
    const home = process.env.DSH_HOME || process.env.HOME || '/data/local/home';
    return path.join(home === '/root' ? '/data/local/home' : home, '.bonio', 'memos');
}
function text(value) {
    return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}
function tags(value) {
    if (!Array.isArray(value))
        return undefined;
    const unique = new Set();
    for (const tag of value) {
        const normalized = text(tag);
        if (normalized)
            unique.add(normalized.replace(/^#+/, ''));
    }
    return unique.size > 0 ? [...unique].slice(0, 3) : undefined;
}
function normalizeMemo(value) {
    if (!value || typeof value !== 'object')
        return null;
    const raw = value;
    const id = text(raw.id);
    const title = text(raw.title);
    const content = text(raw.content);
    if (!id || !title || !content)
        return null;
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
function memoPath(id) {
    return /^[A-Za-z0-9_-]+$/.test(id) ? path.join(memoDir(), `${id}.json`) : null;
}
export async function saveMemo(input) {
    const title = text(input.title);
    const content = text(input.content);
    if (!title || !content)
        throw new Error('memo title and content are required');
    const memo = {
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
export async function listMemos(limit = 100) {
    let files = [];
    try {
        files = await fs.readdir(memoDir());
    }
    catch {
        return [];
    }
    const memos = [];
    for (const file of files) {
        if (!file.endsWith('.json'))
            continue;
        try {
            const parsed = normalizeMemo(JSON.parse(await fs.readFile(path.join(memoDir(), file), 'utf8')));
            if (parsed)
                memos.push(parsed);
        }
        catch {
            // A partially written or legacy-invalid file must not hide other memories.
        }
    }
    return memos.sort((a, b) => b.createdAt - a.createdAt).slice(0, Math.max(1, Math.min(limit, 200)));
}
export async function getMemo(id) {
    const target = memoPath(id);
    if (!target)
        return null;
    try {
        return normalizeMemo(JSON.parse(await fs.readFile(target, 'utf8')));
    }
    catch {
        return null;
    }
}
export async function deleteMemo(id) {
    const target = memoPath(id);
    if (!target)
        return false;
    try {
        await fs.unlink(target);
        return true;
    }
    catch (error) {
        if (error.code === 'ENOENT')
            return false;
        throw error;
    }
}
