/** bonio-bridge — hiclaw-compatible WebSocket gateway for DeepSeek Harness. */
import { defineTool } from '@deepseek-ai/dsh-tools';
import { startGateway } from './gateway.js';
import { SessionRegistry } from './sessions.js';
import { AgentDriver } from './driver.js';
import { eventFrame } from './protocol.js';

class BridgeService {
  constructor(ctx, config) {
    this.ctx = ctx;
    this.config = config;
    this.broadcaster = null;
  }
  start() {
    const registry = new SessionRegistry();
    const service = this;

    const sink = {
      agentDelta(runId, sessionKey, text) {
        // hiclaw 'agent' event: stream assistant text delta.
        service.emit('agent', { runId, sessionKey, stream: 'assistant', data: { text } });
      },
      chatFinal(runId, sessionKey, payload) {
        // hiclaw 'chat' event: final state ('final' | 'error').
        service.emit('chat', { runId, sessionKey, state: payload.state ?? 'final', ...payload });
      },
    };

    const driver = new AgentDriver(
      this.ctx,
      registry,
      sink,
      async (callId, command, args, timeoutMs) => {
        const sent = service.emit('node.invoke.request', { id: callId, command, params: args, timeoutMs });
        if (!sent) return { ok: false, error: { code: 'NO_NODE', message: 'no node session connected' } };
        return registry.registerInvoke(callId, timeoutMs);
      },
    );

    if (this.config.tools !== 'none') {
      try {
        driver.registerBridgeTool(defineTool, (def) => this.ctx.tools.register(def));
      } catch (error) {
        console.error('[bonio-bridge] tool registration failed:', error instanceof Error ? error.message : error);
      }
    }

    const { dispose, broadcaster } = startGateway(this.ctx, this.config, registry, driver);
    this.broadcaster = broadcaster;

    this.ctx.on('dispose', () => {
      this.broadcaster = null;
      dispose();
    });
  }
  emit(event, payload) {
    if (!this.broadcaster) return false;
    const frame = eventFrame(event, payload);
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
export const inject = ['tools', 'agents', 'sessions', 'agentDefaultModel'];
