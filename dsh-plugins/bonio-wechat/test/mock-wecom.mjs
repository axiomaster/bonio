/**
 * Mock WeCom server for testing the wecom WebSocket client.
 * Simulates wss://openws.work.weixin.qq.com aibot protocol:
 *  - accepts connection, waits for aibot_subscribe
 *  - sends one aibot_msg_callback (simulated user message)
 *  - prints received aibot_respond_msg replies
 */
import { WebSocketServer } from 'ws';

const PORT = 18335;

const wss = new WebSocketServer({ port: PORT, host: '127.0.0.1' });

wss.on('connection', (ws) => {
  console.log('[mock-wecom] client connected');
  ws.on('message', (data) => {
    const text = data.toString();
    try {
      const frame = JSON.parse(text);
      if (frame.cmd === 'aibot_subscribe') {
        console.log('[mock-wecom] subscribe received, bot_id=' + (frame.body?.bot_id || '?'));
        // Send a simulated inbound message
        const callback = {
          cmd: 'aibot_msg_callback',
          headers: { req_id: 'mock-req-001' },
          body: {
            msgid: 'mock-msg-001',
            chatid: 'chat-001',
            chattype: 'single',
            from: { userid: 'wecom-user-1' },
            msgtype: 'text',
            text: { content: '你好，请介绍你自己' },
          },
        };
        ws.send(JSON.stringify(callback));
        console.log('[mock-wecom] sent aibot_msg_callback');
      } else if (frame.cmd === 'aibot_respond_msg') {
        console.log('[mock-wecom] reply received:', JSON.stringify(frame.body?.stream?.content || '').slice(0, 120));
      }
    } catch (e) {
      console.log('[mock-wecom] frame error:', e.message);
    }
  });
  ws.on('close', () => console.log('[mock-wecom] client disconnected'));
});

console.log(`[mock-wecom] listening on ${PORT}`);

// Exit after 25s
setTimeout(() => {
  console.log('[mock-wecom] done');
  process.exit(0);
}, 25000);
