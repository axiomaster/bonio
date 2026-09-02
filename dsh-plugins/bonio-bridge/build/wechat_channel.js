/**
 * wechat_channel — personal-WeChat (ilink) channel running inside the bridge.
 *
 * Reads the binding the app wrote via channel.wechat.setup (persisted in
 * <home>/.bonio/hiclaw.json), long-polls ilink for inbound messages, feeds
 * them to the shared AgentDriver under `wechat:weixin:<fromUserId>` session
 * keys (multi-turn, persisted, streamed to the operator socket like any other
 * run), and sends the final assistant text back to the WeChat sender.
 */
import { getWechatBinding, bonioHome } from './channel_store.js';
import { IlinkHttpClient } from './ilink.js';
const LOG_PREFIX = '[bonio-wechat]';
const DEDUP_TTL_MS = 300000;
export class WechatChannel {
    driver;
    ilink = null;
    activeToken = '';
    activeBaseUrl = '';
    allowFrom = [];
    /** runId -> WeChat sender awaiting a reply. */
    pendingReplies = new Map();
    dedupCache = new Map();
    constructor(driver) {
        this.driver = driver;
    }
    /** (Re)start or stop the poller according to the persisted hiclaw.json binding. */
    async syncFromConfig() {
        try {
            const binding = await getWechatBinding();
            if (!binding.enabled || binding.mode !== 'weixin' || !binding.token) {
                const hadPoller = this.ilink !== null;
                this.stop();
                if (binding.enabled && binding.mode !== 'weixin') {
                    console.log(LOG_PREFIX, `mode ${binding.mode} has no bridge poller; not starting`);
                }
                else if (hadPoller) {
                    console.log(LOG_PREFIX, 'binding disabled; poller stopped');
                }
                return;
            }
            if (this.ilink && this.activeToken === binding.token && this.activeBaseUrl === binding.baseUrl)
                return;
            this.stop();
            this.allowFrom = binding.allowFrom;
            this.ilink = new IlinkHttpClient(binding.token, binding.baseUrl, bonioHome() + '/.bonio/wechat-state', (msg) => { void this.handleInbound(msg); }, (m) => console.log(m));
            this.ilink.start();
            this.activeToken = binding.token;
            this.activeBaseUrl = binding.baseUrl;
            console.log(LOG_PREFIX, `ilink poller started (base=${binding.baseUrl}, allow_from=${binding.allowFrom.length || 'all'})`);
        }
        catch (e) {
            console.log(LOG_PREFIX, 'sync failed:', e instanceof Error ? e.message : String(e));
        }
    }
    async handleInbound(msg) {
        const text = msg.content.trim();
        if (!text || !msg.fromUserId)
            return;
        if (this.allowFrom.length > 0 && !this.allowFrom.includes(msg.fromUserId) && !this.allowFrom.includes('*'))
            return;
        if (msg.messageId) {
            const now = Date.now();
            if (this.dedupCache.has(msg.messageId))
                return;
            this.dedupCache.set(msg.messageId, now);
            for (const [k, v] of this.dedupCache) {
                if (now - v > DEDUP_TTL_MS)
                    this.dedupCache.delete(k);
            }
        }
        const sessionKey = `wechat:weixin:${msg.fromUserId}`;
        console.log(LOG_PREFIX, `msg from ${msg.fromUserId} session=${sessionKey}`);
        const result = await this.driver.runChat({ text, sessionKey });
        if (result.error || !result.runId) {
            void this.ilink?.sendMessage(msg.fromUserId, '[Error] ' + (result.error || 'agent unavailable'));
            return;
        }
        this.pendingReplies.set(result.runId, msg.fromUserId);
    }
    /**
     * Called from the bridge sink for every chat final. Wechat runs route the
     * final assistant text back to the waiting WeChat sender.
     */
    handleChatFinal(runId, payload) {
        const userId = this.pendingReplies.get(runId);
        if (!userId)
            return;
        this.pendingReplies.delete(runId);
        if (!this.ilink)
            return;
        const state = typeof payload['state'] === 'string' ? payload['state'] : 'final';
        if (state === 'error') {
            const err = typeof payload['errorMessage'] === 'string' && payload['errorMessage']
                ? payload['errorMessage'] : 'agent error';
            void this.ilink.sendMessage(userId, '[Error] ' + err);
            return;
        }
        const text = typeof payload['text'] === 'string' && payload['text']
            ? payload['text']
            : typeof payload['message'] === 'string' && payload['message']
                ? payload['message'] : '';
        if (text)
            void this.ilink.sendMessage(userId, text);
    }
    stop() {
        if (this.ilink) {
            this.ilink.stop();
            this.ilink = null;
        }
        this.activeToken = '';
        this.activeBaseUrl = '';
        this.allowFrom = [];
    }
}
