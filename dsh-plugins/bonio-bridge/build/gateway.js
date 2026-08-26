/** hiclaw-compatible WebSocket gateway backed by dsh agent services. */
import { randomUUID } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { parseFrame, resOk, resErr, eventFrame, stringify } from './protocol.js';

const DEFAULT_PORT = 10724;
const TICK_INTERVAL_MS = 30000;

export function startGateway(ctx, config, registry, driver) {
  const port = config.port ?? DEFAULT_PORT;
  const token = config.token ?? '';

  const sockets = new Map();
  const roleByConn = new Map();

  const broadcaster = {
    sendToRole(role, frame) {
      const session = role === 'operator' ? registry.getOperator() : registry.getNode();
      if (!session) return false;
      const ws = sockets.get(session.connId);
      if (!ws || ws.readyState !== WebSocket.OPEN) return false;
      ws.send(stringify(frame));
      return true;
    },
  };

  const wss = new WebSocketServer({ host: '127.0.0.1', port });

  wss.on('connection', (ws) => {
    const connId = randomUUID();
    let role = null;
    let authenticated = token === '';
    let sessionKey;

    sockets.set(connId, ws);

    const send = (frame) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(stringify(frame));
    };

    send(eventFrame('connect.challenge', { nonce: randomUUID() }));

    const handleConnect = async (frame) => {
      const params = frame.params ?? {};
      const clientInfo = params.client ?? {};
      const auth = params.auth ?? {};

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

      // hiclaw connect response shape (see bonio-app GatewaySession.ets):
      //   payload.server.host, payload.snapshot.sessionDefaults.mainSessionKey
      send(resOk(frame.id, {
        server: { host: 'dsh-bonio-bridge' },
        snapshot: {
          sessionDefaults: { mainSessionKey: sessionKey ?? 'main' },
        },
      }));
    };

    const handleChatSend = async (frame) => {
      if (!authenticated) return send(resErr(frame.id, 'AUTH_REQUIRED', 'connect first'));
      const params = frame.params ?? {};
      // bonio-app sends `message`; the smoke client uses `text` — accept both.
      const text = typeof params.message === 'string' ? params.message
        : typeof params.text === 'string' ? params.text
        : '';
      if (!text) return send(resErr(frame.id, 'BAD_PARAMS', 'missing text'));
      // The client may pass its own sessionKey; prefer it over the connection one.
      const key = typeof params.sessionKey === 'string' && params.sessionKey
        ? params.sessionKey : sessionKey;

      const result = await driver.runChat({ text, sessionKey: key });
      if (result.error) return send(resErr(frame.id, 'CHAT_FAILED', result.error));
      send(resOk(frame.id, { runId: result.runId }));
    };

    const handleChatAbort = (frame) => {
      const params = frame.params ?? {};
      const runId = typeof params.runId === 'string' ? params.runId : '';
      if (runId) driver.abort(runId);
      send(resOk(frame.id, { aborted: true }));
    };

    const handleNodeInvokeResult = (frame) => {
      const params = frame.params ?? {};
      const callId = typeof params.id === 'string' ? params.id : '';
      const ok = params.ok === true;
      const payload = params.payload ?? undefined;
      const error = params.error ?? undefined;
      if (callId) {
        registry.completeInvoke(callId, {
          ok,
          payload,
          error: error ? { code: error.code ?? 'TOOL_ERROR', message: error.message ?? 'tool failed' } : undefined,
        });
      }
      send(resOk(frame.id, { received: true }));
    };

    const handlePing = (frame) => {
      send(resOk(frame.id, { pong: Date.now() }));
    };

    const handleHealth = (frame) => {
      send(resOk(frame.id, { ok: true, ts: Date.now() }));
    };

    const handleChatHistory = (frame) => {
      const params = frame.params ?? {};
      const key = typeof params.sessionKey === 'string' ? params.sessionKey : sessionKey;
      send(resOk(frame.id, driver.getHistory(key)));
    };

    const handleSessionsList = (frame) => {
      send(resOk(frame.id, driver.listSessions()));
    };

    const handleVoiceWakeGet = (frame) => {
      send(resOk(frame.id, { triggers: [] }));
    };

    const handleVoiceWakeSet = (frame) => {
      send(resOk(frame.id, { saved: true }));
    };

    const handleNodeEvent = (frame) => {
      // chat.subscribe etc. — accepted, no-op for now.
      send(resOk(frame.id, { received: true }));
    };

    const handleConfigGet = (frame) => {
      send(resOk(frame.id, {
        default_model: 'deepseek',
        models: [],
        gateway: { enabled: true, host: '127.0.0.1', port },
        providers: [],
      }));
    };

    ws.on('message', (data) => {
      const text = data.toString();
      const frame = parseFrame(text);
      if (!frame || frame.type !== 'req') return;
      switch (frame.method) {
        case 'connect': void handleConnect(frame); break;
        case 'chat.send': void handleChatSend(frame); break;
        case 'chat.abort': handleChatAbort(frame); break;
        case 'chat.history': handleChatHistory(frame); break;
        case 'node.invoke.result': handleNodeInvokeResult(frame); break;
        case 'node.event': handleNodeEvent(frame); break;
        case 'sessions.list': handleSessionsList(frame); break;
        case 'health': handleHealth(frame); break;
        case 'voicewake.get': handleVoiceWakeGet(frame); break;
        case 'voicewake.set': handleVoiceWakeSet(frame); break;
        case 'config.get': handleConfigGet(frame); break;
        case 'ping':
        case 'tick': handlePing(frame); break;
        default:
          send(resErr(frame.id, 'UNKNOWN_METHOD', `method not implemented: ${frame.method}`));
      }
    });

    ws.on('close', () => {
      sockets.delete(connId);
      roleByConn.delete(connId);
      registry.detach(connId);
    });
  });

  const tickTimer = setInterval(() => {
    broadcaster.sendToRole('operator', eventFrame('tick', { ts: Date.now() }));
  }, TICK_INTERVAL_MS);

  const dispose = () => {
    clearInterval(tickTimer);
    registry.cancelAll();
    wss.close();
  };

  ctx.on('dispose', dispose);
  return { dispose, broadcaster };
}
