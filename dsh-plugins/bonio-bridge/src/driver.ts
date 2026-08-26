/**
 * dsh Agent driver for the bonio bridge (TypeScript reference; the deployed
 * artifact is build/driver.js which this mirrors).
 */
import type { Context } from '@deepseek-ai/cordis';
import { randomUUID } from 'node:crypto';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';
import { SessionRegistry } from './sessions.js';

export interface ChatEventSink {
  agentDelta(runId: string, sessionKey: string | undefined, delta: string): void;
  chatFinal(runId: string, sessionKey: string | undefined, payload: Record<string, unknown>): void;
}

export type InvokeForwarder = (
  callId: string,
  command: string,
  args: Record<string, unknown>,
  timeoutMs: number,
) => Promise<{ ok: boolean; payload?: Record<string, unknown>; error?: { code: string; message: string } }>;

export const INVOKE_TIMEOUT_MS = 300_000;

export class AgentDriver {
  private runs = new Map<string, { agent: any; controller: AbortController }>();

  constructor(
    private ctx: Context,
    private registry: SessionRegistry,
    private sink: ChatEventSink,
    private forwardInvoke: InvokeForwarder,
  ) {}

  async runChat(params: { text: string; sessionKey?: string }): Promise<{ runId: string; error?: string }> {
    const ctx = this.ctx;
    const agents = ctx.get('agents');
    const defaultModel = ctx.get('agentDefaultModel');
    const sessions = ctx.get('sessions');
    if (!agents || !defaultModel || !sessions) {
      return { runId: '', error: 'dsh agent services unavailable' };
    }
    await ctx.get('loader')?.await?.();

    const selection = defaultModel.currentSelection();
    const runId = randomUUID();
    const controller = new AbortController();

    try {
      const { agent } = await agents.create({
        sessionId: SessionId(`session-${runId}`),
        meta: { cwd: process.cwd() },
        agentOptions: { provider: selection.provider, model: selection.model },
      });
      this.runs.set(runId, { agent, controller });

      const firstSeq = agent.session.seq;
      const onEvent = (subject: unknown, event: any) => {
        if (subject !== agent.session) return;
        if (event.type === 'assistant/chunk') {
          const chunk = event.data?.chunk;
          const text = chunk && chunk.type === 'text-delta' ? (chunk.text ?? '') : '';
          if (text) this.sink.agentDelta(runId, params.sessionKey, text);
        }
      };
      const off = ctx.on('session/event', onEvent);

      await agent.whenIdle();
      agent.followup(createUserMessage({
        content: [{ type: 'text', text: params.text }],
        source: { kind: 'user' },
      }));
      await agent.whenIdle();
      off?.();

      const events = agent.session.events ?? [];
      let text = '';
      let reason: unknown;
      for (const e of events) {
        if (e.seq < firstSeq) continue;
        if (e.type === 'assistant/message') {
          const joined = (e.data?.message?.content ?? [])
            .filter((b: any) => b.type === 'text')
            .map((b: any) => b.text)
            .join('');
          if (joined !== '') text = joined;
        }
        if (e.type === 'turn/end') reason = e.data?.reason;
      }

      await sessions.flush(agent.session);
      this.runs.delete(runId);

      this.sink.chatFinal(runId, params.sessionKey, {
        text,
        state: 'final',
        done: true,
        error: reason && (reason as { kind?: string }).kind === 'error'
          ? ((reason as { error?: { code?: string; message?: string } }).error?.message ?? 'agent error')
          : undefined,
      });
      return { runId };
    } catch (error) {
      this.runs.delete(runId);
      const message = error instanceof Error ? error.message : String(error);
      this.sink.chatFinal(runId, params.sessionKey, { text: '', state: 'error', errorMessage: message, done: true });
      return { runId, error: message };
    }
  }

  abort(runId: string): void {
    const run = this.runs.get(runId);
    if (run) {
      try {
        run.controller.abort();
        void run.agent.cancel?.('aborted by user');
      } catch { /* ignore */ }
      this.runs.delete(runId);
    }
  }

  registerBridgeTool(defineTool: (def: Record<string, unknown>) => unknown, register: (def: unknown) => () => void): () => void {
    const bridge = this;
    const def = defineTool({
      name: 'bonio_node_invoke',
      description:
        'Invoke a device capability on the companion bonio-app node session (camera, screen capture, location, sms, canvas, input typing, system notifications, calendar, contacts, and similar device commands). Returns the device result payload.',
      parameters: {
        command: {
          type: 'string',
          required: true,
          description: 'Device command name, e.g. camera.snap, screen.capture, sms.send, location.get, canvas.present, input.type, system.notify, calendar.events, contacts.search.',
        },
        arguments: { type: 'object', additionalProperties: true, description: 'Command arguments as a JSON object, e.g. {"text":"hello"} for input.type.' },
        timeoutMs: { type: 'number', description: 'Timeout in milliseconds; default 300000.' },
      },
      output: {
        schema: { type: 'object', additionalProperties: true, description: 'The device result payload returned by the node session.' },
        render(result: { value?: unknown }) {
          const value = result.value;
          if (value && typeof value === 'object' && (value as Record<string, unknown>).error) {
            return 'device tool error: ' + String((value as Record<string, unknown>).error);
          }
          try { return JSON.stringify(value, null, 2); }
          catch { return String(value); }
        },
      },
      async execute(exec: { arguments: { command: string; arguments?: Record<string, unknown>; timeoutMs?: number } }) {
        const { command, arguments: args = {}, timeoutMs = INVOKE_TIMEOUT_MS } = exec.arguments;
        const node = bridge.registry.getNode();
        if (!node) {
          return { isError: true, error: { message: 'no node session connected to the bonio bridge' } };
        }
        const callId = randomUUID();
        const result = await bridge.forwardInvoke(callId, command, args, timeoutMs);
        if (result.ok) return { isError: false, value: result.payload ?? {} };
        return { isError: true, error: { message: result.error?.message ?? 'device tool failed' } };
      },
    });
    return register(def);
  }
}
