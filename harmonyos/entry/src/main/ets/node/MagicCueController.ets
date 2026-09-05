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

const MAX_CUES = 2;
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
  private extractScreenText(rawPayload: string, title?: string): string {
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
        if (/^\d{1,2}:\d{2}$/.test(val) || /^\d{1,2},\s*:\s*,\s*\d{1,2}$/.test(val) || /^\d{1,3}%?$/.test(val)) return;
        if (val.includes('休息中') || val.includes('有事叫我') || val.includes('帮我回') || val.includes('发送中')) return;
        if (title && val === title) return;
        if (lines.length === 0 || lines[lines.length - 1] !== val) {
          lines.push(val);
        }
      };

      const getCompTop = (comp: Record<string, Object>): number => {
        if (typeof comp['top'] === 'number') return comp['top'] as number;
        if (typeof comp['y'] === 'number') return comp['y'] as number;
        if (typeof comp['bbox'] === 'object' && comp['bbox'] !== null) {
          const b = comp['bbox'];
          if (Array.isArray(b) && b.length >= 2 && typeof b[1] === 'number') return b[1] as number;
          const bObj = b as Record<string, Object>;
          if (typeof bObj['top'] === 'number') return bObj['top'] as number;
          if (typeof bObj['y'] === 'number') return bObj['y'] as number;
        }
        const rect = comp['rect'] as Record<string, Object> | undefined;
        if (rect) {
          if (typeof rect['top'] === 'number') return rect['top'] as number;
          if (typeof rect['y'] === 'number') return rect['y'] as number;
        }
        const bounds = typeof comp['bounds'] === 'string' ? comp['bounds'] as string : undefined;
        if (bounds) {
          const m = bounds.match(/\[\d+,\s*(\d+)\]/);
          if (m) return parseInt(m[1], 10);
        }
        return -1;
      };

      const extractFromComponents = (components: Object[]): void => {
        const sortedComps = [...components];
        const hasTop = sortedComps.some((item: Object) => {
          if (typeof item !== 'object' || item === null) return false;
          return getCompTop(item as Record<string, Object>) >= 0;
        });
        if (hasTop) {
          sortedComps.sort((a: Object, b: Object) => {
            const topA = (typeof a === 'object' && a !== null) ? getCompTop(a as Record<string, Object>) : -1;
            const topB = (typeof b === 'object' && b !== null) ? getCompTop(b as Record<string, Object>) : -1;
            if (topA >= 0 && topB >= 0) return topA - topB;
            return 0;
          });
        }

        for (const item of sortedComps) {
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
                if (lines.length > 0) {
                  break;
                }
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
      if (lines.length === 0 && Array.isArray(parsed['paragraphs'])) {
        for (const p of parsed['paragraphs'] as Object[]) {
          if (typeof p === 'object' && p !== null) {
            const pObj = p as Record<string, Object>;
            if (typeof pObj['title'] === 'string') addLine(pObj['title'] as string);
            if (typeof pObj['text'] === 'string') addLine(pObj['text'] as string);
          }
        }
      }

      if (lines.length > 0) {
        // If the last line is an isolated short label/name (e.g. Action Bar title / contact name at the end of UiTree),
        // remove it from the bottom of chat messages so it cannot be mistaken for a question.
        if (lines.length > 1) {
          const last = lines[lines.length - 1];
          const isQuestionLike = /(吗|谁|哪|多|号|发|请|\?|？|联系|手机|电话|邮箱|微信|日程|时间|在哪)/.test(last);
          if (last.length <= 4 && !isQuestionLike) {
            lines.pop();
          }
        }
        hilog.info(MagicCueController.DOMAIN, MagicCueController.TAG, 'extracted screen text (%{public}d lines):\n%{public}s',
          lines.length, lines.join('\n'));
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
      if (title && val === title) continue;
      if (lines.length === 0 || lines[lines.length - 1] !== val) {
        lines.push(val);
      }
    }
    if (lines.length > 0) {
      if (lines.length > 1) {
        const last = lines[lines.length - 1];
        const isQuestionLike = /(吗|谁|哪|多|号|发|请|\?|？|联系|手机|电话|邮箱|微信|日程|时间|在哪)/.test(last);
        if (last.length <= 4 && !isQuestionLike) {
          lines.pop();
        }
      }
      hilog.info(MagicCueController.DOMAIN, MagicCueController.TAG, 'extracted screen text regex (%{public}d lines):\n%{public}s',
        lines.length, lines.join('\n'));
      return lines.join('\n');
    }

    return trimmed;
  }

  private buildPrompt(screenPayload: string, bundleName: string, title: string): string {
    const cleanText = this.extractScreenText(screenPayload, title);
    let payload = cleanText;
    if (payload.length > MAX_PAYLOAD_LENGTH) {
      payload = `[早期屏幕内容已省略]\n${payload.substring(payload.length - MAX_PAYLOAD_LENGTH)}`;
    }

    const titleHint = title ? `会话对象/标题：【${title}】` : '';

    return '你是 Bonio 的 Magic Cue 助手。以下是手机当前屏幕的内容（应用：' + bundleName + (titleHint ? '，' + titleHint : '') + '）：\n'
      + '<屏幕文本>\n' + payload + '\n</屏幕文本>\n\n'
      + '请严格按以下规则分析屏幕对话，决定是否为用户生成快捷回复胶囊：\n\n'
      + '【核心时序规则：只答复最后一次的问题】\n'
      + '1. 屏幕文本是按时间从上到下的聊天记录（上方是早前历史消息，下方是最新消息）。\n'
      + '2. 在整段对话中，找出按时序出现的【最后一次（最底部、最新的一条）】明确向用户询问特定信息的提问（例如索要某人的手机号/电话/邮箱/日程/记忆等）。\n'
      + '3. 绝对忽略所有历史旧问题！无论历史提问内容是什么，严禁处理或列出历史上更早的问题，绝不在胶囊中混杂历史旧问题的答案！\n'
      + (title ? '4. 忽略页面顶部的标题栏与会话对象名称【' + title + '】，那只是当前聊天对象姓名或群名，绝对不是提问，严禁对【' + title + '】调用工具或生成胶囊。\n\n' : '4. 忽略页面顶部的标题栏与会话对象名称，严禁对标题名字调用工具或产出胶囊。\n\n')
      + '【关键规则：已回复检查（如果用户已经回复过了，那就不需要回复了）】\n'
      + '5. 定位到这【最后一次提问】后，必须检查该提问在对话中是否【已经得到回复】：\n'
      + '   a. 如果在该提问下方（或紧随其后）已经出现了相应的答复（包括用户手动发出的消息、或者对话中给出的号码/内容），说明该问题【已经回复过了】。\n'
      + '   b. 如果屏幕最底部的消息本身就是回答、陈述或闲聊，且没有处于等待回复状态的最新提问，说明所有问题均已回复完毕。\n'
      + '   c. 只要最后一次提问已经回复过了，就【完全不需要再回复】，必须直接返回 {"cues":[]}，绝不能弹出任何旧胶囊！\n'
      + '   d. 只有当且仅当这【最后一次提问】处于【未回复/等待回答】状态（即其下方尚未出现任何针对该提问的答复）时，才针对该提问生成胶囊。\n\n'
      + '【单意图与数据真实性】\n'
      + '6. 如果存在最新未回复的提问，只针对这【一个】最新提问调用工具获取真实数据：\n'
      + '   contacts.search（联系人）、calendar.events（日历）、memo_list（记忆）。\n'
      + '   生成 1 条（若有主号/副号等明确备选最多 2 条）针对该提问的答案，严禁跨越多个不同问题混杂输出。\n'
      + '7. 针对联系人查询：若对方明确要电话/手机号，通讯录中找到了该联系人但未登记手机号码（phones 为空），严禁拿邮箱当作手机号提供；可在 content 中说明“未登记手机号码”或返回 {"cues":[]}。\n'
      + '8. 排除：验证码、密码、支付转账/银行卡信息 —— 一律忽略。\n\n'
      + '【输出格式】\n'
      + '只输出纯 JSON，不要 Markdown 代码块或多余解释文字：\n'
      + '{"cues":[{"kind":"contact|calendar|memo","title":"…","content":"…"}]}\n'
      + '若无需回复或未找到，返回 {"cues":[]}。';
  }
}