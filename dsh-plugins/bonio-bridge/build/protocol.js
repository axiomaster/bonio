/** hiclaw-compatible wire protocol types and frame helpers. */
export function parseFrame(text) {
  try {
    const obj = JSON.parse(text);
    if (obj && typeof obj === 'object' && obj.type) return obj;
  } catch { /* ignore */ }
  return null;
}
export function resOk(id, payload = {}) {
  return { type: 'res', id, ok: true, payload };
}
export function resErr(id, code, message) {
  return { type: 'res', id, ok: false, error: { code, message } };
}
export function eventFrame(event, payload = {}) {
  return { type: 'event', event, payload };
}
export function stringify(frame) {
  return JSON.stringify(frame);
}
