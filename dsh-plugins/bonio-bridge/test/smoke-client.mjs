/**
 * Smoke test client simulating bonio-app's hiclaw protocol against the
 * bonio-bridge gateway (ws://127.0.0.1:10724).
 * Uses the exact field names bonio-app sends (message, sessionKey, etc.).
 */
import WebSocket from 'ws';

const URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:10724';
const TOKEN = process.env.BRIDGE_TOKEN || 'bonio-local-token';

function frame(type, id, method, params) {
  return JSON.stringify({ type, id, method, params });
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
      if (f.event === 'connect.challenge') void connect(f.payload.nonce);
      else if (f.event === 'agent' || f.event === 'chat') events.push(f);
    } else if (f.type === 'res') {
      const p = pending.get(f.id);
      if (p) { pending.delete(f.id); f.ok ? p.resolve(f.payload) : p.reject(new Error(`${p.method}: ${f.error?.message}`)); }
    }
  });

  async function connect(nonce) {
    try {
      const res = await rpc('connect', {
        role: 'operator',
        client: { id: 'smoke-test', version: '0.1', platform: 'harmonyos', mode: 'operator' },
        auth: { token: TOKEN },
        device: { id: 'smoke-device', nonce, signature: 'test', signedAt: Date.now(), publicKey: 'test' },
        minProtocol: 1, maxProtocol: 3, scopes: ['chat'], caps: [], commands: [],
        permissions: {}, locale: 'zh-CN',
      });
      sessionKey = res?.snapshot?.sessionDefaults?.mainSessionKey || 'main';
      console.log('[connect] OK sessionKey:', sessionKey);
      await rpc('health', {});
      await rpc('chat.history', { sessionKey });
      await rpc('sessions.list', { limit: 50 });
      console.log('[bootstrap] health/history/sessions OK');

      // Round 1
      await sendChat('记住我的名字叫小明', '1');
      // Round 2 — same sessionKey, tests multi-turn continuity
      await sendChat('我叫什么名字？', '2');
      // History after two turns
      const hist = await rpc('chat.history', { sessionKey });
      const messages = hist?.messages ?? [];
      console.log(`[chat.history] ${messages.length} messages`);
      for (const m of messages.slice(-4)) {
        const text = (m.content ?? []).filter((b) => b.type === 'text').map((b) => b.text).join('').slice(0, 50);
        console.log(`  [${m.role}] ${text}`);
      }
      const sess = await rpc('sessions.list', { limit: 50 });
      console.log('[sessions.list]', JSON.stringify(sess?.sessions ?? []).slice(0, 200));
      process.exit(0);
    } catch (e) {
      console.error('[FAILED]', e.message);
      process.exit(1);
    }
  }

  async function sendChat(text, tag) {
    const runId = `client-run-${tag}-${Date.now()}`;
    try {
      const res = await rpc('chat.send', { sessionKey, message: text, thinking: 'off', timeoutMs: 60000, idempotencyKey: runId });
      console.log(`[chat.send #${tag}] OK runId:`, res?.runId || runId);
      await waitForFinal(res?.runId || runId);
    } catch (e) {
      console.error(`[chat.send #${tag} FAILED]`, e.message);
    }
  }

  async function waitForFinal(runId) {
    const deadline = Date.now() + 60000;
    while (Date.now() < deadline) {
      const final = events.find((e) => e.event === 'chat' && e.payload?.runId === runId && e.payload?.state === 'final');
      if (final) {
        console.log(`[chat final] ${(final.payload.text ?? '').slice(0, 80)}`);
        return;
      }
      await new Promise((r) => setTimeout(r, 500));
    }
    console.log('[TIMEOUT waiting final]');
  }

  ws.on('error', (e) => console.error('[ws error]', e.message));
  ws.on('open', () => console.log('[connected]', URL));
}

main();
