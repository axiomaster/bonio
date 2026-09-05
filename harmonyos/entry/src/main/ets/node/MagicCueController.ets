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
  timeoutMs: number = 30000;
  idempotencyKey: string = '';
}

const MAX_CUES = 3;
const RUN_TIMEOUT_MS = 30000;
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
    if (event !== 'chat' || !payloadJson || !this.resolveActive) return;
    try {
      const payload = JSON.parse(payloadJson) as Record<string, Object>;
      if (payload['sessionKey'] !== MAGIC_CUE_SESSION_KEY) return;
      const runId = payload['runId'] as string | undefined;
      if (this.activeRunId && runId !== this.activeRunId) return;
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

  private buildPrompt(screenPayload: string, bundleName: string, title: string): string {
    const payload = screenPayload.length <= MAX_PAYLOAD_LENGTH
      ? screenPayload
      : `${screenPayload.substring(0, MAX_PAYLOAD_LENGTH)}\n[屏幕文本过长，后续内容已截断]`;
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
      + '3. 排除：验证码、密码、支付/银行卡信息 —— 一律忽略。\n'
      + '4. 最多 3 条。content 是准备直接发给对方的完整答案文本（如“张三：138xxxx8888”），'
      + '不是入口或“去日历查看”。\n'
      + '5. 只输出 JSON，不要输出 Markdown 或多余文字：'
      + '{"cues":[{"kind":"contact|calendar|memo","title":"…","content":"…"}]}';
  }
}
