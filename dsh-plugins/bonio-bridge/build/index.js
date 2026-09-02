import { defineTool } from '@deepseek-ai/dsh-tools';
import { startGateway } from './gateway.js';
import { SessionRegistry } from './sessions.js';
import { AgentDriver } from './driver.js';
import { WechatChannel } from './wechat_channel.js';
import { eventFrame } from './protocol.js';
const BONIO_IDENTITY_PROMPT = `
你的名字是 Bonio。你的身份是：我是 Bonio，是住在手机里你的搭子，陪你解闷，帮你记录，完成各项琐事；陪你笑、陪你哭，陪你走过风风雨雨、度过分分秒秒。

你始终以 Bonio 的身份与用户交流，不要自称 DeepSeek 智能助手或其他模型名称。
`;
class BridgeService {
    ctx;
    config;
    broadcaster = null;
    constructor(ctx, config) {
        this.ctx = ctx;
        this.config = config;
    }
    start() {
        const registry = new SessionRegistry();
        const service = this;
        let wechatChannel;
        this.ctx.systemPrompt.section({
            name: 'bonio:identity',
            order: -100,
            text: BONIO_IDENTITY_PROMPT,
        });
        // Sink: emit hiclaw 'agent'/'chat' events to the operator socket.
        const sink = {
            agentDelta(runId, sessionKey, delta) {
                service.emit('agent', { runId, sessionKey, stream: 'assistant', data: { text: delta } });
            },
            chatFinal(runId, sessionKey, payload) {
                service.emit('chat', { runId, sessionKey, state: payload.state ?? 'final', ...payload });
                // Wechat-triggered runs send their final reply back to the WeChat sender.
                wechatChannel?.handleChatFinal(runId, payload);
            },
        };
        const driver = new AgentDriver(this.ctx, registry, sink, async (callId, command, args, timeoutMs) => {
            // Send node.invoke.request to the node session and wait for the result.
            const sent = service.emit('node.invoke.request', {
                id: callId,
                command,
                params: args,
                timeoutMs,
            });
            if (!sent) {
                return { ok: false, error: { code: 'NO_NODE', message: 'no node session connected' } };
            }
            return registry.registerInvoke(callId, timeoutMs);
        });
        // Register the bridge tool + local hiclaw-parity tools (ctx.tools injected).
        if (this.config.tools !== 'none') {
            try {
                const defineBridgeTool = defineTool;
                driver.registerBridgeTool(defineBridgeTool, (def) => this.ctx.tools.register(def));
                driver.registerLocalTools(defineBridgeTool, (def) => this.ctx.tools.register(def));
            }
            catch (error) {
                console.error('[bonio-bridge] tool registration failed:', error instanceof Error ? error.message : error);
            }
        }
        // Wechat channel: starts/stops from the persisted hiclaw.json binding and
        // is re-synced whenever the app changes the binding via channel.wechat.*.
        wechatChannel = new WechatChannel(driver);
        void wechatChannel.syncFromConfig();
        // Start the gateway and keep the broadcaster for event emission.
        const { dispose, broadcaster } = startGateway(this.ctx, this.config, registry, driver, {
            syncFromConfig: () => wechatChannel ? wechatChannel.syncFromConfig() : Promise.resolve(),
        });
        this.broadcaster = broadcaster;
        this.ctx.on('dispose', () => {
            wechatChannel?.stop();
            this.broadcaster = null;
            dispose();
        });
    }
    /** Emit an event frame to the node/operator socket via the gateway broadcaster. */
    emit(event, payload) {
        if (!this.broadcaster)
            return false;
        const frame = eventFrame(event, payload);
        // node.invoke and agent/chat events target the node and operator sockets
        // respectively; the gateway's sendToRole picks the right socket by event.
        const role = event === 'node.invoke.request' ? 'node' : 'operator';
        return this.broadcaster.sendToRole(role, frame);
    }
}
export function apply(ctx, config) {
    const service = new BridgeService(ctx, config);
    ctx.provide('bonioBridge', service);
    service.start();
}
export const name = 'bonio-bridge';
export const Config = undefined;
export const inject = ['tools', 'agents', 'sessions', 'agentDefaultModel', 'systemPrompt'];
