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
const PROXY_IME = '/data/local/bin/bonio-proxy-ime';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function hasProxyIme() {
    try {
        await fs.access(PROXY_IME, fs.constants.X_OK);
        return true;
    }
    catch {
        return false;
    }
}
/** Center of the send button from the live layout; null when absent. */
async function findSendPoint() {
    try {
        await run(UITEST, ['dumpLayout', '-p', LAYOUT_PATH]);
        const root = JSON.parse(await fs.readFile(LAYOUT_PATH, 'utf8'));
        let point = null;
        const match = (val) => val === '发送' || /^(发送|send|发送消息|点击发送)$/i.test(val);
        const walk = (node) => {
            if (Array.isArray(node)) {
                node.forEach(walk);
                return;
            }
            if (!node || typeof node !== 'object')
                return;
            const at = node.attributes ?? {};
            const text = typeof at.text === 'string' ? at.text.trim() : '';
            const desc = typeof at.description === 'string' ? at.description.trim() : '';
            const orig = typeof at.originalText === 'string' ? at.originalText.trim() : '';
            // The 发送 label itself reports clickable:false (its parent Button owns
            // the hit test), but tapping the label's coordinates still delivers.
            if ((match(text) || match(desc) || match(orig)) && typeof at.bounds === 'string') {
                const m = at.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
                if (m)
                    point = { x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2) };
            }
            for (const child of node.children ?? [])
                walk(child);
        };
        walk(root);
        return point;
    }
    catch {
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
async function findInputPoint() {
    try {
        await run(UITEST, ['dumpLayout', '-p', LAYOUT_PATH]);
        const root = JSON.parse(await fs.readFile(LAYOUT_PATH, 'utf8'));
        let best = null;
        let keyboardOpen = false;
        const INPUT_TYPES = ['RichEditor', 'TextInput', 'TextArea', 'EditText', 'Search'];
        const walk = (node) => {
            if (Array.isArray(node)) {
                node.forEach(walk);
                return;
            }
            if (!node || typeof node !== 'object')
                return;
            const at = node.attributes ?? {};
            const type = typeof at.type === 'string' ? at.type : '';
            const key = typeof at.key === 'string' ? at.key : '';
            if (/inputMethodPanel|imePanel/i.test(key))
                keyboardOpen = true;
            if (INPUT_TYPES.includes(type) && typeof at.bounds === 'string') {
                const m = at.bounds.match(/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/);
                if (m) {
                    const center = { x: Math.round((+m[1] + +m[3]) / 2), y: Math.round((+m[2] + +m[4]) / 2) };
                    if (!best || center.y > best.y)
                        best = center;
                }
            }
            for (const child of node.children ?? [])
                walk(child);
        };
        walk(root);
        return { point: best, keyboardOpen };
    }
    catch {
        return { point: null, keyboardOpen: false };
    }
}
export async function injectAndSend(options) {
    try {
        let inputPoint;
        let inputLearned = false;
        // Dynamically locate the input box from the live view tree
        const foundInput = await findInputPoint();
        if (foundInput.point) {
            inputPoint = foundInput.point;
            inputLearned = true;
            if (foundInput.keyboardOpen)
                inputLearned = false;
        }
        else if (typeof options.inputX === 'number' && typeof options.inputY === 'number') {
            inputPoint = { x: Math.round(options.inputX), y: Math.round(options.inputY) };
        }
        if (!inputPoint) {
            return { ok: false, stage: 'find-input', error: 'chat input not found in live layout' };
        }
        // Fast path: use OpenHarmony IMF ProxyIME to silently inject without opening keyboard
        if (await hasProxyIme()) {
            const args = ['--text', options.text];
            if (inputPoint) {
                args.push('--input', String(inputPoint.x), String(inputPoint.y));
            }
            // Inject text first via ProxyIME without sending
            args.push('--no-send');
            await run(PROXY_IME, args);
            if (options.send === false) {
                return { ok: true, stage: 'type', inputPoint: { ...inputPoint, learned: inputLearned } };
            }
            // Allow UI a moment to update and render the send button (switch from '+' to '发送')
            await sleep(150);
            // Dynamically locate the real Send button from the live view tree
            const sendPoint = await findSendPoint();
            if (!sendPoint) {
                return { ok: false, stage: 'find-send', error: 'send button not found in live layout after inject' };
            }
            await run(UITEST, ['uiInput', 'click', String(sendPoint.x), String(sendPoint.y)]);
            await sleep(200);
            return {
                ok: true,
                stage: 'click-send',
                inputPoint: { ...inputPoint, learned: inputLearned },
                sendPoint: { ...sendPoint, learned: true },
            };
        }
        // Fallback path: uitest keyboard typing (if proxy ime unavailable)
        await run(UITEST, ['uiInput', 'click', String(inputPoint.x), String(inputPoint.y)]);
        await sleep(800); // keyboard animation
        await run(UITEST, ['uiInput', 'text', options.text]);
        await sleep(600);
        if (options.send === false)
            return { ok: true, stage: 'type', inputPoint: { ...inputPoint, learned: inputLearned } };
        const sendPoint = await findSendPoint();
        if (!sendPoint)
            return { ok: false, stage: 'find-send', error: 'send button not found in live layout' };
        await run(UITEST, ['uiInput', 'click', String(sendPoint.x), String(sendPoint.y)]);
        await sleep(300);
        return {
            ok: true,
            stage: 'click-send',
            inputPoint: { ...inputPoint, learned: inputLearned },
            sendPoint: { ...sendPoint, learned: true },
        };
    }
    catch (error) {
        return { ok: false, stage: 'click-send', error: error instanceof Error ? error.message : String(error) };
    }
}
/** Launch an app by bundle (+ ability). Calendar: com.huawei.hmos.calendar/MainAbility. */
export async function openApp(bundle, ability) {
    try {
        await run(AA, ['start', '-b', bundle, '-a', ability ?? 'MainAbility']);
        return { ok: true };
    }
    catch (error) {
        return { ok: false, error: error instanceof Error ? error.message : String(error) };
    }
}
