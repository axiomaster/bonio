/** Session registry for the bridge. */
export class SessionRegistry {
  constructor() {
    this.operator = null;
    this.node = null;
    this.pendingInvokes = new Map();
  }
  attach(session) {
    if (session.role === 'operator') this.operator = session;
    else this.node = session;
  }
  detach(connId) {
    if (this.operator && this.operator.connId === connId) this.operator = null;
    if (this.node && this.node.connId === connId) this.node = null;
    if (this.node === null || this.node.connId !== connId) {
      for (const [id, pending] of this.pendingInvokes) {
        clearTimeout(pending.timer);
        pending.resolve({ ok: false, error: { code: 'SESSION_LOST', message: 'node session disconnected' } });
        this.pendingInvokes.delete(id);
      }
    }
  }
  getOperator() { return this.operator; }
  getNode() { return this.node; }
  registerInvoke(callId, timeoutMs) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.pendingInvokes.delete(callId);
        resolve({ ok: false, error: { code: 'TOOL_TIMEOUT', message: 'node.invoke.request timed out' } });
      }, timeoutMs);
      this.pendingInvokes.set(callId, { resolve, timer });
    });
  }
  completeInvoke(callId, result) {
    const pending = this.pendingInvokes.get(callId);
    if (!pending) return false;
    clearTimeout(pending.timer);
    this.pendingInvokes.delete(callId);
    pending.resolve(result);
    return true;
  }
  cancelAll() {
    for (const [id, pending] of this.pendingInvokes) {
      clearTimeout(pending.timer);
      pending.resolve({ ok: false, error: { code: 'SHUTDOWN', message: 'bridge shutting down' } });
      this.pendingInvokes.delete(id);
    }
  }
}
