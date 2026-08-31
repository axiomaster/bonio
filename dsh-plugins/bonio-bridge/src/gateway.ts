/**
 * hiclaw-compatible WebSocket gateway backed by the dsh Agent services.
 *
 * Listens on 127.0.0.1:PORT (default 10724) and speaks the legacy hiclaw
 * wire protocol so the unmodified bonio-app client can drive a dsh agent.
 */
import { randomUUID } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import type { Context } from '@deepseek-ai/cordis';
import {
  parseFrame, resOk, resErr, eventFrame, stringify,
  type ReqFrame, type EventFrame,
} from './protocol.js';
import { SessionRegistry } from './sessions.js';
import { deleteMemo, getMemo, listMemos } from './memo_store.js';

const DEFAULT_PORT = 10724;
const INVOKE_TIMEOUT_MS = 300_000; // 5 min, mirror hiclaw tool call timeout
const TICK_INTERVAL_MS = 30_000;   // heartbeat, mirror hiclaw

export interface BridgeConfig {
  port?: number;
  /** shared token; when set, connect requests must carry auth.token === token */
  token?: string;
}

interface AgentDriver {
  /** create a fresh agent, send the user message, and stream assistant events. */
  runChat(params: { text: string; sessionKey?: string; runId?: string }): Promise<{ runId: string; error?: string }>;
  /** cancel a running chat run. */
  abort(runId: string): void;
  getHistory(sessionKey?: string): Promise<Record<string, unknown>>;
  listSessions(): Promise<Record<string, unknown>>;
}

/** Broadcast a frame to a specific role's socket (operator or node). */
export interface WireBroadcaster {
  sendToRole(role: 'operator' | 'node', frame: EventFrame): boolean;
}

