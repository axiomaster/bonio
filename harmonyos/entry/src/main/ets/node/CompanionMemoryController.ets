import { hilog } from '@kit.PerformanceAnalysisKit';
import { GatewaySession } from '../gateway/GatewaySession';
import { MemoryService, SaveBonioMemory } from './MemoryService';

export const COMPANION_MEMORY_SESSION_KEY = 'system:companion-memory';

class CompanionChatParams {
  sessionKey: string = COMPANION_MEMORY_SESSION_KEY;
  message: string = '';
  thinking: string = 'low';
  timeoutMs: number = 30000;
  idempotencyKey: string = '';
}

class CompanionMemoryInput {
  sequence: number = 0;
  source: string = '';
  payloadJson: string = '';
  receivedAt: number = 0;
}

interface CompanionSummary {
  shouldRemember?: boolean;
  title?: string;
  content?: string;
  tags?: string[];
  sourceApp?: string;
  pageTitle?: string;
  pageLink?: string;
}

/** Serializes background MSDP results through a conversation hidden from the main chat. */
export class CompanionMemoryController {
  private static readonly DOMAIN = 0x3D00;
  private static readonly TAG = 'CompanionMemory';
  private static readonly MAX_QUEUE_SIZE = 200;

  private readonly session: GatewaySession;
  private readonly memoryService: MemoryService;
  private readonly isConnected: () => boolean;
  private queue: CompanionMemoryInput[] = [];
  private activeInput: CompanionMemoryInput | undefined = undefined;
  private activeRunId: string | undefined = undefined;
  private requestInFlight: boolean = false;
  private completingActive: boolean = false;
  private nextInputSequence: number = 1;
  private connectionGeneration: number = 0;

  constructor(session: GatewaySession, memoryService: MemoryService, isConnected: () => boolean) {
    this.session = session;
    this.memoryService = memoryService;
    this.isConnected = isConnected;
  }

