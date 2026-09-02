import { hilog } from '@kit.PerformanceAnalysisKit';
import { GatewaySession } from '../gateway/GatewaySession';
import { MemoryService, SaveBonioMemory } from './MemoryService';

export const COMPANION_MEMORY_SESSION_KEY = 'system:companion-memory';

const IGNORED_BUNDLE_NAMES: string[] = [
  'com.example.msdpdemo',
  'com.huawei.hmos.vassistant.launcher',
  'com.ohos.sceneboard',
];
const IGNORED_APP_NAMES: string[] = ['bonio', '大桌面'];
const MAX_DSH_PAYLOAD_LENGTH = 60000;
const ORDER_MEMORY_KEYWORDS: string[] = [
  '订单', '下单', '购买', '支付', '付款', '结算', '外卖', '取餐', '咖啡', 'coffee', 'luckin', '瑞幸',
];
const CONTENT_TAG_PREFIX = '内容:';
const ACTION_TAG_PREFIX = '行为:';
const FAVORITE_PAGE_TAG = 'addtofavorite';

class CompanionChatParams {
  sessionKey: string = COMPANION_MEMORY_SESSION_KEY;
  message: string = '';
  thinking: string = 'low';
  timeoutMs: number = 30000;
  idempotencyKey: string = '';
  attachments: CompanionAttachmentPayload[] | undefined = undefined;
}

class CompanionAttachmentPayload {
  type: string = 'image';
  mimeType: string = 'image/jpeg';
  fileName: string = 'msdp-screen.jpg';
  content: string = '';
}

class CompanionMemoryInput {
  sequence: number = 0;
  source: string = '';
  payloadJson: string = '';
  coverImageBase64: string | undefined = undefined;
  receivedAt: number = 0;
  explicitCapture: boolean = false;
  favoriteAction: boolean = false;
  completionListeners: Array<(outcome: CompanionMemoryOutcome) => void> = [];
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

export class CompanionMemoryOutcome {
  saved: boolean = false;
  title: string = '';
  reason: string = '';
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

  enqueue(source: string, payloadJson: string, coverImageBase64?: string): void {
    this.enqueueInternal(source, payloadJson, coverImageBase64);
  }

  /** Wait for a user-initiated capture to finish DSH analysis and memo persistence. */
  enqueueAndWait(source: string, payloadJson: string, coverImageBase64?: string): Promise<CompanionMemoryOutcome> {
    return new Promise((resolve: (outcome: CompanionMemoryOutcome) => void) => {
      this.enqueueInternal(source, payloadJson, coverImageBase64, resolve);
    });
  }

