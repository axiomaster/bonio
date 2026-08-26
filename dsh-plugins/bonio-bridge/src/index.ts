/**
 * bonio-bridge — hiclaw-compatible WebSocket gateway for DeepSeek Harness.
 *
 * Mounts a legacy hiclaw gateway (127.0.0.1:10724) inside a dsh process so
 * the unmodified bonio-app client can drive a dsh agent: chat, streaming
 * agent deltas, and device tool calls routed back to the node session.
 *
 * Usage: add this package to a dsh profile (pnpm add /path/to/bonio-bridge)
 * and reference it from the profile's cordis.patch.yml.
 */
import { Context } from '@deepseek-ai/cordis';
import { defineTool } from '@deepseek-ai/dsh-tools';
import { startGateway, type WireBroadcaster } from './gateway.js';
import { SessionRegistry } from './sessions.js';
import { AgentDriver } from './driver.js';
import { eventFrame, type EventFrame } from './protocol.js';

export interface BridgeServiceConfig {
  port?: number;
  token?: string;
  /** tools: when 'route' (default), the single bonio_node_invoke bridge tool is registered. */
  tools?: 'route' | 'none';
}

declare module '@deepseek-ai/cordis' {
  interface Context {
    bonioBridge: BridgeService;
  }
}

class BridgeService {
  private broadcaster: WireBroadcaster | null = null;

  constructor(
    private ctx: Context,
    private config: BridgeServiceConfig,
  ) {}

  start(): void {
    const registry = new SessionRegistry();
    const service = this;

    // Sink: emit hiclaw 'agent'/'chat' events to the operator socket.
    const sink = {
      agentDelta(runId: string, sessionKey: string | undefined, delta: string) {
        service.emit('agent', { runId, sessionKey, stream: 'assistant', data: { text: delta } });
      },
      chatFinal(runId: string, sessionKey: string | undefined, payload: Record<string, unknown>) {
        service.emit('chat', { runId, sessionKey, state: payload.state ?? 'final', ...payload });
      },
    };

    const driver = new AgentDriver(
      this.ctx,
      registry,
      sink,
      async (callId, command, args, timeoutMs) => {
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
      },
    );

    // Register the bridge tool when configured (ctx.tools is injected).
    if (this.config.tools !== 'none') {
      try {
        driver.registerBridgeTool(defineTool, (def) => this.ctx.tools.register(def));
      } catch (error) {
        console.error('[bonio-bridge] tool registration failed:', error instanceof Error ? error.message : error);
      }
    }

    // Start the gateway and keep the broadcaster for event emission.
    const { dispose, broadcaster } = startGateway(this.ctx, this.config, registry, driver);
    this.broadcaster = broadcaster;

    this.ctx.on('dispose', () => {
      this.broadcaster = null;
      dispose();
    });
  }

  /** Emit an event frame to the node/operator socket via the gateway broadcaster. */
  private emit(event: string, payload: Record<string, unknown>): boolean {
    if (!this.broadcaster) return false;
    const frame: EventFrame = eventFrame(event, payload);
    // node.invoke and agent/chat events target the node and operator sockets
    // respectively; the gateway's sendToRole picks the right socket by event.
    const role = event === 'node.invoke.request' ? 'node' : 'operator';
    return this.broadcaster.sendToRole(role, frame);
  }
}

export function apply(ctx: Context, config: BridgeServiceConfig): void {
  const service = new BridgeService(ctx, config);
  ctx.provide('bonioBridge', service);
  service.start();
}

export const name = 'bonio-bridge';
export const Config = undefined as unknown as BridgeServiceConfig;
export const inject = ['tools', 'agents', 'sessions', 'agentDefaultModel'];
