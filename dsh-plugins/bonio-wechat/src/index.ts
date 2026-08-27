/**
 * bonio-wechat — WeChat channel bridge for DeepSeek Harness on HarmonyOS.
 * Ports hiclaw's WeChatAdapter into a dsh cordis plugin.
 */
import { randomUUID } from 'node:crypto';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';
import { WecomWsClient } from './wecom.js';
import { IlinkHttpClient } from './ilink.js';

const DEFAULT_ILINK_BASE = 'https://ilinkai.weixin.qq.com';

class WeChatService {
  constructor(ctx, config) {
    this.ctx = ctx;
    this.config = config || {};
    this.wecom = null;
    this.ilink = null;
    this.pendingReplyCtx = new Map();
    this.dedupCache = new Map();
    this.dedupTtlMs = 300000;
  }

  start() {
    const cfg = this.config;
    const mode = cfg.mode || 'wecom';
    const stateDir = '/data/local/home/.bonio/wechat-state';
    const driver = this.createDriver();

    if (mode === 'wecom') {
      const w = cfg.wecom || {};
      if (!w.bot_id || !w.bot_secret) {
        console.log('[bonio-wechat] wecom mode requires bot_id + bot_secret; not starting');
        return;
      }
      this.wecom = new WecomWsClient(
        w.bot_id,
        w.bot_secret,
        (msgId, userId, chatId, chatType, content, callbackReqId) => {
          this.handleInbound(driver, {
            sessionKey: chatType === 'group'
              ? `wechat:wecom:${chatId}:${userId}`
              : `wechat:wecom:${userId}`,
            userId,
            content,
            replyCtx: callbackReqId,
            msgId,
          });
        },
        (m) => console.log(m),
      );
      this.wecom.start();
    } else if (mode === 'weixin') {
      const wx = cfg.weixin || {};
      if (!wx.token) {
        console.log('[bonio-wechat] weixin mode requires token; not starting');
        return;
      }
      this.ilink = new IlinkHttpClient(
        wx.token,
        wx.base_url || DEFAULT_ILINK_BASE,
        stateDir,
        (msg) => {
          this.handleInbound(driver, {
            sessionKey: `wechat:weixin:${msg.fromUserId}`,
            userId: msg.fromUserId,
            content: msg.content,
            replyCtx: msg.fromUserId,
            msgId: msg.messageId,
          });
        },
        (m) => console.log(m),
      );
      this.ilink.start();
    } else {
      console.log('[bonio-wechat] unsupported mode: ' + mode);
    }

    this.ctx.on('dispose', () => {
      this.stop();
    });
  }

  createDriver() {
    const ctx = this.ctx;
    return {
      async runChat(params) {
        try {
          const agents = ctx.get('agents');
          const defaultModel = ctx.get('agentDefaultModel');
          const sessions = ctx.get('sessions');
          if (!agents || !defaultModel || !sessions) {
            return { error: 'agent services unavailable' };
          }
          await ctx.get('loader')?.await?.();

          const selection = defaultModel.currentSelection();
          const { agent } = await agents.create({
            sessionId: SessionId('session-' + randomUUID()),
            meta: { cwd: process.cwd() },
            agentOptions: {
              provider: selection.provider,
              model: selection.model,
            },
          });
          await agent.whenIdle();
          agent.followup(createUserMessage({
            content: [{ type: 'text', text: params.text }],
            source: { kind: 'user' },
          }));
          await agent.whenIdle();
          await sessions.flush(agent.session);

          const events = agent.session.events ?? [];
          let text = '';
          for (const e of events) {
            if (e.type === 'assistant/message') {
              const joined = (e.data?.message?.content ?? [])
                .filter((b) => b.type === 'text')
                .map((b) => b.text)
                .join('');
              if (joined !== '') text = joined;
            }
          }
          return { text };
        } catch (e) {
          return { error: e instanceof Error ? e.message : String(e) };
        }
      },
    };
  }

  async handleInbound(driver, info) {
    const allow = this.config.allow_from || [];
    if (allow.length > 0 && !allow.includes(info.userId) && !allow.includes('*')) return;
    if (info.msgId) {
      const now = Date.now();
      if (this.dedupCache.has(info.msgId)) return;
      this.dedupCache.set(info.msgId, now);
      for (const [k, v] of this.dedupCache) {
        if (now - v > this.dedupTtlMs) this.dedupCache.delete(k);
      }
    }
    this.pendingReplyCtx.set(info.sessionKey, info.replyCtx);
    console.log('[bonio-wechat] msg from ' + info.userId + ' session=' + info.sessionKey);

    const result = await driver.runChat({ text: info.content, sessionKey: info.sessionKey });
    const replyCtx = this.pendingReplyCtx.get(info.sessionKey);
    if (!replyCtx) return;

    const reply = result.error ? ('[Error] ' + result.error) : (result.text || '(no reply)');
    if (this.wecom) this.wecom.reply(replyCtx, reply);
    else if (this.ilink) { void this.ilink.sendMessage(replyCtx, reply); }
    this.pendingReplyCtx.delete(info.sessionKey);
  }

  stop() {
    if (this.wecom) { this.wecom.stop(); this.wecom = null; }
    if (this.ilink) { this.ilink.stop(); this.ilink = null; }
  }
}

export function apply(ctx, config) {
  const service = new WeChatService(ctx, config);
  ctx.provide('bonioWechat', service);
  service.start();
}

export const name = 'bonio-wechat';
export const Config = undefined;
export const inject = ['agents', 'sessions', 'agentDefaultModel'];
