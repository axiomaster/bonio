/**
 * WecomWsClient — WeCom intelligent-bot WebSocket client.
 * Node.js port of hiclaw's wecom_ws_client.cpp.
 */
import WebSocket from 'ws';

const WS_ENDPOINT = process.env.WECOM_WS_ENDPOINT || 'wss://openws.work.weixin.qq.com';
const PING_INTERVAL_MS = 30000;
const REPLY_CHUNK_BYTES = 2000;

export class WecomWsClient {
  constructor(botId, botSecret, onMessage, log = () => {}) {
    this.botId = botId;
    this.endpoint = process.env.WECOM_WS_ENDPOINT || WS_ENDPOINT;
    this.botSecret = botSecret;
    this.onMessage = onMessage;
    this.log = log;
    this.ws = null;
    this.running = false;
    this.reqCounter = 0;
    this.pingTimer = null;
    this.reconnectTimer = null;
    this.backoffMs = 1000;
  }

  nextReqId(prefix) {
    this.reqCounter++;
    return prefix + '_' + Date.now() + '_' + this.reqCounter;
  }

  sendFrame(frame) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(frame));
      return true;
    }
    return false;
  }

  subscribe() {
    this.sendFrame({
      cmd: 'aibot_subscribe',
      headers: { req_id: this.nextReqId('aibot_subscribe') },
      body: { bot_id: this.botId, secret: this.botSecret },
    });
  }

  handleFrame(text) {
    try {
      const j = JSON.parse(text);
      const cmd = j.cmd || '';
      if (cmd === 'aibot_msg_callback') {
        const headers = j.headers || {};
        const reqId = headers.req_id || '';
        const body = j.body || {};
        const msgId = body.msgid || '';
        const chatId = body.chatid || '';
        const chatType = body.chattype || 'single';
        let userId = '';
        if (body.from && typeof body.from === 'object') {
          userId = body.from.userid || '';
        }
        const msgType = body.msgtype || 'text';
        let content = '';
        if (msgType === 'text' && body.text && typeof body.text === 'object') {
          content = body.text.content || '';
        } else if (msgType === 'voice' && body.voice && typeof body.voice === 'object') {
          content = body.voice.text || body.voice.content || '';
          if (!content) content = '[voice message]';
        } else if (msgType === 'image' || msgType === 'file') {
          content = '[' + msgType + ']';
        }
        this.onMessage(msgId, userId, chatId, chatType, content, reqId);
      }
    } catch (e) {
      this.log('[wecom] frame parse error: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.connect();
  }

  connect() {
    if (!this.running) return;
    this.log('[wecom] connecting to ' + this.endpoint);
    const ws = new WebSocket(this.endpoint);
    this.ws = ws;

    ws.on('open', () => {
      this.log('[wecom] connected');
      this.backoffMs = 1000;
      this.subscribe();
      this.pingTimer = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.ping();
      }, PING_INTERVAL_MS);
    });

    ws.on('message', (data) => {
      this.handleFrame(data.toString());
    });

    ws.on('close', () => {
      this.log('[wecom] connection closed');
      this.ws = null;
      if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null; }
      this.scheduleReconnect();
    });

    ws.on('error', (e) => {
      this.log('[wecom] ws error: ' + e.message);
    });
  }

  scheduleReconnect() {
    if (!this.running) return;
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.connect();
      this.backoffMs = Math.min(this.backoffMs * 2, 60000);
    }, this.backoffMs);
  }

  stop() {
    this.running = false;
    if (this.reconnectTimer) { clearTimeout(this.reconnectTimer); this.reconnectTimer = null; }
    if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null; }
    if (this.ws) { try { this.ws.close(); } catch { /* ignore */ } this.ws = null; }
  }

  reply(callbackReqId, content) {
    const chunks = [];
    let offset = 0;
    while (offset < content.length) {
      let len = Math.min(content.length - offset, REPLY_CHUNK_BYTES);
      while (len > 0 && offset + len < content.length) {
        const c = content.charCodeAt(offset + len);
        if ((c & 0xC0) === 0x80) len--;
        else break;
      }
      if (len === 0) len = 1;
      chunks.push(content.slice(offset, offset + len));
      offset += len;
    }
    for (let i = 0; i < chunks.length; i++) {
      const isLast = i === chunks.length - 1;
      const ok = this.sendFrame({
        cmd: 'aibot_respond_msg',
        headers: { req_id: callbackReqId },
        body: {
          msgtype: 'stream',
          stream: {
            id: 'stream_' + (i + 1),
            finish: isLast,
            content: chunks[i],
          },
        },
      });
      if (!ok) return false;
    }
    return true;
  }
}
