/**
 * Session registry for the bridge: tracks connected operator/node sessions
 * and the pending node.invoke tool-call futures.
 */
export class SessionRegistry {
    operator = null;
    node = null;
    pendingInvokes = new Map();
    /** Attach a connection under a role; replaces any previous session of that role. */
    attach(session) {
        if (session.role === 'operator')
            this.operator = session;
        else
            this.node = session;
    }
    detach(connId) {
        if (this.operator?.connId === connId)
            this.operator = null;
        if (this.node?.connId === connId)
            this.node = null;
        // Cancel invokes owned by this connection (they can only be node).
        if (this.node === null || this.node.connId !== connId) {
            for (const [id, pending] of this.pendingInvokes) {
                clearTimeout(pending.timer);
                pending.resolve({ ok: false, error: { code: 'SESSION_LOST', message: 'node session disconnected' } });
                this.pendingInvokes.delete(id);
            }
        }
    }
    getOperator() {
        return this.operator;
    }
    getNode() {
        return this.node;
    }
    /** Register a pending invoke and return a promise resolved by complete(). */
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
        if (!pending)
            return false;
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
