import { randomUUID } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
function memoDir() {
    const home = process.env.DSH_HOME || process.env.HOME || '/data/local/home';
    return path.join(home === '/root' ? '/data/local/home' : home, '.bonio', 'memos');
}
function memoDirectory(id) {
    return /^[A-Za-z0-9_-]+$/.test(id) ? path.join(memoDir(), id) : null;
}
function memoDataPath(id) {
    const directory = memoDirectory(id);
    return directory ? path.join(directory, 'memo.json') : null;
}
function memoCoverPath(id) {
    const directory = memoDirectory(id);
    return directory ? path.join(directory, 'cover.jpg') : null;
}
function memoOriginalImagePath(id) {
    const directory = memoDirectory(id);
    return directory ? path.join(directory, 'screenshot.png') : null;
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
    // Up to three content tags plus one behavior tag are shown and filterable.
    return unique.size > 0 ? [...unique].slice(0, 4) : undefined;
}
function coverImage(value) {
    if (typeof value !== 'string')
        return undefined;
    const normalized = value.trim().replace(/^data:image\/(?:jpeg|jpg|png|webp|gif);base64,/i, '');
    return normalized ? normalized : undefined;
}
function imageMimeType(value) {
    return value === 'image/jpeg' || value === 'image/png' || value === 'image/webp' ? value : undefined;
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
        coverImage: coverImage(raw.coverImage),
        originalImage: coverImage(raw.originalImage),
        originalImageMimeType: imageMimeType(raw.originalImageMimeType),
    };
}
function storedMemo(memo) {
    const { coverImage: _coverImage, originalImage: _originalImage, ...metadata } = memo;
    return metadata;
}
async function readMemo(id, includeOriginalImage = true) {
    const dataPath = memoDataPath(id);
    const coverPath = memoCoverPath(id);
    const originalImagePath = memoOriginalImagePath(id);
    if (!dataPath || !coverPath || !originalImagePath)
        return null;
    try {
        const memo = normalizeMemo(JSON.parse(await fs.readFile(dataPath, 'utf8')));
        if (!memo)
            return null;
        try {
            memo.coverImage = (await fs.readFile(coverPath)).toString('base64');
        }
        catch {
            // A cover is optional; a missing/corrupt cover must not hide the memo.
        }
        if (includeOriginalImage) {
            try {
                memo.originalImage = (await fs.readFile(originalImagePath)).toString('base64');
            }
            catch {
                // Legacy memories do not have a full-resolution screenshot.
            }
        }
        return memo;
    }
    catch {
        return null;
    }
}
async function writeMemo(memo) {
    const directory = memoDirectory(memo.id);
    const dataPath = memoDataPath(memo.id);
    const coverPath = memoCoverPath(memo.id);
    const originalImagePath = memoOriginalImagePath(memo.id);
    if (!directory || !dataPath || !coverPath || !originalImagePath)
        throw new Error('invalid memo id');
    await fs.mkdir(directory, { recursive: true });
    await fs.writeFile(dataPath, JSON.stringify(storedMemo(memo), null, 2), 'utf8');
    const cover = coverImage(memo.coverImage);
    if (cover)
        await fs.writeFile(coverPath, Buffer.from(cover, 'base64'));
    const originalImage = coverImage(memo.originalImage);
    if (originalImage)
        await fs.writeFile(originalImagePath, Buffer.from(originalImage, 'base64'));
}
/** Move legacy <id>.json records into the per-memo directory layout. */
async function migrateLegacyMemos() {
    let entries = [];
    try {
        entries = await fs.readdir(memoDir());
    }
    catch {
        return;
    }
    for (const entry of entries) {
        if (!entry.endsWith('.json'))
            continue;
        const legacyPath = path.join(memoDir(), entry);
        try {
            const memo = normalizeMemo(JSON.parse(await fs.readFile(legacyPath, 'utf8')));
            if (!memo)
                continue;
            await writeMemo(memo);
            await fs.unlink(legacyPath);
        }
        catch {
            // Leave unreadable legacy files untouched for manual recovery.
        }
    }
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
        coverImage: coverImage(input.coverImage),
        originalImage: coverImage(input.originalImage),
        originalImageMimeType: imageMimeType(input.originalImageMimeType),
    };
    await fs.mkdir(memoDir(), { recursive: true });
    await writeMemo(memo);
    return memo;
}
export async function listMemos(limit = 100, query) {
    await migrateLegacyMemos();
    let entries = [];
    try {
        entries = await fs.readdir(memoDir());
    }
    catch {
        return [];
    }
    const needle = typeof query === 'string' ? query.trim().toLowerCase() : '';
    const memos = [];
    for (const entry of entries) {
        const memo = await readMemo(entry, false);
        if (!memo)
            continue;
        if (needle) {
            const haystack = [memo.title, memo.content, ...(memo.tags ?? []), memo.pageTitle ?? '']
                .join('\n').toLowerCase();
            // Split the query on whitespace; every token must match somewhere
            // (title/content/tags), so "瑞幸 电话" finds memos containing both.
            const tokens = needle.split(/\s+/).filter(Boolean);
            if (!tokens.every((token) => haystack.includes(token)))
                continue;
        }
        memos.push(memo);
    }
    return memos.sort((a, b) => b.createdAt - a.createdAt).slice(0, Math.max(1, Math.min(limit, 200)));
}
export async function getMemo(id) {
    await migrateLegacyMemos();
    return readMemo(id);
}
export async function deleteMemo(id) {
    const directory = memoDirectory(id);
    if (!directory)
        return false;
    try {
        await fs.rm(directory, { recursive: true });
        return true;
    }
    catch (error) {
        if (error.code === 'ENOENT')
            return false;
        throw error;
    }
}
