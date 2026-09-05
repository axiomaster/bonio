import { hilog } from '@kit.PerformanceAnalysisKit';
import { GatewaySession } from '../gateway/GatewaySession';

export const MAGIC_CUE_SESSION_KEY = 'system:magic-cue';

/** One recommended capsule. kind: contact | calendar | memo. */
export interface MagicCue {
  kind: string;
  title: string;
  content: string;
}

class MagicCueChatParams {
  sessionKey: string = MAGIC_CUE_SESSION_KEY;
  message: string = '';
  thinking: string = 'low';
  timeoutMs: number = 90000;
  idempotencyKey: string = '';
}

const MAX_CUES = 3;
const RUN_TIMEOUT_MS = 90000;
const MAX_PAYLOAD_LENGTH = 60000;

/**
 * One-shot Magic Cue analyzer. On double-tap it sends the current screen text
 * to an ephemeral DSH session and parses the JSON cue recommendations out of
 * the chat final — mirroring CompanionMemoryController's chat.send + final
 * pattern but stateless and request/response, not queued.
 */
export class MagicCueController {
  private static readonly DOMAIN = 0x3D00;
  private static readonly TAG = 'MagicCue';

  private readonly session: GatewaySession;
  private readonly isConnected: () => boolean;
  private activeRunId: string | undefined = undefined;
  private resolveActive: ((cues: MagicCue[]) => void) | undefined = undefined;
  private activeTimeout: number = -1;

  constructor(session: GatewaySession, isConnected: () => boolean) {
    this.session = session;
    this.isConnected = isConnected;
  }

  /** Analyze the current screen for an in-chat information request; resolve cues. */
  run(screenPayload: string, bundleName: string, title: string): Promise<MagicCue[]> {
    return new Promise((resolve: (cues: MagicCue[]) => void) => {
      if (!this.isConnected()) {
        hilog.warn(MagicCueController.DOMAIN, MagicCueController.TAG, 'Magic Cue run skipped: not connected');
        resolve([]);
        return;
      }
      this.cancelActive();
      this.resolveActive = resolve;
      this.activeTimeout = setTimeout(() => this.finish([]), RUN_TIMEOUT_MS);
      void this.startActive(screenPayload, bundleName, title);
    });
  }

  handleGatewayEvent(event: string, payloadJson: string | undefined): void {
    if ((event !== 'chat' && event !== 'agent') || !payloadJson || !this.resolveActive) return;
    try {
      const payload = JSON.parse(payloadJson) as Record<string, Object>;
      if (payload['sessionKey'] !== MAGIC_CUE_SESSION_KEY) return;
      const runId = payload['runId'] as string | undefined;
      if (this.activeRunId && runId !== this.activeRunId) return;
      if (event === 'agent') {
        // DSH is still streaming its analysis — keep the run alive so a long
        // multi-tool analysis is not killed by the idle timeout.
        this.resetTimeout();
        return;
      }
      const state = payload['state'] as string | undefined;
      if (state === 'started' && !this.activeRunId && runId) {
        this.activeRunId = runId;
      } else if (state === 'final') {
        const message = payload['message'];
        const text = payload['text'];
        const summary = typeof message === 'string' ? message : typeof text === 'string' ? text : undefined;
        this.finish(this.parseCues(summary));
      } else if (state === 'error' || state === 'aborted') {
        hilog.warn(MagicCueController.DOMAIN, MagicCueController.TAG, 'DSH magic-cue run ended with %{public}s', state);
        this.finish([]);
      }
    } catch (error) {
      hilog.warn(MagicCueController.DOMAIN, MagicCueController.TAG, 'invalid magic-cue event: %{public}s',
        error instanceof Error ? error.message : String(error));
    }
  }

  /** Refresh the idle timeout (agent delta proves DSH is still working). */
  private resetTimeout(): void {
    if (this.activeTimeout !== -1) clearTimeout(this.activeTimeout);
    this.activeTimeout = setTimeout(() => this.finish([]), RUN_TIMEOUT_MS);
  }

