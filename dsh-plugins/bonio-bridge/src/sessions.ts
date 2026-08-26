/**
 * Session registry for the bridge: tracks connected operator/node sessions
 * and the pending node.invoke tool-call futures.
 */

export interface ClientSession {
  /** ws connection id (unique per socket) */
  connId: string;
  role: 'operator' | 'node';
  /** client-provided identity (connect params.client.id) */
  clientId?: string;
  /** server-assigned session key (operator only) */
  sessionKey?: string;
}

interface PendingInvoke {
  resolve: (result: { ok: boolean; payload?: Record<string, unknown>; error?: { code: string; message: string } }) => void;
  timer: NodeJS.Timeout;
}

export class SessionRegistry {
  private operator: ClientSession | null = null;
  private node: ClientSession | null = null;
  private pendingInvokes = new Map<string, PendingInvoke>();

  /** Attach a connection under a role; replaces any previous session of that role. */
  attach(session: ClientSession): void {
    if (session.role === 'operator') this.operator = session;
    else this.node = session;
  }

  detach(connId: string): void {
    if (this.operator?.connId === connId) this.operator = null;
    if (this.node?.connId === connId) this.node = null;
    // Cancel invokes owned by this connection (they can only be node).
    if (this.node === null || this.node.connId !== connId) {
      for (const [id, pending] of this.pendingInvokes) {
        clearTimeout(pending.timer);
        pending.resolve({ ok: false, error: { code: 'SESSION_LOST', message: 'node session disconnected' } });
        this.pendingInvokes.delete(id);
      }
    }
  }

  getOperator(): ClientSession | null {
    return this.operator;
  }

  getNode(): ClientSession | null {
    return this.node;
  }

  /** Register a pending invoke and return a promise resolved by complete(). */
  registerInvoke(callId: string, timeoutMs: number): Promise<{ ok: boolean; payload?: Record<string, unknown>; error?: { code: string; message: string } }> {
    return new Promise((resolve) => {
      const timer = setTimeout(() => {
        this.pendingInvokes.delete(callId);
        resolve({ ok: false, error: { code: 'TOOL_TIMEOUT', message: 'node.invoke.request timed out' } });
      }, timeoutMs);
      this.pendingInvokes.set(callId, { resolve, timer });
    });
  }

  completeInvoke(callId: string, result: { ok: boolean; payload?: Record<string, unknown>; error?: { code: string; message: string } }): boolean {
    const pending = this.pendingInvokes.get(callId);
    if (!pending) return false;
    clearTimeout(pending.timer);
    this.pendingInvokes.delete(callId);
    pending.resolve(result);
    return true;
  }

  cancelAll(): void {
    for (const [id, pending] of this.pendingInvokes) {
      clearTimeout(pending.timer);
      pending.resolve({ ok: false, error: { code: 'SHUTDOWN', message: 'bridge shutting down' } });
      this.pendingInvokes.delete(id);
    }
  }
}
