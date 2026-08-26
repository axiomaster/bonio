/**
 * hiclaw-compatible wire protocol types and frame helpers.
 *
 * Frame shapes (from bonio-app GatewaySession.ets and hiclaw gateway.cpp):
 *   req   : { type: 'req',  id, method, params }
 *   res   : { type: 'res',  id, ok, payload?, error? }
 *   event : { type: 'event', event, payload }
 *
 * Session roles: 'operator' (chat/config) and 'node' (server-initiated tool calls).
 */
export type FrameType = 'req' | 'res' | 'event';

export interface ReqFrame {
  type: 'req';
  id: string;
  method: string;
  params: Record<string, unknown>;
}

export interface ResFrame {
  type: 'res';
  id: string;
  ok: boolean;
  payload?: Record<string, unknown>;
  error?: { code: string; message: string };
}

export interface EventFrame {
  type: 'event';
  event: string;
  payload: Record<string, unknown>;
}

export type Frame = ReqFrame | ResFrame | EventFrame;

/** Parse a raw text frame; returns null on invalid JSON or unknown shape. */
export function parseFrame(text: string): Frame | null {
  try {
    const obj = JSON.parse(text) as Frame;
    if (obj && typeof obj === 'object' && obj.type) return obj;
  } catch {
    /* ignore */
  }
  return null;
}

export function resOk(id: string, payload: Record<string, unknown> = {}): ResFrame {
  return { type: 'res', id, ok: true, payload };
}

export function resErr(id: string, code: string, message: string): ResFrame {
  return { type: 'res', id, ok: false, error: { code, message } };
}

export function eventFrame(event: string, payload: Record<string, unknown> = {}): EventFrame {
  return { type: 'event', event, payload };
}

export function stringify(frame: Frame): string {
  return JSON.stringify(frame);
}
