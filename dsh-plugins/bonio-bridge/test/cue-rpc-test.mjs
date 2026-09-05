import WebSocket from 'ws';
const URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:10724';
const TOKEN = process.env.BRIDGE_TOKEN || 'bonio-local-token';
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
  if (f.type === 'event' && f.event === 'connect.challenge') {
    void (async () => {
      try {
        await rpc('connect', { role: 'operator', auth: { token: TOKEN }, client: { id: 'cue-test' } });
        console.log('[connect] ok');
        const method = process.argv[2] || 'cue.inject';
        const t0 = Date.now();
        const res = await rpc(method, JSON.parse(process.argv[3] || '{}'));
        console.log(`[${method}] ${(Date.now() - t0)}ms`, JSON.stringify(res));
        process.exit(0);
      } catch (e) { console.error('[FAILED]', e.message); process.exit(1); }
    })();
  } else if (f.type === 'res') {
    const p = pending.get(f.id);
    if (p) { pending.delete(f.id); f.ok ? p.resolve(f.payload) : p.reject(new Error(`${p.method}: ${f.error?.message}`)); }
  }
});
setTimeout(() => { console.log('[TIMEOUT]'); process.exit(2); }, 60000);
