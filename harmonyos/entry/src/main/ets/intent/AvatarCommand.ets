/**
 * AvatarCommand — shared avatar.command payload types.
 *
 * ArkTS forbids untyped object literals, so every avatar command payload is
 * built from these explicitly declared interfaces. `sequence` carries ordered
 * steps; each step applies one action (setState / setBubble / clearBubble /
 * moveTo / playSound / tts) after `delayMs`.
 */

export interface AvatarStep {
  action: string;
  params: Record<string, Object>;
  delayMs: number;
}

export interface AvatarSequence {
  action: string;
  params: Record<string, Object>;
}

/** Build a params Record from parallel key/value arrays (avoids untyped literals). */
export function paramsOf(keys: string[], values: Object[]): Record<string, Object> {
  const p: Record<string, Object> = {};
  const n = keys.length < values.length ? keys.length : values.length;
  for (let i = 0; i < n; i++) p[keys[i]] = values[i];
  return p;
}

/** Build one step with typed fields. */
export function stepOf(action: string, params: Record<string, Object>, delayMs: number): AvatarStep {
  return { action: action, params: params, delayMs: delayMs };
}

/** Serialize a step sequence as an avatar.command payload. */
export function sequencePayload(steps: AvatarStep[]): string {
  const params: Record<string, Object> = {};
  params.steps = steps;
  const seq: AvatarSequence = { action: 'sequence', params: params };
  return JSON.stringify(seq);
}
