/**
 * Mock ilink server for end-to-end wechat bridge testing.
 * Simulates POST /ilink/bot/getupdates and /ilink/bot/sendmessage.
 */
import http from 'node:http';

const PORT = 18333;
let updatesCursor = 0;
const outbound = []; // messages sent by the bot (sendmessage)

// One simulated inbound message after the first poll.
const simulated = [
  { message_id: 1001, seq: 1, from_user_id: 'user-001', to_user_id: 'bot', message_type: 1, context_token: 'ctx-1', item_list: [{ type: 1, content: '你好，请用一句话介绍你自己' }] },
];

const server = http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', () => {
    let payload = {};
    try { payload = JSON.parse(body); } catch { /* ignore */ }
    res.setHeader('Content-Type', 'application/json');

    if (req.url === '/ilink/bot/getupdates') {
      const resp = { ret: 0, errcode: 0, get_updates_buf: 'cursor-' + (++updatesCursor), msgs: updatesCursor === 1 ? simulated : [] };
      res.end(JSON.stringify(resp));
    } else if (req.url === '/ilink/bot/sendmessage') {
      outbound.push(payload);
      console.log('[mock-ilink] sendmessage received:', JSON.stringify(payload).slice(0, 200));
      res.end(JSON.stringify({ ret: 0, errcode: 0 }));
    } else {
      res.end(JSON.stringify({ ret: -1, errcode: 0 }));
    }
  });
});

server.listen(PORT, () => {
  console.log(`[mock-ilink] listening on ${PORT}`);
  console.log('inbound message queued: 你好，请用一句话介绍你自己');
});

// After 20s, print outbound and exit.
setTimeout(() => {
  console.log('--- outbound messages ---');
  for (const m of outbound) {
    const content = m.content || [];
    const text = content.map((c) => c.content || '').join('');
    console.log('reply:', JSON.stringify(text).slice(0, 200));
  }
  process.exit(0);
}, 25000);
