/** dsh Agent driver for the bonio bridge. */
import { randomUUID } from 'node:crypto';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';

export const INVOKE_TIMEOUT_MS = 300000;

export class AgentDriver {
  constructor(ctx, registry, sink, forwardInvoke) {
    this.ctx = ctx;
    this.registry = registry;
    this.sink = sink;
    this.forwardInvoke = forwardInvoke;
    this.runs = new Map();
  }

  async runChat(params) {
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
      // session/event carries (subject, event); filter to this agent's session.
      const onEvent = (subject, event) => {
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
      let reason;
      for (const e of events) {
        if (e.seq < firstSeq) continue;
        if (e.type === 'assistant/message') {
          const joined = (e.data?.message?.content ?? [])
            .filter((b) => b.type === 'text')
            .map((b) => b.text)
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
        error: reason && reason.kind === 'error' ? (reason.error?.message ?? 'agent error') : undefined,
      });
      return { runId };
    } catch (error) {
      this.runs.delete(runId);
      const message = error instanceof Error ? error.message : String(error);
      this.sink.chatFinal(runId, params.sessionKey, { text: '', state: 'error', errorMessage: message, done: true });
      return { runId, error: message };
    }
  }

  abort(runId) {
    const run = this.runs.get(runId);
    if (run) {
      try {
        run.controller.abort();
        void run.agent.cancel?.('aborted by user');
      } catch { /* ignore */ }
      this.runs.delete(runId);
    }
  }

  registerBridgeTool(defineTool, register) {
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
        schema: {
          type: 'object',
          additionalProperties: true,
          description: 'The device result payload returned by the node session.',
        },
        render(result) {
          const value = result.value;
          if (value && typeof value === 'object' && value.error) {
            return 'device tool error: ' + String(value.error);
          }
          try { return JSON.stringify(value, null, 2); }
          catch { return String(value); }
        },
      },
      async execute(exec) {
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
