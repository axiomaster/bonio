/**
 * IlinkHttpClient — personal WeChat (ilink) bot HTTP client for the bridge.
 * Ported from bonio-wechat/src/ilink.ts (itself a Node.js port of hiclaw's
 * ilink_http_client.cpp): long-polls /ilink/bot/getupdates and replies via
 * /ilink/bot/sendmessage with the sender's cached context_token.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import http from 'node:http';
import https from 'node:https';
const CHANNEL_VERSION = '2.0.0';
const POLL_INTERVAL_MS = 1500;
export class IlinkHttpClient {
    token;
    baseUrl;
    stateDir;
    onMessage;
    log;
    running = false;
    inflight = false;
    cursor = '';
    contextTokens = new Map();
    pollTimer = null;
    sessionExpiredPauseUntil = 0;
    constructor(token, baseUrl, stateDir, onMessage, log = () => { }) {
        this.token = token;
        this.baseUrl = baseUrl;
        this.stateDir = stateDir;
        this.onMessage = onMessage;
        this.log = log;
        try {
            mkdirSync(stateDir, { recursive: true });
        }
        catch { /* ignore */ }
        this.loadCursor();
    }
    cursorFile() {
        return join(this.stateDir, 'get_updates.buf');
    }
    loadCursor() {
        try {
            this.cursor = readFileSync(this.cursorFile(), 'utf8').trim();
        }
        catch {
            this.cursor = '';
        }
    }
    saveCursor(cursor) {
        try {
            writeFileSync(this.cursorFile(), cursor);
        }
        catch { /* ignore */ }
    }
    post(path, body) {
        const url = new URL(this.baseUrl + path);
        const lib = url.protocol === 'https:' ? https : http;
        const data = JSON.stringify(body);
        return new Promise((resolve) => {
            const req = lib.request({
                hostname: url.hostname,
                port: url.port || (url.protocol === 'https:' ? 443 : 80),
                path: url.pathname + url.search,
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(data),
                    'Authorization': 'Bearer ' + this.token,
                },
                timeout: 20000,
            }, (res) => {
                let text = '';
                res.on('data', (c) => { text += c; });
                res.on('end', () => {
                    let parsed = {};
                    try {
                        parsed = JSON.parse(text);
                    }
                    catch { /* ignore */ }
                    resolve({
                        retCode: typeof parsed['ret'] === 'number' ? parsed['ret'] : 0,
                        errCode: typeof parsed['errcode'] === 'number' ? parsed['errcode'] : 0,
                        body: parsed,
                    });
                });
            });
            req.on('error', (e) => {
                this.log('[ilink] post ' + path + ' failed: ' + e.message);
                resolve(null);
            });
            req.on('timeout', () => {
                req.destroy();
                this.log('[ilink] post ' + path + ' timed out');
                resolve(null);
            });
            req.write(data);
            req.end();
        });
    }
    start() {
        if (this.running)
            return;
        this.running = true;
        this.log('[ilink] starting poll loop, base=' + this.baseUrl);
        this.pollTimer = setInterval(() => { void this.poll(); }, POLL_INTERVAL_MS);
        void this.poll();
    }
    stop() {
        this.running = false;
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }
    async poll() {
        if (!this.running || this.inflight)
            return;
        if (Date.now() < this.sessionExpiredPauseUntil)
            return;
        this.inflight = true;
        try {
            const body = { base_info: { channel_version: CHANNEL_VERSION } };
            if (this.cursor)
                body['get_updates_buf'] = this.cursor;
            const res = await this.post('/ilink/bot/getupdates', body);
            if (!res)
                return;
            if (res.errCode === -14) {
                this.log('[ilink] session expired (errcode=-14), pausing 1 hour');
                this.sessionExpiredPauseUntil = Date.now() + 3600000;
                return;
            }
            if (res.retCode !== 0)
                return;
            const nextCursor = res.body['get_updates_buf'];
            if (typeof nextCursor === 'string' && nextCursor) {
                this.cursor = nextCursor;
                this.saveCursor(nextCursor);
            }
            const msgs = res.body['msgs'];
            if (!Array.isArray(msgs))
                return;
            for (const raw of msgs) {
                if (!raw || typeof raw !== 'object')
                    continue;
                const m = raw;
                const msg = {
                    messageId: String(m['message_id'] ?? ''),
                    seq: String(m['seq'] ?? ''),
                    fromUserId: typeof m['from_user_id'] === 'string' ? m['from_user_id'] : '',
                    toUserId: typeof m['to_user_id'] === 'string' ? m['to_user_id'] : '',
                    messageType: typeof m['message_type'] === 'number' ? m['message_type'] : 0,
                    contextToken: typeof m['context_token'] === 'string' ? m['context_token'] : '',
                    content: this.extractText(m['item_list']),
                };
                if (msg.contextToken && msg.fromUserId) {
                    this.contextTokens.set(msg.fromUserId, msg.contextToken);
                }
                this.onMessage(msg);
            }
        }
        finally {
            this.inflight = false;
        }
    }
    extractText(itemList) {
        if (!Array.isArray(itemList))
            return '';
        const parts = [];
        for (const itemRaw of itemList) {
            if (!itemRaw || typeof itemRaw !== 'object')
                continue;
            const item = itemRaw;
            if (item['type'] === 1 && typeof item['content'] === 'string' && item['content'])
                parts.push(item['content']);
            else if (item['type'] === 1 && item['value'] !== undefined)
                parts.push(String(item['value']));
            else if (typeof item['content'] === 'string' && item['content'])
                parts.push(item['content']);
        }
        return parts.join(' ');
    }
    async sendMessage(toUserId, content) {
        const contextToken = this.contextTokens.get(toUserId) || '';
        const body = {
            base_info: { channel_version: CHANNEL_VERSION, context_token: contextToken },
            to_user_id: toUserId,
            msg_type: 1,
            content: [
                { type: 1, content },
            ],
        };
        const res = await this.post('/ilink/bot/sendmessage', body);
        return res !== null && res.retCode === 0;
    }
}
