/**
 * One-shot chat probe: connect as operator, send ARGV[2] (default: battery
 * query) to sessionKey ARGV[3] (default: main), print streamed agent events,
 * exit on chat final. Usage: node one-shot.mjs ["msg"] [sessionKey]
 */
import WebSocket from 'ws';

const URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:10724';
const TOKEN = process.env.BRIDGE_TOKEN || 'bonio-local-token';
const MESSAGE = process.argv[2] || '查询手机电量';
const SESSION_KEY = process.argv[3] || 'main';

const ws = new WebSocket(URL);
const pending = new Map();
let seq = 0;

const rpc = (method, params) => new Promise((resolve, reject) => {
  const id = `r${++seq}`;
  pending.set(id, { resolve, reject, method });
  ws.send(JSON.stringify({ type: 'req', id, method, params }));
});

ws.on('message', (data) => {
  const f = JSON.parse(data.toString());
  if (f.type === 'event') {
    if (f.event === 'connect.challenge') void connect(f.payload.nonce);
    if (f.event === 'agent') {
      const d = f.payload ?? {};
      if (d.stream === 'assistant' && d.data?.text) {
        process.stdout.write('.');
      } else if (d.stream === 'tool') {
        console.log(`\n[tool] ${d.data?.phase} ${d.data?.name} ${JSON.stringify(d.data?.args ?? {}).slice(0, 120)}`);
      }
    }
    if (f.event === 'chat') {
      const d = f.payload ?? {};
      if (d.state === 'final' || d.state === 'error') {
        console.log(`\n[chat.${d.state}] ${(d.text || d.errorMessage || '').slice(0, 400)}`);
        process.exit(d.state === 'error' ? 1 : 0);
      }
    }
  } else if (f.type === 'res') {
    const p = pending.get(f.id);
    if (p) { pending.delete(f.id); f.ok ? p.resolve(f.payload) : p.reject(new Error(`${p.method}: ${f.error?.message}`)); }
  }
});

async function connect(nonce) {
  try {
    await rpc('connect', {
      role: 'operator',
      client: { id: 'one-shot', version: '0.1', platform: 'harmonyos', mode: 'operator' },
      auth: { token: TOKEN },
      device: { id: 'one-shot-device', nonce, signature: 'test', signedAt: Date.now(), publicKey: 'test' },
      minProtocol: 1, maxProtocol: 3, scopes: ['chat'], caps: [], commands: [],
      permissions: {}, locale: 'zh-CN',
    });
    console.log('[connect] OK; sending:', MESSAGE, '→', SESSION_KEY);
    const runId = `one-shot-${Date.now()}`;
    const res = await rpc('chat.send', { sessionKey: SESSION_KEY, message: MESSAGE, thinking: 'off', timeoutMs: 300000, idempotencyKey: runId });
    console.log('[chat.send] runId:', res?.runId || runId);
    setTimeout(() => { console.log('\n[TIMEOUT] no final within 240s'); process.exit(2); }, 240000);
  } catch (e) {
    console.error('[FAILED]', e.message);
    process.exit(1);
  }
}
