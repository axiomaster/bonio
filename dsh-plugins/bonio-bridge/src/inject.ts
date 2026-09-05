/**
 * Magic Cue input injection, executed as root on-device.
 *
 * Validated recipe (real device, WeChat chat page): click the chat input at
 * its PRE-keyboard coordinates, type with `uitest uiInput text` (Chinese OK),
 * then tap the send button. The keyboard relocates the input row upward, so
 * the send point must be learned AFTER the keyboard opens.
 *
 * The flow is deliberately FIXED — no per-step layout recognition (too slow).
 * The caller passes a previously learned send point; only when it has none do
 * we dumpLayout once to discover it, and the discovered point is returned so
 * the app can cache it per chat app and never dump again.
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';

const run = promisify(execFile);
const UITEST = '/bin/uitest';
const AA = '/bin/aa';
const LAYOUT_PATH = '/data/local/tmp/bonio-cue-layout.json';

const sleep = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

export interface InjectOptions {
  /** Text to type into the focused chat input. */
  text: string;
  /** Chat input center in physical px, captured before the keyboard opens. */
  inputX?: number;
  inputY?: number;
  /** Learned send-button center; when absent it is discovered once via dumpLayout. */
  sendX?: number;
  sendY?: number;
  /** false = focus+type only, never tap send. */
  send?: boolean;
}

export interface InjectResult {
  ok: boolean;
  stage: 'find-input' | 'click-input' | 'type' | 'find-send' | 'click-send';
  /** Input point actually used; NEW when discovered this call (caller caches). */
  inputPoint?: { x: number; y: number; learned?: boolean };
  /** Send point actually used; NEW when discovered this call (caller caches). */
  sendPoint?: { x: number; y: number; learned?: boolean };
  error?: string;
}

interface LayoutNode {
  attributes?: Record<string, unknown>;
  children?: LayoutNode[];
}

/** Center of the send button from the live layout; null when absent. */
async function findSendPoint(): Promise<{ x: number; y: number } | null> {
  try {
    await run(UITEST, ['dumpLayout', '-p', LAYOUT_PATH]);
    const root = JSON.parse(await fs.readFile(LAYOUT_PATH, 'utf8')) as LayoutNode | LayoutNode[];
    let point: { x: number; y: number } | null = null;
    const walk = (node: LayoutNode | LayoutNode[]): void => {
      if (Array.isArray(node)) { node.forEach(walk); return; }
      if (!node || typeof node !== 'object') return;
      const at = node.attributes ?? {};
      const text = typeof at.text === 'string' ? at.text.trim() : '';
      // The 发送 label itself reports clickable:false (its parent Button owns
      // the hit test), but tapping the label's coordinates still delivers.
      if ((text === '发送' || /^send$/i.test(text)) && typeof at.bounds === 'string') {
        const m = at.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        if (m) point = { x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2) };
      }
      for (const child of node.children ?? []) walk(child);
    };
    walk(root);
    return point;
  } catch {
    return null;
  }
}

/**
 * Center of the chat input row from the PRE-keyboard layout; null when absent.
 * Matches editable node types (WeChat's input is a RichEditor) and picks the
 * lowest one — the chat input bar sits at the bottom of the page. Also reports
 * whether an IME panel is open: a keyboard relocates the input upward, so a
 * point learned in that state must NOT be cached for later runs.
 */
async function findInputPoint(): Promise<{ point: { x: number; y: number } | null; keyboardOpen: boolean }> {
  try {
    await run(UITEST, ['dumpLayout', '-p', LAYOUT_PATH]);
    const root = JSON.parse(await fs.readFile(LAYOUT_PATH, 'utf8')) as LayoutNode | LayoutNode[];
    let best: { x: number; y: number } | null = null;
    let keyboardOpen = false;
    const INPUT_TYPES = ['RichEditor', 'TextInput', 'TextArea', 'EditText', 'Search'];
    const walk = (node: LayoutNode | LayoutNode[]): void => {
      if (Array.isArray(node)) { node.forEach(walk); return; }
      if (!node || typeof node !== 'object') return;
      const at = node.attributes ?? {};
      const type = typeof at.type === 'string' ? at.type : '';
      const key = typeof at.key === 'string' ? at.key : '';
      if (/inputMethodPanel|imePanel/i.test(key)) keyboardOpen = true;
      if (INPUT_TYPES.includes(type) && typeof at.bounds === 'string') {
        const m = at.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
        if (m) {
          const center = { x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2) };
          if (!best || center.y > best.y) best = center;
        }
      }
      for (const child of node.children ?? []) walk(child);
    };
    walk(root);
    return { point: best, keyboardOpen };
  } catch {
    return { point: null, keyboardOpen: false };
  }
}

export async function injectAndSend(options: InjectOptions): Promise<InjectResult> {
  try {
    let inputPoint: { x: number; y: number } | undefined
      = typeof options.inputX === 'number' && typeof options.inputY === 'number'
        ? { x: Math.round(options.inputX), y: Math.round(options.inputY) }
        : undefined;
    let inputLearned = false;
    if (!inputPoint) {
      // No cached point: discover once from the live layout (keyboard closed
      // in the normal case). The caller caches it, so this dump is one-time.
      const found = await findInputPoint();
      inputLearned = true;
      inputPoint = found.point ?? undefined;
      if (!inputPoint) return { ok: false, stage: 'find-input', error: 'chat input not found in live layout' };
      // A keyboard relocates the input row; a point learned with the keyboard
      // open is wrong for later cold runs, so mark it non-cacheable.
      if (found.keyboardOpen) inputLearned = false;
    }
    await run(UITEST, ['uiInput', 'click', String(inputPoint.x), String(inputPoint.y)]);
    await sleep(800); // keyboard animation
    await run(UITEST, ['uiInput', 'text', options.text]);
    await sleep(600);
    if (options.send === false) return { ok: true, stage: 'type', inputPoint: { ...inputPoint, learned: inputLearned } };

    let sendPoint: { x: number; y: number } | undefined
      = typeof options.sendX === 'number' && typeof options.sendY === 'number'
        ? { x: Math.round(options.sendX), y: Math.round(options.sendY) }
        : undefined;
    let learned = false;
    if (!sendPoint) {
      sendPoint = (await findSendPoint()) ?? undefined;
      learned = true;
      if (!sendPoint) return { ok: false, stage: 'find-send', error: 'send button not found in live layout' };
    }
    await run(UITEST, ['uiInput', 'click', String(sendPoint.x), String(sendPoint.y)]);
    await sleep(300);
    return {
      ok: true,
      stage: 'click-send',
      inputPoint: { ...inputPoint, learned: inputLearned },
      sendPoint: { ...sendPoint, learned },
    };
  } catch (error) {
    return { ok: false, stage: 'click-send', error: error instanceof Error ? error.message : String(error) };
  }
}

/** Launch an app by bundle (+ ability). Calendar: com.huawei.hmos.calendar/MainAbility. */
export async function openApp(bundle: string, ability?: string): Promise<{ ok: boolean; error?: string }> {
  try {
    await run(AA, ['start', '-b', bundle, '-a', ability ?? 'MainAbility']);
    return { ok: true };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}