  enqueue(source: string, payloadJson: string): void {
    if (!payloadJson.trim()) return;
    const previous = this.queue.length > 0 ? this.queue[this.queue.length - 1] : this.activeInput;
    if (previous?.source === source && previous.payloadJson === payloadJson) return;
    const input = new CompanionMemoryInput();
    input.sequence = this.nextInputSequence++;
    input.source = source;
    input.payloadJson = payloadJson;
    input.receivedAt = Date.now();
    if (this.queue.length >= CompanionMemoryController.MAX_QUEUE_SIZE) {
      this.queue.shift();
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'companion queue full; dropped oldest awareness result');
    }
    this.queue.push(input);
    this.processNext();
  }

  onConnected(): void {
    this.processNext();
  }

  onDisconnected(): void {
    this.connectionGeneration++;
    if (this.activeInput) this.queue.unshift(this.activeInput);
    this.activeInput = undefined;
    this.activeRunId = undefined;
    this.requestInFlight = false;
    this.completingActive = false;
  }

  handleGatewayEvent(event: string, payloadJson: string | undefined): void {
    if (event !== 'chat' || !payloadJson || !this.activeInput) return;
    try {
      const payload = JSON.parse(payloadJson) as Record<string, Object>;
      if (payload['sessionKey'] !== COMPANION_MEMORY_SESSION_KEY) return;
      const runId = payload['runId'] as string | undefined;
      if (this.activeRunId && runId !== this.activeRunId) return;
      const state = payload['state'] as string | undefined;
      if (state === 'started' && !this.activeRunId && runId) {
        this.activeRunId = runId;
      } else if (state === 'final' && !this.completingActive) {
        this.completingActive = true;
        const summary = payload['message'] as string | undefined;
        void this.completeActive(summary);
      } else if ((state === 'error' || state === 'aborted') && !this.completingActive) {
        hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'DSH companion run ended with %{public}s', state || 'unknown');
        this.finishActive();
      }
    } catch (error) {
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'invalid companion event: %{public}s', error instanceof Error ? error.message : String(error));
    }
  }

  private processNext(): void {
    if (!this.isConnected() || this.activeInput || this.requestInFlight || this.queue.length === 0) return;
    const next = this.queue.shift();
    if (!next) return;
    this.activeInput = next;
    this.requestInFlight = true;
    void this.startActive(next);
  }

  private async startActive(input: CompanionMemoryInput): Promise<void> {
    const generation = this.connectionGeneration;
    try {
      const params = new CompanionChatParams();
      params.message = this.buildPrompt(input);
      params.idempotencyKey = `companion-memory-${input.receivedAt}-${input.sequence}`;
      const response = await this.session.request('chat.send', params);
      if (generation !== this.connectionGeneration || this.activeInput !== input) return;
      const payload = response.payload as Record<string, Object> ||
        (response.payloadJSON ? JSON.parse(response.payloadJSON) as Record<string, Object> : undefined);
      this.activeRunId = payload?.['runId'] as string | undefined;
      this.requestInFlight = false;
      hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'sent %{public}s result to companion session, runId=%{public}s', input.source, this.activeRunId || '');
    } catch (error) {
      if (generation !== this.connectionGeneration || this.activeInput !== input) return;
      this.requestInFlight = false;
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'failed to send companion memory: %{public}s', error instanceof Error ? error.message : String(error));
      this.finishActive();
    }
  }

  private async completeActive(summaryText: string | undefined): Promise<void> {
    const input = this.activeInput;
    if (!input) return;
    try {
      const summary = this.parseSummary(summaryText);
      if (summary?.shouldRemember !== false && summary?.content?.trim()) {
        const memory = new SaveBonioMemory();
        memory.title = summary.title?.trim() || '屏幕记忆';
        memory.content = summary.content.trim();
        memory.source = `msdp_${input.source}`;
        memory.tags = Array.isArray(summary.tags) ? summary.tags.filter((tag: string): boolean => tag.trim().length > 0) : [];
        memory.sourceApp = summary.sourceApp?.trim() || '';
        memory.pageTitle = summary.pageTitle?.trim() || '';
        memory.pageLink = summary.pageLink?.trim() || '';
        await this.memoryService.save(memory);
        hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'saved companion summary: %{public}s', memory.title);
      }
    } catch (error) {
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'failed to persist companion summary: %{public}s', error instanceof Error ? error.message : String(error));
    } finally {
      this.finishActive();
    }
  }

  private finishActive(): void {
    this.activeInput = undefined;
    this.activeRunId = undefined;
    this.requestInFlight = false;
    this.completingActive = false;
    this.processNext();
  }

  private parseSummary(text: string | undefined): CompanionSummary | undefined {
    const value = (text || '').trim();
    if (!value) return undefined;
    const start = value.indexOf('{');
    const end = value.lastIndexOf('}');
    if (start < 0 || end <= start) return undefined;
    return JSON.parse(value.substring(start, end + 1)) as CompanionSummary;
  }

  private buildPrompt(input: CompanionMemoryInput): string {
    return '你正在处理 Bonio 的后台伴随记忆，不是用户主对话。分析下面的 MSDP 屏幕感知结果，提取用户正在浏览的、未来可能有帮助的信息。'
      + '忽略密码、验证码、支付信息、证件号、完整私信以及短暂无意义的界面状态。不要调用任何工具，不要输出 Markdown。'
      + '只返回一个 JSON 对象：有价值时返回 {"shouldRemember":true,"title":"简短标题","content":"1到3句中文摘要",'
      + '"tags":["1到3个标签"],"sourceApp":"应用名","pageTitle":"页面标题","pageLink":"来源链接"}；'
      + '无价值时返回 {"shouldRemember":false}。缺失字段使用空字符串或空数组。\n'
      + `来源：${input.source}\n时间戳：${input.receivedAt}\nMSDP 原始结果：\n${input.payloadJson}`;
  }
}
