/**
 * Smoke test client simulating bonio-app's hiclaw protocol against the
 * bonio-bridge gateway (ws://127.0.0.1:10724).
 *
 * Flow: connect (receive challenge) -> connect req (token) -> chat.send ->
 * collect agent/chat events. Optionally attach a node session and trigger a
 * tool call through the bridge tool.
 */
import WebSocket from 'ws';

const URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:10724';
const TOKEN = process.env.BRIDGE_TOKEN || 'test-token-123';
const MODE = process.argv[2] || 'chat'; // chat | node-tool

function frame(type, id, method, params) {
  const f = { type, id, method, params };
  return JSON.stringify(f);
}

async function main() {
  const ws = new WebSocket(URL);
  const pending = new Map();
  let seq = 0;
  let sessionKey;

  const events = [];

  const rpc = (method, params) => new Promise((resolve, reject) => {
    const id = `r${++seq}`;
    pending.set(id, { resolve, reject, method });
    ws.send(frame('req', id, method, params));
  });

  ws.on('message', (data) => {
    const f = JSON.parse(data.toString());
    if (f.type === 'event') {
      console.log(`[event] ${f.event}`, JSON.stringify(f.payload).slice(0, 200));
      if (f.event === 'connect.challenge') {
        void connect(f.payload.nonce);
      } else if (f.event === 'agent' || f.event === 'chat') {
        events.push(f);
      }
    } else if (f.type === 'res') {
      const p = pending.get(f.id);
      if (p) {
        pending.delete(f.id);
        if (f.ok) p.resolve(f.payload);
        else p.reject(new Error(`${p.method}: ${f.error?.message}`));
      }
    }
  });

  async function connect(nonce) {
    try {
      const res = await rpc('connect', {
        role: 'operator',
        client: { id: 'smoke-test', version: '0.1', platform: 'node', mode: 'operator' },
        auth: { token: TOKEN },
        device: { id: 'smoke-device', nonce, signature: 'test', signedAt: Date.now(), publicKey: 'test' },
        minProtocol: 1,
        maxProtocol: 3,
        scopes: ['chat'],
        caps: [],
        commands: [],
        permissions: {},
        locale: 'zh-CN',
      });
      sessionKey = res.mainSessionKey;
      console.log('[connect] OK, sessionKey:', sessionKey);

      // health + history + sessions (client bootstrap calls)
      await rpc('health', {});
      await rpc('chat.history', { sessionKey });
      await rpc('sessions.list', { limit: 50 });
      console.log('[bootstrap] health/history/sessions OK');

      if (MODE === 'node-tool') {
        // Attach a node session first.
        const nodeWs = new WebSocket(URL);
        await new Promise((r) => nodeWs.on('open', r));
        nodeWs.on('message', (d) => {
          const f = JSON.parse(d.toString());
          if (f.type === 'event' && f.event === 'connect.challenge') {
            nodeWs.send(frame('req', 'n1', 'connect', {
              role: 'node',
              client: { id: 'smoke-node', version: '0.1', platform: 'node', mode: 'node' },
              auth: { token: TOKEN },
              minProtocol: 1, maxProtocol: 3, scopes: ['node'], caps: [], commands: [],
              permissions: {}, locale: 'zh-CN',
            }));
          } else if (f.type === 'res' && f.id === 'n1') {
            console.log('[node connect] OK');
            // Now ask the model to use the device tool.
            void sendChat();
          } else if (f.type === 'event' && f.event === 'node.invoke.request') {
            console.log('[node.invoke.request]', JSON.stringify(f.payload).slice(0, 200));
            nodeWs.send(frame('req', 'n2', 'node.invoke.result', {
              id: f.payload.id,
              ok: true,
              payload: { result: 'device executed: ' + f.payload.command },
            }));
            console.log('[node.invoke.result] sent');
          }
        });
        nodeWs.on('error', (e) => console.error('[node ws error]', e.message));
        await new Promise((r) => setTimeout(r, 300));
        // The chat is triggered from node connect handler above.
      } else {
        await sendChat();
      }
    } catch (e) {
      console.error('[connect failed]', e.message);
      process.exit(1);
    }
  }

  async function sendChat() {
    try {
      const res = await rpc('chat.send', { text: '请用一句话介绍你自己，并说明你是否运行在 HarmonyOS 设备上', sessionKey });
      console.log('[chat.send] OK runId:', res.runId);
      // Wait for chat final event.
      await new Promise((r) => setTimeout(r, 45000));
      console.log('--- events collected ---');
      for (const e of events) {
        console.log(`  ${e.event}:`, JSON.stringify(e.payload).slice(0, 300));
      }
      process.exit(0);
    } catch (e) {
      console.error('[chat.send failed]', e.message);
      process.exit(1);
    }
  }

  ws.on('error', (e) => console.error('[ws error]', e.message));
  ws.on('open', () => console.log('[connected]', URL));
}

main();
