// Magic Cue end-to-end test: connect as operator, send a chat.send that asks
// the LLM to look up a contact via contacts.search, and stream the reply.
// The app (already connected as the node session) must handle the
// node.invoke.request and return real data.
import WebSocket from 'ws';
const URL = process.env.BRIDGE_URL || 'ws://127.0.0.1:10724';
const TOKEN = process.env.BRIDGE_TOKEN || 'bonio-local-token';

const prompt = process.argv[2] || '请用 contacts.search 工具查询通讯录里姓"张"的联系人，并把第一个人的姓名和电话用 JSON 格式 {"cues":[{"kind":"contact","title":"联系人","content":"姓名：电话"}]} 输出。如果查不到就输出 {"cues":[]}';

const ws = new WebSocket(URL);
const pending = new Map();
let seq = 0;
let done = false;

const rpc = (method, params) => new Promise((resolve, reject) => {
  const id = `r${++seq}`;
  pending.set(id, { resolve, reject, method });
  ws.send(JSON.stringify({ type: 'req', id, method, params }));
});

const finish = (code, msg) => {
  if (done) return;
  done = true;
  console.log(`\n[RESULT] ${code}: ${msg}`);
  setTimeout(() => process.exit(code === 'OK' ? 0 : 1), 200);
};

ws.on('message', (data) => {
  const f = JSON.parse(data.toString());
  if (f.type === 'event' && f.event === 'connect.challenge') {
    void (async () => {
      await rpc('connect', { role: 'operator', auth: { token: TOKEN }, client: { id: 'magic-cue-e2e' } });
      console.log('[connect] ok');
      const res = await rpc('chat.send', {
        message: prompt,
        sessionKey: 'system:magic-cue',
        idempotencyKey: `e2e-${Date.now()}`,
        thinking: 'low',
      });
      console.log('[chat.send]', JSON.stringify(res));
    })();
  } else if (f.type === 'event' && f.event === 'agent') {
    const d = f.payload?.data;
    if (d?.text) process.stdout.write(d.text);
  } else if (f.type === 'event' && f.event === 'chat') {
    const p = f.payload || {};
    if (p.sessionKey !== 'system:magic-cue') return;
    if (p.state === 'final') {
      finish('OK', `final message: ${JSON.stringify(p.message ?? p.text ?? p)}`);
    } else if (p.state === 'error' || p.state === 'aborted') {
      finish('FAIL', `run ended ${p.state}: ${JSON.stringify(p)}`);
    }
  } else if (f.type === 'res') {
    const p = pending.get(f.id);
    if (p) {
      pending.delete(f.id);
      if (f.ok) p.resolve(f.payload);
      else finish('FAIL', `${p.method}: ${f.error?.message}`);
    }
  }
});

setTimeout(() => finish('TIMEOUT', 'no final within 90s'), 90000);