  private async startActive(screenPayload: string, bundleName: string, title: string): Promise<void> {
    try {
      const params = new MagicCueChatParams();
      params.message = this.buildPrompt(screenPayload, bundleName, title);
      params.idempotencyKey = `magic-cue-${Date.now()}`;
      const response = await this.session.request('chat.send', params);
      const payload = response.payload as Record<string, Object> ||
        (response.payloadJSON ? JSON.parse(response.payloadJSON) as Record<string, Object> : undefined);
      this.activeRunId = payload?.['runId'] as string | undefined;
      hilog.info(MagicCueController.DOMAIN, MagicCueController.TAG, 'sent magic-cue analysis, runId=%{public}s',
        this.activeRunId || '');
    } catch (error) {
      hilog.warn(MagicCueController.DOMAIN, MagicCueController.TAG, 'magic-cue send failed: %{public}s',
        error instanceof Error ? error.message : String(error));
      this.finish([]);
    }
  }

  private finish(cues: MagicCue[]): void {
    if (this.activeTimeout !== -1) {
      clearTimeout(this.activeTimeout);
      this.activeTimeout = -1;
    }
    const resolve = this.resolveActive;
    this.resolveActive = undefined;
    this.activeRunId = undefined;
    if (resolve) resolve(cues);
  }

  private cancelActive(): void {
    if (this.activeTimeout !== -1) {
      clearTimeout(this.activeTimeout);
      this.activeTimeout = -1;
    }
    this.resolveActive = undefined;
    this.activeRunId = undefined;
  }

  /** Brace-slice JSON with the same tolerance as companion-memory. */
  private parseCues(text: string | undefined): MagicCue[] {
    const value = (text || '').trim();
    if (!value) return [];
    const start = value.indexOf('{');
    const end = value.lastIndexOf('}');
    if (start < 0 || end <= start) return [];
    try {
      const parsed = JSON.parse(value.substring(start, end + 1)) as Record<string, Object>;
      const rawCues = parsed['cues'];
      if (!Array.isArray(rawCues)) return [];
      const cues: MagicCue[] = [];
      for (const item of rawCues as Object[]) {
        if (typeof item !== 'object' || item === null) continue;
        const c = item as Record<string, Object>;
        const kind = typeof c['kind'] === 'string' ? (c['kind'] as string) : '';
        const title = typeof c['title'] === 'string' ? (c['title'] as string).trim() : '';
        const content = typeof c['content'] === 'string' ? (c['content'] as string).trim() : '';
        if (!['contact', 'calendar', 'memo'].includes(kind) || !title || !content) continue;
        cues.push({ kind, title, content });
        if (cues.length >= MAX_CUES) break;
      }
      return cues;
    } catch (error) {
      hilog.warn(MagicCueController.DOMAIN, MagicCueController.TAG, 'magic-cue JSON parse failed: %{public}s',
        error instanceof Error ? error.message : String(error));
      return [];
    }
  }

  /**
   * Extract meaningful text from MSDP UI tree or context payload.
   * MSDP SmartEdge returns a deeply nested UI tree with hundreds of empty
   * syntax/layout items (IfElse, SyntaxItem, Column, bbox, actions) that can
   * exceed 100KB. We extract only visible content/description text in order.
   */
  private extractScreenText(rawPayload: string): string {
    const trimmed = rawPayload.trim();
    if (!trimmed) return '';

    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>;
      const lines: string[] = [];

      const addLine = (text: string | undefined): void => {
        if (!text) return;
        const val = text.trim();
        if (!val) return;
        if (['OTHERS', 'UiTree', 'Screenshot', 'LoadModule', 'Na', 'FontWeight.Normal'].includes(val)) return;
        if (lines.length === 0 || lines[lines.length - 1] !== val) {
          lines.push(val);
        }
      };

      const extractFromComponents = (components: Object[]): void => {
        for (const item of components) {
          if (typeof item !== 'object' || item === null) continue;
          const comp = item as Record<string, Object>;
          const content = typeof comp['content'] === 'string' ? (comp['content'] as string) : undefined;
          const description = typeof comp['description'] === 'string' ? (comp['description'] as string) : undefined;
          if (content && content.trim()) {
            addLine(content);
          } else if (description && description.trim()) {
            addLine(description);
          }
        }
      };

      // 1. Check MSDP OnscreenAwarenessInfo items -> uiTree
      const items = parsed['items'];
      if (Array.isArray(items)) {
        for (const it of items as Object[]) {
          if (typeof it !== 'object' || it === null) continue;
          const itObj = it as Record<string, Object>;
          const info = itObj['itemInfo'] as Record<string, Object> | undefined;
          const uiTreeStr = info?.['uiTree'];
          if (typeof uiTreeStr === 'string' && uiTreeStr.trim()) {
            try {
              const tree = JSON.parse(uiTreeStr) as Record<string, Object>;
              const comps = tree['components'];
              if (Array.isArray(comps)) {
                extractFromComponents(comps as Object[]);
              }
            } catch (_) {
              // Ignore single tree parse failure
            }
          }
        }
      }

      // 2. Direct components array
      if (lines.length === 0 && Array.isArray(parsed['components'])) {
        extractFromComponents(parsed['components'] as Object[]);
      }

      // 3. ScreenContextSnapshot (content & paragraphs)
      if (lines.length === 0 && typeof parsed['content'] === 'string') {
        addLine(parsed['content'] as string);
      }
      if (Array.isArray(parsed['paragraphs'])) {
        for (const p of parsed['paragraphs'] as Object[]) {
          if (typeof p === 'object' && p !== null) {
            const pObj = p as Record<string, Object>;
            if (typeof pObj['title'] === 'string') addLine(pObj['title'] as string);
            if (typeof pObj['text'] === 'string') addLine(pObj['text'] as string);
          }
        }
      }

      if (lines.length > 0) {
        return lines.join('\n');
      }
    } catch (_) {
      // Fallback below if not valid JSON
    }