  private enqueueInternal(source: string, payloadJson: string, coverImageBase64?: string,
    completionListener?: (outcome: CompanionMemoryOutcome) => void): void {
    if (!payloadJson.trim()) {
      if (completionListener) completionListener(this.outcome(false, '', '屏幕识别未返回内容'));
      return;
    }
    const filteredPayload = this.filterIgnoredApplications(source, payloadJson);
    if (!filteredPayload) {
      if (completionListener) completionListener(this.outcome(false, '', '当前页面不支持记忆'));
      return;
    }
    const pending = this.findPendingInput(source, filteredPayload);
    if (pending) {
      if (completionListener) pending.completionListeners.push(completionListener);
      return;
    }
    const input = new CompanionMemoryInput();
    input.sequence = this.nextInputSequence++;
    input.source = source;
    input.payloadJson = filteredPayload;
    input.coverImageBase64 = coverImageBase64;
    input.receivedAt = Date.now();
    input.explicitCapture = source === 'trigger';
    input.favoriteAction = this.isFavoriteAction(filteredPayload);
    if (completionListener) input.completionListeners.push(completionListener);
    if (this.queue.length >= CompanionMemoryController.MAX_QUEUE_SIZE) {
      this.queue.shift();
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'companion queue full; dropped oldest awareness result');
    }
    this.queue.push(input);
    hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
      'queued %{public}s input seq=%{public}d explicit=%{public}s favorite=%{public}s queue=%{public}d connected=%{public}s',
      source, input.sequence, input.explicitCapture ? 'true' : 'false', input.favoriteAction ? 'true' : 'false', this.queue.length,
      this.isConnected() ? 'true' : 'false');
    this.processNext();
  }

  private findPendingInput(source: string, payloadJson: string): CompanionMemoryInput | undefined {
    if (this.activeInput?.source === source && this.activeInput.payloadJson === payloadJson) return this.activeInput;
    return this.queue.find((candidate: CompanionMemoryInput): boolean =>
      candidate.source === source && candidate.payloadJson === payloadJson);
  }

  private filterIgnoredApplications(source: string, payloadJson: string): string | undefined {
    try {
      const parsed = JSON.parse(payloadJson) as Object;
      if (Array.isArray(parsed)) {
        const rows = parsed as Object[];
        const filtered = rows.filter((row: Object): boolean => !this.isIgnoredApplication(row));
        if (filtered.length === rows.length) return payloadJson;
        hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'ignored %{public}d/%{public}d %{public}s result(s) from Bonio or launcher',
          rows.length - filtered.length, rows.length, source);
        return filtered.length > 0 ? JSON.stringify(filtered) : undefined;
      }
      if (!this.isIgnoredApplication(parsed)) return payloadJson;
      hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'ignored %{public}s result from Bonio or launcher', source);
      return undefined;
    } catch (_) {
      return payloadJson;
    }
  }

  private isIgnoredApplication(value: Object): boolean {
    if (value === null || typeof value !== 'object') return false;
    const row = value as Record<string, Object>;
    const bundleValue = row['bundleName'];
    const appValue = row['appName'];
    const bundleName = typeof bundleValue === 'string' ? bundleValue.trim().toLowerCase() : '';
    const appName = typeof appValue === 'string' ? appValue.trim().toLowerCase() : '';
    return IGNORED_BUNDLE_NAMES.includes(bundleName) || IGNORED_APP_NAMES.includes(appName);
  }

  private isFavoriteAction(payloadJson: string): boolean {
    return payloadJson.toLowerCase().includes(FAVORITE_PAGE_TAG);
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
        const message = payload['message'];
        const text = payload['text'];
        const summary = typeof message === 'string' ? message : typeof text === 'string' ? text : undefined;
        void this.completeActive(summary);
      } else if ((state === 'error' || state === 'aborted') && !this.completingActive) {
        const errorMessage = typeof payload['errorMessage'] === 'string' ? payload['errorMessage'] : '';
        hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'DSH companion run ended with %{public}s: %{public}s', state || 'unknown', errorMessage);
        this.finishActive(this.outcome(false, '', state === 'error' ? errorMessage || 'DSH 分析失败' : 'DSH 分析已取消'));
      }
    } catch (error) {
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'invalid companion event: %{public}s', error instanceof Error ? error.message : String(error));
    }
  }

  private processNext(): void {
    if (!this.isConnected() || this.activeInput || this.requestInFlight || this.queue.length === 0) {
      if (this.queue.length > 0) {
        hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'companion queue waiting connected=%{public}s active=%{public}s request=%{public}s queue=%{public}d',
          this.isConnected() ? 'true' : 'false', this.activeInput ? 'true' : 'false',
          this.requestInFlight ? 'true' : 'false', this.queue.length);
      }
      return;
    }
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
      if (input.coverImageBase64) {
        const attachment = new CompanionAttachmentPayload();
        attachment.content = input.coverImageBase64;
        params.attachments = [attachment];
      }
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
        this.finishActive(this.outcome(false, '', error instanceof Error ? error.message : String(error)));
    }
  }

  private async completeActive(summaryText: string | undefined): Promise<void> {
    const input = this.activeInput;
    if (!input) return;
    let outcome = this.outcome(false, '', 'DSH 未返回可保存的摘要');
    try {
      let summary = this.parseSummary(summaryText);
      if (!summary) {
        hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'DSH companion summary was not valid JSON, source=%{public}s response=%{public}s',
          input.source, (summaryText || '').substring(0, 300));
      }
      if (this.shouldCreateRequiredFallback(input, summary)) {
        summary = this.requiredFallbackSummary(input);
        hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'using required memory fallback for %{public}s', input.source);
      }
      if (summary && summary.shouldRemember !== false && summary.content?.trim()) {
        const memory = new SaveBonioMemory();
        memory.title = summary.title?.trim() || '屏幕记忆';
        memory.content = summary.content.trim();
        memory.source = `msdp_${input.source}`;
        memory.tags = this.memoryTags(summary.tags, input);
        memory.sourceApp = summary.sourceApp?.trim() || '';
        memory.pageTitle = summary.pageTitle?.trim() || '';
        memory.pageLink = summary.pageLink?.trim() || '';
        memory.coverImage = input.coverImageBase64 || '';
        await this.memoryService.save(memory);
        hilog.info(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
          'saved companion summary: %{public}s', memory.title);
        outcome = this.outcome(true, memory.title, '');
      } else if (summary?.shouldRemember === false) {
        outcome = this.outcome(false, '', '当前页面未发现需要长期记忆的内容');
      }
    } catch (error) {
      hilog.warn(CompanionMemoryController.DOMAIN, CompanionMemoryController.TAG,
        'failed to persist companion summary: %{public}s', error instanceof Error ? error.message : String(error));
      outcome = this.outcome(false, '', error instanceof Error ? error.message : String(error));
    } finally {
      this.finishActive(outcome);
    }
  }

  private finishActive(outcome?: CompanionMemoryOutcome): void {
    const completed = this.activeInput;
    if (completed) {
      const finalOutcome = outcome || this.outcome(false, '', '伴随记忆未完成');
      completed.completionListeners.forEach((listener: (value: CompanionMemoryOutcome) => void) => listener(finalOutcome));
    }
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

  private outcome(saved: boolean, title: string, reason: string): CompanionMemoryOutcome {
    const outcome = new CompanionMemoryOutcome();
    outcome.saved = saved;
    outcome.title = title;
    outcome.reason = reason;
    return outcome;
  }

  private shouldCreateRequiredFallback(input: CompanionMemoryInput, summary: CompanionSummary | undefined): boolean {
    if (!input.explicitCapture && !input.favoriteAction) return false;
    return !summary || summary.shouldRemember === false || !summary.content?.trim();
  }

  private memoryTags(summaryTags: string[] | undefined, input: CompanionMemoryInput): string[] {
    const contentTags: string[] = [];
    (summaryTags || []).forEach((tag: string) => {
      const normalized = tag.trim().replace(/^内容[:：]/, '').replace(/^行为[:：]/, '');
      if (normalized && !['浏览记', '主动记', '收藏记'].includes(normalized) && !contentTags.includes(normalized)) {
        contentTags.push(normalized);
      }
    });
    if (contentTags.length === 0) contentTags.push('待分类');
    const behavior = input.favoriteAction ? '收藏记' : input.explicitCapture ? '主动记' : '浏览记';
    return contentTags.slice(0, 3).map((tag: string): string => `${CONTENT_TAG_PREFIX}${tag}`)
      .concat(`${ACTION_TAG_PREFIX}${behavior}`);
  }

  private containsOrderSignal(payloadJson: string): boolean {
    const lowerPayload = payloadJson.toLowerCase();
    return ORDER_MEMORY_KEYWORDS.some((keyword: string): boolean => lowerPayload.includes(keyword));
  }

  private requiredFallbackSummary(input: CompanionMemoryInput): CompanionSummary {
    const lowerPayload = input.payloadJson.toLowerCase();
    const isOrder = this.containsOrderSignal(input.payloadJson);
    const isLuckin = lowerPayload.includes('luckin') || input.payloadJson.includes('瑞幸');
    const subject = isLuckin ? '瑞幸咖啡订单' : isOrder ? '订单页面' : '当前页面';
    const rememberedBy = input.favoriteAction ? 'MSDP 检测到用户收藏了当前内容。' : '用户通过双击 avatar 明确要求记录当前页面。';
    return {
      shouldRemember: true,
      title: `${input.favoriteAction ? '收藏' : ''}${subject}记录`,
      content: isOrder
        ? `${rememberedBy}下次用户说“再来一单”时，应先读取此记忆，再结合关联截图和页面信息调用 phone-use skill 复现下单流程。`
        : `${rememberedBy}后续可结合本条记忆的截图和页面信息继续处理。`,
      tags: isLuckin ? ['瑞幸咖啡', '订单', '复购'] : isOrder ? ['订单', '复购'] : ['显式记录'],
      sourceApp: isLuckin ? '瑞幸咖啡' : '',
      pageTitle: subject,
      pageLink: '',
    };
  }

  private buildPrompt(input: CompanionMemoryInput): string {
    const payload = this.payloadForDsh(input.payloadJson);
    const captureInstruction = input.explicitCapture
      ? '用户指令：用户刚刚双击 avatar，明确要求把当前页面分析并保存为长期记忆。此请求不得按普通后台浏览数据忽略，必须返回 shouldRemember:true。微信小程序可能没有可用的 view tree；若附有截图，截图和其中可见的文字是订单事实的最高优先级来源。\n'
        + '订单提取规则：商品名称、规格、温度/冰量、糖度、数量和金额必须逐字忠实转录截图或 MSDP 原文中可见的文字。不得依据杯子颜色、商品图片、常见搭配或经验推断饮品种类；不得把“冷萃”概括、改写或纠正为“冰拿铁”等其他饮品。名称不可辨认时写“商品名称未识别”，并省略该字段，绝不猜测。\n'
        + '在 content 中按“商品名称：…；规格：…；温度/冰量：…；糖度：…；数量：…；金额：…”依次记录可确认字段。例如画面文字为“埃塞瑰夏冷萃 / 大杯 / 冰 / 不另外加糖”，则必须保留这四个原文值。再补充品牌、取餐方式、门店、订单状态等明确可见的信息。\n'
      : '';
    const favoriteInstruction = input.favoriteAction
      ? 'MSDP 的 pageTags 包含 addtofavorite，表示用户刚刚收藏了当前内容。这是明确的收藏行为，必须返回 shouldRemember:true；即使页面详情不足，也要保存可用的标题、来源和收藏上下文。\n'
      : '';
    return '你正在处理 Bonio 的后台伴随记忆，不是用户主对话。分析下面的 MSDP 屏幕感知结果，提取用户正在浏览的、未来可能有帮助的信息。'
      + '支付信息、账单、证件号等个人事务信息是高价值记忆，应记录关键内容。用户浏览过的文章、商品、美食、店铺、短视频，以及下单或购买过的商品也都是高价值记忆，应记录名称、关键信息和上下文。'
      + '忽略密码、验证码、完整私信以及短暂无意义的界面状态。验证码是临时信息，不应记录。若附有截图，请结合截图和结构化结果判断内容。不要调用任何工具，不要输出 Markdown。'
      + '只返回一个 JSON 对象：有价值时返回 {"shouldRemember":true,"title":"简短标题","content":"1到3句中文摘要",'
      + '"tags":["1到3个内容类别"],"sourceApp":"应用名","pageTitle":"页面标题","pageLink":"来源链接"}。tags 只能是内容类别，不要输出行为类别或“内容:”/“行为:”前缀；可使用新闻、时政、财经、科技、购物、美食、生活、健康、出行、教育、娱乐、情感等贴合页面的类别；'
      + '无价值时返回 {"shouldRemember":false}。输出必须能被标准 JSON.parse 解析；字符串正文中的英文双引号请改用中文引号或进行 JSON 转义。缺失字段使用空字符串或空数组。\n'
      + `来源：${input.source}\n时间戳：${input.receivedAt}\n${captureInstruction}${favoriteInstruction}MSDP 原始结果：\n${payload}`;
  }

  private payloadForDsh(payloadJson: string): string {
    if (payloadJson.length <= MAX_DSH_PAYLOAD_LENGTH) return payloadJson;
    return `${payloadJson.substring(0, MAX_DSH_PAYLOAD_LENGTH)}\n[MSDP 原始结果过长，后续内容已截断]`;
  }
}
