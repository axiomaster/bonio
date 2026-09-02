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

const CHANNEL_VERSION = 'bonio-weixin/1.0';
const POLL_INTERVAL_MS = 1500;
const MAX_CHUNK_BYTES = 3800;
const MAX_SEND_RETRIES = 3;

export interface IlinkInboundMessage {
  messageId: string;
  seq: string;
  fromUserId: string;
  toUserId: string;
  messageType: number;
  contextToken: string;
  content: string;
}

interface IlinkResponse {
  retCode: number;
  errCode: number;
  body: Record<string, unknown>;
}

type Log = (message: string) => void;
type OnMessage = (msg: IlinkInboundMessage) => void;

export class IlinkHttpClient {
  private token: string;
  private baseUrl: string;
  private stateDir: string;
  private readonly onMessage: OnMessage;
  private readonly log: Log;
  private running = false;
  private inflight = false;
  private cursor = '';
  private contextTokens = new Map<string, string>();
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private sessionExpiredPauseUntil = 0;
  /**
   * Random per-instance UIN. hiclaw's ilink_http_client.cpp sends a random
   * 4-byte base64 value here; without it (and AuthorizationType) the server
   * rejects even freshly bound tokens with errcode=-14.
   */
  private readonly xWechatUin: string;

  constructor(token: string, baseUrl: string, stateDir: string, onMessage: OnMessage, log: Log = () => {}) {
    this.token = token;
    this.baseUrl = baseUrl;
    this.stateDir = stateDir;
    this.onMessage = onMessage;
    this.log = log;
    this.xWechatUin = Buffer.from(Array.from({ length: 4 }, () => Math.floor(Math.random() * 256))).toString('base64');
    try { mkdirSync(stateDir, { recursive: true }); } catch { /* ignore */ }
    this.loadCursor();
    this.loadContextTokens();
  }

  private cursorFile(): string {
    return join(this.stateDir, 'get_updates.buf');
  }

  private loadCursor(): void {
    try {
      this.cursor = readFileSync(this.cursorFile(), 'utf8').trim();
    } catch { this.cursor = ''; }
  }

  private saveCursor(cursor: string): void {
    try { writeFileSync(this.cursorFile(), cursor); } catch { /* ignore */ }
  }

  private contextTokensFile(): string {
    return join(this.stateDir, 'context_tokens.json');
  }

  private loadContextTokens(): void {
    try {
      const raw = JSON.parse(readFileSync(this.contextTokensFile(), 'utf8')) as Record<string, unknown>;
      for (const [k, v] of Object.entries(raw)) {
        if (typeof v === 'string' && v) this.contextTokens.set(k, v);
      }
    } catch { /* ignore */ }
  }

  private saveContextTokens(): void {
    try {
      const obj: Record<string, string> = {};
      for (const [k, v] of this.contextTokens) obj[k] = v;
      writeFileSync(this.contextTokensFile(), JSON.stringify(obj, null, 2));
    } catch { /* ignore */ }
  }

