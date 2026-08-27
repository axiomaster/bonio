/**
 * IlinkHttpClient — personal WeChat bot HTTP client.
 * Node.js port of hiclaw's ilink_http_client.cpp.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import http from 'node:http';
import https from 'node:https';

const CHANNEL_VERSION = '2.0.0';
const POLL_INTERVAL_MS = 1500;

export class IlinkHttpClient {
  constructor(token, baseUrl, stateDir, onMessage, log = () => {}) {
    this.token = token;
    this.baseUrl = baseUrl;
    this.stateDir = stateDir;
    this.onMessage = onMessage;
    this.log = log;
    this.running = false;
    this.cursor = '';
    this.contextTokens = new Map();
    this.pollTimer = null;
    this.sessionExpiredPauseUntil = 0;
    try { mkdirSync(stateDir, { recursive: true }); } catch { /* ignore */ }
    this.loadCursor();
  }

  cursorFile() {
    return join(this.stateDir, 'get_updates.buf');
  }

  loadCursor() {
    try {
      const raw = readFileSync(this.cursorFile(), 'utf8');
      this.cursor = raw.trim();
    } catch { this.cursor = ''; }
  }

  saveCursor(cursor) {
    try { writeFileSync(this.cursorFile(), cursor); } catch { /* ignore */ }
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
          try { parsed = JSON.parse(text); } catch { /* ignore */ }
          resolve({ retCode: parsed.ret ?? 0, errCode: parsed.errcode ?? 0, body: parsed });
        });
      });
      req.on('error', (e) => {
        this.log('[ilink] post ' + path + ' failed: ' + (e instanceof Error ? e.message : String(e)));
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
    if (this.running) return;
    this.running = true;
    this.log('[ilink] starting poll loop, base=' + this.baseUrl);
    this.pollTimer = setInterval(() => { void this.poll(); }, POLL_INTERVAL_MS);
    void this.poll();
  }

  stop() {
    this.running = false;
    if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
  }

  async poll() {
    if (!this.running) return;
    if (Date.now() < this.sessionExpiredPauseUntil) return;

    const body = { base_info: { channel_version: CHANNEL_VERSION } };
    if (this.cursor) body.get_updates_buf = this.cursor;

    const res = await this.post('/ilink/bot/getupdates', body);
    if (!res) return;

    if (res.errCode === -14) {
      this.log('[ilink] session expired (errcode=-14), pausing 1 hour');
      this.sessionExpiredPauseUntil = Date.now() + 3600000;
      return;
    }
    if (res.retCode !== 0) return;

    const nextCursor = res.body.get_updates_buf || '';
    if (nextCursor) { this.cursor = nextCursor; this.saveCursor(nextCursor); }

    const msgs = res.body.msgs;
    if (!Array.isArray(msgs)) return;

    for (const m of msgs) {
      const msg = {
        messageId: String(m.message_id ?? ''),
        seq: String(m.seq ?? ''),
        fromUserId: m.from_user_id || '',
        toUserId: m.to_user_id || '',
        messageType: m.message_type ?? 0,
        contextToken: m.context_token || '',
        content: this.extractText(m.item_list),
      };
      if (msg.contextToken && msg.fromUserId) {
        this.contextTokens.set(msg.fromUserId, msg.contextToken);
      }
      this.onMessage(msg);
    }
  }

  extractText(itemList) {
    if (!Array.isArray(itemList)) return '';
    const parts = [];
    for (const item of itemList) {
      if (item.type === 1 && item.content) parts.push(item.content);
      else if (item.type === 1 && item.value) parts.push(String(item.value));
      else if (item.content) parts.push(item.content);
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
        { type: 1, content: content },
      ],
    };
    const res = await this.post('/ilink/bot/sendmessage', body);
    return res !== null && res.retCode === 0;
  }
}
