// Focused tool-call test: attach node session, then ask model to use device tool.
import WebSocket from 'ws';
const URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:10724';
const TOKEN = process.env.BRIDGE_TOKEN || 'test-token-123';

function frame(type, id, method, params) { return JSON.stringify({ type, id, method, params }); }

async function main() {
  // --- node session ---
  const nodeWs = new WebSocket(URL);
  await new Promise((r) => nodeWs.on('open', r));
  nodeWs.on('message', (d) => {
    const f = JSON.parse(d.toString());
    if (f.type === 'event' && f.event === 'connect.challenge') {
      nodeWs.send(frame('req', 'n1', 'connect', {
        role: 'node',
        client: { id: 'smoke-node', version: '0.1', platform: 'node', mode: 'node' },
        auth: { token: TOKEN },
        minProtocol: 1, maxProtocol: 3, scopes: ['node'], caps: [], commands: [], permissions: {}, locale: 'zh-CN',
      }));
    } else if (f.type === 'res' && f.id === 'n1') {
      console.log('[node session] connected');
    } else if (f.type === 'event' && f.event === 'node.invoke.request') {
      console.log('[NODE.INVOKE.REQUEST]', JSON.stringify(f.payload));
      nodeWs.send(frame('req', 'n2', 'node.invoke.result', {
        id: f.payload.id, ok: true,
        payload: { simulated: true, result: 'device executed ' + f.payload.command + ' with ' + JSON.stringify(f.payload.params) },
      }));
      console.log('[node.invoke.result] sent');
    }
  });
  nodeWs.on('error', (e) => console.error('[node ws err]', e.message));
  await new Promise((r) => setTimeout(r, 500));

  // --- operator session ---
  const ws = new WebSocket(URL);
  const pending = new Map();
  let seq = 0;
  const rpc = (method, params) => new Promise((resolve, reject) => {
    const id = `r${++seq}`;
    pending.set(id, { resolve, reject, method });
    ws.send(frame('req', id, method, params));
  });
  const agentEvents = [];
  ws.on('message', (data) => {
    const f = JSON.parse(data.toString());
    if (f.type === 'event') {
      if (f.event === 'connect.challenge') {
        void rpc('connect', {
          role: 'operator', client: { id: 'smoke-op', version: '0.1', platform: 'node', mode: 'operator' },
          auth: { token: TOKEN }, minProtocol: 1, maxProtocol: 3, scopes: ['chat'], caps: [],
          commands: [], permissions: {}, locale: 'zh-CN',
        }).then(() => {
          console.log('[operator] connected, sending chat with device-tool prompt');
          return rpc('chat.send', { text: '请使用设备工具 bonio.node.invoke 执行 command=camera.snap（参数为空对象），然后告诉我设备返回的结果。务必调用该工具。', sessionKey: 'main-x' });
        }).then((res) => console.log('[chat.send] runId:', res.runId));
      } else if (f.event === 'agent' || f.event === 'chat') {
        agentEvents.push(f);
        console.log(`[${f.event}]`, JSON.stringify(f.payload).slice(0, 180));
      }
    } else if (f.type === 'res') {
      const p = pending.get(f.id);
      if (p) { pending.delete(f.id); f.ok ? p.resolve(f.payload) : p.reject(new Error(f.error?.message)); }
    }
  });
  ws.on('error', (e) => console.error('[op ws err]', e.message));
  await new Promise((r) => setTimeout(r, 60000));
  console.log('--- done, agent events:', agentEvents.length);
  process.exit(0);
}
main();