export function startGateway(
  ctx: Context,
  config: BridgeConfig,
  registry: SessionRegistry,
  driver: AgentDriver,
): { dispose: () => void; broadcaster: WireBroadcaster } {
  const port = config.port ?? DEFAULT_PORT;
  const token = config.token ?? '';

  // connId -> WebSocket map so the broadcaster can reach node sockets.
  const sockets = new Map<string, WebSocket>();
  const roleByConn = new Map<string, 'operator' | 'node'>();

  const broadcaster: WireBroadcaster = {
    sendToRole(role, frame) {
      // Find the connection registered under that role.
      const session = role === 'operator' ? registry.getOperator() : registry.getNode();
      if (!session) return false;
      const ws = sockets.get(session.connId);
      if (!ws || ws.readyState !== WebSocket.OPEN) return false;
      ws.send(stringify(frame));
      return true;
    },
  };

  const wss = new WebSocketServer({ host: '127.0.0.1', port });

  wss.on('connection', (ws: WebSocket) => {
    const connId = randomUUID();
    let role: 'operator' | 'node' | null = null;
    let authenticated = token === ''; // no token configured -> allow all
    let sessionKey: string | undefined;

    sockets.set(connId, ws);

    const send = (frame: { type: string; id?: string; ok?: boolean; payload?: unknown; error?: unknown; event?: string }) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(stringify(frame as never));
    };

    // hiclaw flow: server pushes connect.challenge (nonce) on connect; the
    // client signs/echoes it inside the connect request. We keep the nonce
    // for symmetry but the token check is what actually gates access.
    send(eventFrame('connect.challenge', { nonce: randomUUID() }));

    const requireAuth = (): boolean => authenticated;

    const handleConnect = async (frame: ReqFrame): Promise<void> => {
      const params = frame.params ?? {};
      const clientInfo = (params.client as Record<string, unknown>) ?? {};
      const auth = (params.auth as Record<string, unknown>) ?? {};

      if (token !== '' && auth.token !== token) {
        send(resErr(frame.id, 'AUTH_FAILED', 'invalid token'));
        ws.close(4001, 'invalid token');
        return;
      }
      authenticated = true;

      const requestedRole = typeof params.role === 'string' ? params.role : 'operator';
      role = requestedRole === 'node' ? 'node' : 'operator';
      roleByConn.set(connId, role);
      sessionKey = role === 'operator' ? 'main' : undefined;

      registry.attach({
        connId,
        role,
        clientId: typeof clientInfo.id === 'string' ? clientInfo.id : undefined,
        sessionKey,
      });

      send(resOk(frame.id, {
        server: { host: 'dsh-bonio-bridge' },
        snapshot: {
          sessionDefaults: { mainSessionKey: sessionKey ?? 'main' },
        },
      }));
    };

    const handleChatSend = async (frame: ReqFrame): Promise<void> => {
      if (!requireAuth()) return send(resErr(frame.id, 'AUTH_REQUIRED', 'connect first'));
      const params = (frame.params ?? {}) as Record<string, unknown>;
      // bonio-app sends `message`; accept `text` too for the smoke client.
      const text = typeof params.message === 'string' ? params.message
        : typeof params.text === 'string' ? params.text
        : '';
      if (!text) return send(resErr(frame.id, 'BAD_PARAMS', 'missing text'));
      const key = typeof params.sessionKey === 'string' && params.sessionKey
        ? params.sessionKey : sessionKey;
      // bonio-app sends idempotencyKey = its own runId; reuse it so agent/chat
      // events match the client's pendingRuns filter.
      const runId = typeof params.idempotencyKey === 'string' && params.idempotencyKey
        ? params.idempotencyKey : undefined;

      const result = await driver.runChat({ text, sessionKey: key, runId });
      if (result.error) return send(resErr(frame.id, 'CHAT_FAILED', result.error));
      // Respond immediately with the runId; agent events stream afterwards.
      send(resOk(frame.id, { runId: result.runId }));
    };

    const handleChatAbort = (frame: ReqFrame): void => {
      const params = (frame.params ?? {}) as Record<string, unknown>;
      const runId = typeof params.runId === 'string' ? params.runId : '';
      if (runId) driver.abort(runId);
      send(resOk(frame.id, { aborted: true }));
    };

    const handleNodeInvokeResult = (frame: ReqFrame): void => {
      const params = (frame.params ?? {}) as Record<string, unknown>;
      const callId = typeof params.id === 'string' ? params.id : '';
      const ok = params.ok === true;
      const payload = (params.payload as Record<string, unknown>) ?? undefined;
      const error = (params.error as { code?: string; message?: string }) ?? undefined;
      if (callId) {
        registry.completeInvoke(callId, {
          ok,
          payload,
          error: error ? { code: error.code ?? 'TOOL_ERROR', message: error.message ?? 'tool failed' } : undefined,
        });
      }
      send(resOk(frame.id, { received: true }));
    };

    const handlePing = (frame: ReqFrame): void => {
      send(resOk(frame.id, { pong: Date.now() }));
    };

    const handleHealth = (frame: ReqFrame): void => {
      send(resOk(frame.id, { ok: true, ts: Date.now() }));
    };

    const handleChatHistory = async (frame: ReqFrame): Promise<void> => {
      const params = (frame.params ?? {}) as Record<string, unknown>;
      const key = typeof params.sessionKey === 'string' ? params.sessionKey : sessionKey;
      send(resOk(frame.id, await driver.getHistory(key)));
    };

    const handleSessionsList = async (frame: ReqFrame): Promise<void> => {
      send(resOk(frame.id, await driver.listSessions()));
    };

    const handleMemoList = async (frame: ReqFrame): Promise<void> => {
      if (!requireAuth()) return send(resErr(frame.id, 'AUTH_REQUIRED', 'connect first'));
      const params = (frame.params ?? {}) as Record<string, unknown>;
      const rawLimit = typeof params.limit === 'number' ? params.limit : 100;
      const memos = await listMemos(rawLimit);
      send(resOk(frame.id, { memos, total: memos.length }));
    };

    const handleMemoGet = async (frame: ReqFrame): Promise<void> => {
      if (!requireAuth()) return send(resErr(frame.id, 'AUTH_REQUIRED', 'connect first'));
      const id = typeof frame.params?.id === 'string' ? frame.params.id : '';
      const memo = await getMemo(id);
      if (!memo) return send(resErr(frame.id, 'MEMO_NOT_FOUND', 'memory not found'));
      send(resOk(frame.id, { memo }));
    };

    const handleMemoDelete = async (frame: ReqFrame): Promise<void> => {
      if (!requireAuth()) return send(resErr(frame.id, 'AUTH_REQUIRED', 'connect first'));
      const id = typeof frame.params?.id === 'string' ? frame.params.id : '';
      if (!id) return send(resErr(frame.id, 'BAD_PARAMS', 'missing memory id'));
      const deleted = await deleteMemo(id);
      if (!deleted) return send(resErr(frame.id, 'MEMO_NOT_FOUND', 'memory not found'));
      send(resOk(frame.id, { deleted: true }));
    };

    const handleVoiceWakeGet = (frame: ReqFrame): void => {
      send(resOk(frame.id, { triggers: [] }));
    };

    const handleVoiceWakeSet = (frame: ReqFrame): void => {
      send(resOk(frame.id, { saved: true }));
    };

    const handleNodeEvent = (frame: ReqFrame): void => {
      // chat.subscribe etc. — accepted, no-op for now.
      send(resOk(frame.id, { received: true }));
    };

    const handleConfigGet = (frame: ReqFrame): void => {
      send(resOk(frame.id, {
        default_model: 'deepseek',
        models: [],
        gateway: { enabled: true, host: '127.0.0.1', port },
        providers: [],
      }));
    };

    ws.on('message', (data: Buffer) => {
      const text = data.toString();
      const frame = parseFrame(text);
      if (!frame || frame.type !== 'req') return;

      const req = frame as ReqFrame;
      switch (req.method) {
        case 'connect':
          void handleConnect(req);
          break;
        case 'chat.send':
          void handleChatSend(req);
          break;
        case 'chat.abort':
          handleChatAbort(req);
          break;
        case 'chat.history':
          void handleChatHistory(req);
          break;
        case 'node.invoke.result':
          handleNodeInvokeResult(req);
          break;
        case 'node.event':
          handleNodeEvent(req);
          break;
        case 'sessions.list':
          void handleSessionsList(req);
          break;
        case 'memo.list':
          void handleMemoList(req);
          break;
        case 'memo.get':
          void handleMemoGet(req);
          break;
        case 'memo.delete':
          void handleMemoDelete(req);
          break;
        case 'health':
          handleHealth(req);
          break;
        case 'voicewake.get':
          handleVoiceWakeGet(req);
          break;
        case 'voicewake.set':
          handleVoiceWakeSet(req);
          break;
        case 'config.get':
          handleConfigGet(req);
          break;
        case 'ping':
        case 'tick':
          handlePing(req);
          break;
        default:
          send(resErr(req.id, 'UNKNOWN_METHOD', `method not implemented: ${req.method}`));
      }
    });

    ws.on('close', () => {
      sockets.delete(connId);
      roleByConn.delete(connId);
      registry.detach(connId);
    });
  });

  // Heartbeat tick to all operator sessions (mirror hiclaw).
  const tickTimer = setInterval(() => {
    broadcaster.sendToRole('operator', eventFrame('tick', { ts: Date.now() }));
  }, TICK_INTERVAL_MS);

  (ctx as any).on('dispose', () => {
    clearInterval(tickTimer);
    registry.cancelAll();
    wss.close();
  });

  const dispose = () => {
    clearInterval(tickTimer);
    registry.cancelAll();
    wss.close();
  };
  return { dispose, broadcaster };
}