  private post(path: string, body: Record<string, unknown>): Promise<IlinkResponse | null> {
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
          // Both auth headers are required (see hiclaw ilink_http_client.cpp);
          // omitting AuthorizationType yields errcode=-14 even for fresh tokens.
          'AuthorizationType': 'ilink_bot_token',
          'Authorization': 'Bearer ' + this.token,
          'X-WECHAT-UIN': this.xWechatUin,
        },
        timeout: 20000,
      }, (res) => {
        let text = '';
        res.on('data', (c: Buffer) => { text += c; });
        res.on('end', () => {
          let parsed: Record<string, unknown> = {};
          try { parsed = JSON.parse(text) as Record<string, unknown>; } catch { /* ignore */ }
          resolve({
            retCode: typeof parsed['ret'] === 'number' ? parsed['ret'] : 0,
            errCode: typeof parsed['errcode'] === 'number' ? parsed['errcode'] : 0,
            body: parsed,
          });
        });
      });
      req.on('error', (e: Error) => {
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

  start(): void {
    if (this.running) return;
    this.running = true;
    this.log('[ilink] starting poll loop, base=' + this.baseUrl);
    this.pollTimer = setInterval(() => { void this.poll(); }, POLL_INTERVAL_MS);
    void this.poll();
  }

  stop(): void {
    this.running = false;
    if (this.pollTimer) { clearInterval(this.pollTimer); this.pollTimer = null; }
  }

  private async poll(): Promise<void> {
    if (!this.running || this.inflight) return;
    if (Date.now() < this.sessionExpiredPauseUntil) return;

    this.inflight = true;
    try {
      const body: Record<string, unknown> = { base_info: { channel_version: CHANNEL_VERSION } };
      if (this.cursor) body['get_updates_buf'] = this.cursor;

      const res = await this.post('/ilink/bot/getupdates', body);
      if (!res) return;

      if (res.errCode === -14) {
        this.log('[ilink] session expired (errcode=-14), pausing 1 hour');
        this.sessionExpiredPauseUntil = Date.now() + 3600000;
        return;
      }
      if (res.retCode !== 0) return;

      const nextCursor = res.body['get_updates_buf'];
      if (typeof nextCursor === 'string' && nextCursor) {
        this.cursor = nextCursor;
        this.saveCursor(nextCursor);
      }

      const msgs = res.body['msgs'];
      if (!Array.isArray(msgs)) return;

      for (const raw of msgs) {
        if (!raw || typeof raw !== 'object') continue;
        const m = raw as Record<string, unknown>;
        const msg: IlinkInboundMessage = {
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
          this.saveContextTokens();
        }
        this.onMessage(msg);
      }
    } finally {
      this.inflight = false;
    }
  }

  private extractText(itemList: unknown): string {
    // Mirrors hiclaw extract_text: text lives in item.text_item.text, voice
    // transcriptions in item.voice_item.text; media items become placeholders.
    if (!Array.isArray(itemList)) return '';
    const parts: string[] = [];
    for (const itemRaw of itemList) {
      if (!itemRaw || typeof itemRaw !== 'object') continue;
      const item = itemRaw as Record<string, unknown>;
      const type = typeof item['type'] === 'number' ? item['type'] : 0;
      if (type === 1 || type === 3) {
        const holder = (type === 1 ? item['text_item'] : item['voice_item']) as Record<string, unknown> | undefined;
        const text = holder && typeof holder['text'] === 'string' ? holder['text'] : '';
        if (text) parts.push(text);
      } else if (type === 2) {
        parts.push('[image]');
      } else if (type === 4) {
        parts.push('[file]');
      } else if (type === 5) {
        parts.push('[video]');
      }
    }
    return parts.join('\n');
  }

  private generateClientId(): string {
    const bytes = Array.from({ length: 8 }, () => Math.floor(Math.random() * 256));
    return 'cc-' + Buffer.from(bytes).toString('hex');
  }

  async sendMessage(toUserId: string, content: string): Promise<boolean> {
    // Chunk to 3800 chars without splitting mid-UTF8, retry ret=-2 (hiclaw parity).
    const chunks: string[] = [];
    const buf = Buffer.from(content, 'utf8');
    for (let offset = 0; offset < buf.length;) {
      let len = Math.min(buf.length - offset, MAX_CHUNK_BYTES);
      while (len > 0 && offset + len < buf.length && (buf[offset + len] & 0xC0) === 0x80) len--;
      if (len === 0) len = 1;
      chunks.push(buf.subarray(offset, offset + len).toString('utf8'));
      offset += len;
    }

    const contextToken = this.contextTokens.get(toUserId) || '';
    for (let i = 0; i < chunks.length; i++) {
      const msg: Record<string, unknown> = {
        from_user_id: '',
        to_user_id: toUserId,
        client_id: this.generateClientId(),
        message_type: 2,
        message_state: 2,
        item_list: [{ type: 1, text_item: { text: chunks[i] } }],
      };
      if (contextToken) msg['context_token'] = contextToken;
      const body: Record<string, unknown> = { msg, base_info: { channel_version: CHANNEL_VERSION } };

      let ok = false;
      for (let attempt = 0; attempt < MAX_SEND_RETRIES; attempt++) {
        const res = await this.post('/ilink/bot/sendmessage', body);
        if (!res) {
          if (attempt < MAX_SEND_RETRIES - 1) await this.delay(500);
          continue;
        }
        if (res.retCode === -2) {
          this.log('[ilink] sendMessage ret=-2, retry ' + (attempt + 1));
          await this.delay(500);
          continue;
        }
        if (res.errCode === -14) {
          this.log('[ilink] session expired during send');
          return false;
        }
        ok = true;
        break;
      }
      if (!ok) {
        this.log('[ilink] failed to send chunk ' + (i + 1) + ' to ' + toUserId);
        return false;
      }
      if (i < chunks.length - 1) await this.delay(100);
    }
    return true;
  }

  private delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }
}