    // Fallback: extract via regex for content / description in escaped or raw JSON
    const contentRegex = /\\*"(?:content|description)\\*":\\*"([^\\"\n]+)/g;
    const lines: string[] = [];
    let match: RegExpExecArray | null = null;
    while ((match = contentRegex.exec(trimmed)) !== null) {
      const val = match[1].trim();
      if (!val || ['OTHERS', 'UiTree', 'Screenshot', 'LoadModule', 'Na', 'FontWeight.Normal'].includes(val)) continue;
      if (lines.length === 0 || lines[lines.length - 1] !== val) {
        lines.push(val);
      }
    }
    if (lines.length > 0) {
      return lines.join('\n');
    }

    return trimmed;
  }

  private buildPrompt(screenPayload: string, bundleName: string, title: string): string {
    const cleanText = this.extractScreenText(screenPayload);
    // In chat screens, new messages are at the bottom. If the text exceeds the
    // length limit, retain the tail (most recent messages) instead of cutting
    // off the latest question from the peer.
    let payload = cleanText;
    if (payload.length > MAX_PAYLOAD_LENGTH) {
      payload = `[早期屏幕内容已省略]\n${payload.substring(payload.length - MAX_PAYLOAD_LENGTH)}`;
    }

    return '你是 Bonio 的 Magic Cue 助手。以下是手机当前屏幕的内容（应用：' + bundleName + '，标题：' + title + '）：\n'
      + '<屏幕文本>\n' + payload + '\n</屏幕文本>\n\n'
      + '判断屏幕上的对话是否有人在【询问】以下类别的信息：\n'
      + '- 联系人（某人的电话/公司/邮箱）\n'
      + '- 日程安排（某天/某个活动的时间和地点）\n'
      + '- 记忆（以前记下的内容，如某家餐厅、某个订单、某个地址）\n\n'
      + '规则：\n'
      + '1. 只处理“询问”，不是陈述。没人问 → 返回 {"cues":[]}。\n'
      + '2. 需要数据时调用工具取真实数据：contacts.search（联系人）、calendar.events（日历）、'
      + 'memo_list（记忆，用 query 关键词过滤）。工具查不到 → 不产出该 cue，禁止编造。\n'
      + '3. 针对联系人查询：若对方明确询问“手机号/电话号码”，如果通讯录中找到了该联系人但未登记手机号码（phones 为空），'
      + '不得单独将邮箱当作手机号输出；可在 content 中明确说明“未登记手机号码（可用邮箱：xxx）”或不产出 cue，严禁把邮箱当作电话号码提供。\n'
      + '4. 排除：验证码、密码、支付/银行卡信息 —— 一律忽略。\n'
      + '5. 最多 3 条。content 是准备直接发给对方的完整答案文本（如“张三：138xxxx8888”），'
      + '不是入口或“去日历查看”。\n'
      + '6. 只输出 JSON，不要输出 Markdown 或多余文字：'
      + '{"cues":[{"kind":"contact|calendar|memo","title":"…","content":"…"}]}';
  }
}