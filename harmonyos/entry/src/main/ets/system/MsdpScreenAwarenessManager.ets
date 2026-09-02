import onScreen from '@ohos.multimodalAwareness.onScreen';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const MAX_CONTEXT_TEXT_LENGTH = 12000;
const MEMORY_COVER_MAX_EDGE = 480;
const MEMORY_COVER_JPEG_QUALITY = 60;
const MEMORY_ORIGINAL_IMAGE_FORMAT = 'image/png';
// SmartEdge is an MSDP capability group, not an individual capability name.
const SMART_EDGE_CAPABILITY: onScreen.OnscreenAwarenessCap = { groupId: 'SmartEdge' };
// capture() accepts concrete capabilities; Screenshot is exposed by the device MSDP service.
const SCREENSHOT_CAPTURE_CAPABILITY: onScreen.OnscreenAwarenessCap = { capList: ['Screenshot'] };

export type SmartEdgeResultSource = 'subscribe' | 'trigger' | 'capture';

export interface ScreenParagraph {
  hookId?: number;
  chapterId?: number;
  title?: string;
  text?: string;
}

/** Data exposed to DSH only after an explicit screen-context request. */
export interface ScreenContextSnapshot {
  windowId: number;
  sessionId: number;
  bundleName: string;
  scenario?: number;
  title?: string;
  content?: string;
  pageLink?: string;
  paragraphs?: ScreenParagraph[];
  truncated: boolean;
}

/** Structured SmartEdge output for an explicit avatar memory capture. */
export interface SmartEdgeSnapshot {
  resultCode: number;
  timestamp: number;
  bundleName?: string;
  appName?: string;
  pageId?: string;
  collectStrategy?: number;
  pageTags?: string[];
  payloadJson: string;
  coverImageBase64?: string;
  originalImageBase64?: string;
  originalImageMimeType?: string;
  truncated: boolean;
}

interface SmartEdgeReport {
  payloadJson: string;
  coverImageBase64?: string;
  originalImageBase64?: string;
  originalImageMimeType?: string;
}

interface MemoryImages {
  coverImageBase64?: string;
  originalImageBase64?: string;
  originalImageMimeType?: string;
}

export class MsdpScreenAwarenessError extends Error {
  public readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

/**
 * Boundary around the system-only MSDP on-screen API. It does not collect in
 * the background: data is read only after the user enabled it in Settings.
 */
export class MsdpScreenAwarenessManager {
  private static readonly DOMAIN = 0x3D00;
  private static readonly TAG = 'MsdpScreenAwareness';
  private readonly smartEdgeListener = (results: onScreen.OnscreenAwarenessInfo[]): void => {
    this.lastSmartEdgeChangeAtMs = results.length > 0 ? Date.now() : this.lastSmartEdgeChangeAtMs;
    void this.reportSmartEdgeResult('subscribe', results);
  };
  private smartEdgeSubscribed: boolean = false;
  private lastSnapshot: ScreenContextSnapshot | undefined = undefined;
  private lastSmartEdgeChangeAtMs: number | undefined = undefined;
  private readonly isEnabled: () => boolean;
  private readonly onSmartEdgeResult: ((source: SmartEdgeResultSource, payloadJson: string,
    coverImageBase64?: string, originalImageBase64?: string, originalImageMimeType?: string) => void) | undefined;

  constructor(
    isEnabled: () => boolean,
    onSmartEdgeResult?: (source: SmartEdgeResultSource, payloadJson: string, coverImageBase64?: string,
      originalImageBase64?: string, originalImageMimeType?: string) => void,
  ) {
    this.isEnabled = isEnabled;
    this.onSmartEdgeResult = onSmartEdgeResult;
  }

  public start(): void {
    if (this.isEnabled()) this.subscribeSmartEdge();
  }

  public setEnabled(enabled: boolean): void {
    if (enabled) {
      this.subscribeSmartEdge();
      return;
    }
    if (!this.smartEdgeSubscribed) return;
    try {
      onScreen.unsubscribe(SMART_EDGE_CAPABILITY, this.smartEdgeListener);
    } catch (_) {
      // The local preference is still disabled even if the service already removed it.
    }
    this.smartEdgeSubscribed = false;
  }

  public async captureContext(paramsJson: string | undefined): Promise<ScreenContextSnapshot> {
    this.assertEnabled();
    const maxTextLength = this.parseMaxTextLength(paramsJson);
    try {
      const page = await onScreen.getPageContent({
        contentUnderstand: true,
        pageLink: true,
        textOnly: true,
      });
      const snapshot = this.toSnapshot(page, maxTextLength);
      this.lastSnapshot = snapshot;
      return snapshot;
    } catch (error) {
      throw this.toAwarenessError(error);
    }
  }

  /**
   * SmartEdge subscribes to foreground-app/page changes. Results are forwarded
   * to the independent companion-memory session by NodeRuntime.
   */
  public async triggerSmartEdge(): Promise<SmartEdgeSnapshot> {
    this.assertEnabled();
    this.subscribeSmartEdge();
    try {
      const result = await onScreen.trigger(SMART_EDGE_CAPABILITY);
      const report = await this.reportSmartEdgeResult('trigger', result);
      if (result.resultCode !== 0) {
        throw new MsdpScreenAwarenessError(
          'SMART_EDGE_RESULT_FAILED',
          `MSDP SmartEdge returned resultCode ${result.resultCode}`,
        );
      }
      return this.toSmartEdgeSnapshot(result, report);
    } catch (error) {
      throw this.toAwarenessError(error);
    }
  }

  /** Capture the foreground screenshot and its related on-screen information. */
  public async captureScreenshot(): Promise<SmartEdgeSnapshot> {
    this.assertEnabled();
    try {
      const results = await onScreen.capture(SCREENSHOT_CAPTURE_CAPABILITY);
      if (results.length === 0) {
        throw new MsdpScreenAwarenessError('SCREEN_CAPTURE_EMPTY_RESULT', 'MSDP Screenshot capture returned no result');
      }
      const failed = results.find((result: onScreen.OnscreenAwarenessInfo): boolean => result.resultCode !== 0);
      if (failed) {
        throw new MsdpScreenAwarenessError(
          'SCREEN_CAPTURE_RESULT_FAILED',
          `MSDP Screenshot capture returned resultCode ${failed.resultCode}`,
        );
      }
      const report = await this.reportSmartEdgeResult('capture', results);
      return this.toSmartEdgeSnapshot(results[0], report);
    } catch (error) {
      throw this.toAwarenessError(error);
    }
  }

  public async scrollToHook(paramsJson: string | undefined): Promise<void> {
    this.assertEnabled();
    const hookId = this.parseHookId(paramsJson);
    const snapshot = this.lastSnapshot;
    if (!snapshot) {
      throw new MsdpScreenAwarenessError('SCREEN_CONTEXT_REQUIRED', 'capture screen.context before screen.scrollToHook');
    }
    if (!snapshot.paragraphs?.some((paragraph: ScreenParagraph) => paragraph.hookId === hookId)) {
      throw new MsdpScreenAwarenessError('UNKNOWN_SCREEN_HOOK', 'hookId is not present in the latest screen context');
    }
    try {
      await onScreen.sendControlEvent({
        windowId: snapshot.windowId,
        sessionId: snapshot.sessionId,
        eventType: onScreen.EventType.SCROLL_TO_HOOK,
        hookId: hookId,
      });
    } catch (error) {
      throw this.toAwarenessError(error);
    }
  }

  private assertEnabled(): void {
    if (!this.isEnabled()) {
      throw new MsdpScreenAwarenessError('SCREEN_AWARENESS_DISABLED', 'enable Screen Awareness in Bonio settings first');
    }
  }

  private subscribeSmartEdge(): void {
    if (this.smartEdgeSubscribed) return;
    try {
      onScreen.subscribe(SMART_EDGE_CAPABILITY, this.smartEdgeListener);
      this.smartEdgeSubscribed = true;
    } catch (_) {
      // trigger() below reports service errors for the user-initiated capture.
    }
  }

  private async reportSmartEdgeResult(source: SmartEdgeResultSource, result: Object): Promise<SmartEdgeReport> {
    const report: SmartEdgeReport = { payloadJson: '' };
    try {
      report.payloadJson = JSON.stringify(result);
      const images = await this.extractMemoryImages(result);
      report.coverImageBase64 = images.coverImageBase64;
      report.originalImageBase64 = images.originalImageBase64;
      report.originalImageMimeType = images.originalImageMimeType;
      hilog.info(
        MsdpScreenAwarenessManager.DOMAIN,
        MsdpScreenAwarenessManager.TAG,
        '%{public}s result shape: %{public}s',
        source,
        this.describeResultShape(result, report.payloadJson, report.coverImageBase64, report.originalImageBase64),
      );
      if (this.onSmartEdgeResult) this.onSmartEdgeResult(source, report.payloadJson, report.coverImageBase64,
        report.originalImageBase64, report.originalImageMimeType);
    } catch (_) {
      // Diagnostic rendering must never affect MSDP subscription or capture.
    }
    return report;
  }

  private async extractMemoryImages(result: Object): Promise<MemoryImages> {
    const rows = Array.isArray(result) ? result as onScreen.OnscreenAwarenessInfo[] : [result as onScreen.OnscreenAwarenessInfo];
    for (const row of rows) {
      for (const item of row.items || []) {
        const imageValue = item.itemInfo['image'];
        if (imageValue === undefined || imageValue === null || typeof imageValue !== 'object') continue;
        try {
          const pixelMap = imageValue as image.PixelMap;
          const info = await pixelMap.getImageInfo();
          const longestEdge = Math.max(info.size.width, info.size.height);
          const scale = longestEdge > MEMORY_COVER_MAX_EDGE ? MEMORY_COVER_MAX_EDGE / longestEdge : 1;
            const original = await image.createImagePacker().packing(pixelMap, {
              format: MEMORY_ORIGINAL_IMAGE_FORMAT, quality: 100,
            });
            const coverMap = scale < 1 ? await pixelMap.createScaledPixelMap(scale, scale) : pixelMap;
            try {
              const packed = await image.createImagePacker().packing(coverMap, {
                format: 'image/jpeg', quality: MEMORY_COVER_JPEG_QUALITY,
              });
              return {
                coverImageBase64: new util.Base64Helper().encodeToStringSync(new Uint8Array(packed)),
                originalImageBase64: new util.Base64Helper().encodeToStringSync(new Uint8Array(original)),
                originalImageMimeType: MEMORY_ORIGINAL_IMAGE_FORMAT,
              };
          } finally {
            if (coverMap !== pixelMap) coverMap.release();
          }
        } catch (error) {
          hilog.warn(MsdpScreenAwarenessManager.DOMAIN, MsdpScreenAwarenessManager.TAG,
            'MSDP image is not a readable PixelMap: %{public}s', error instanceof Error ? error.message : String(error));
        }
      }
    }
    return {};
  }

  private describeResultShape(result: Object, payloadJson: string, coverImageBase64?: string,
    originalImageBase64?: string): string {
    const rows = Array.isArray(result) ? result as onScreen.OnscreenAwarenessInfo[] : [result as onScreen.OnscreenAwarenessInfo];
    const topLevelKeys = rows.length > 0 ? Object.keys(rows[0]) : [];
    const itemCount = rows.reduce((count: number, row: onScreen.OnscreenAwarenessInfo): number =>
      count + (row.items?.length || 0), 0);
    const entityCount = rows.reduce((count: number, row: onScreen.OnscreenAwarenessInfo): number =>
      count + (row.entityInfo?.length || 0), 0);
    const itemKeys = rows.flatMap((row: onScreen.OnscreenAwarenessInfo): string[] =>
      row.items?.flatMap((item: onScreen.AwarenessItem): string[] => Object.keys(item.itemInfo)) || []);
    const entityKeys = rows.flatMap((row: onScreen.OnscreenAwarenessInfo): string[] =>
      row.entityInfo?.flatMap((entity: onScreen.EntityInfo): string[] => Object.keys(entity.entityInfo)) || []);
    const pageTags = rows.flatMap((row: onScreen.OnscreenAwarenessInfo): string[] => row.pageTags || []);
    const imagePattern = /(^image$|pixelmap|screenshot|screen.?shot|bitmap|image.?data|base64)/i;
    const candidateKeys = topLevelKeys.concat(itemKeys, entityKeys)
      .filter((key: string): boolean => imagePattern.test(key));
    return JSON.stringify({
      count: rows.length,
      topLevelKeys: this.uniqueStrings(topLevelKeys),
      itemCount: itemCount,
      itemKeys: this.uniqueStrings(itemKeys),
      entityCount: entityCount,
      entityKeys: this.uniqueStrings(entityKeys),
      pageTags: this.uniqueStrings(pageTags),
      screenshotCandidateKeys: this.uniqueStrings(candidateKeys),
      memoryCoverBytes: coverImageBase64 ? Math.floor(coverImageBase64.length * 3 / 4) : 0,
      memoryOriginalBytes: originalImageBase64 ? Math.floor(originalImageBase64.length * 3 / 4) : 0,
      payloadLength: payloadJson.length,
    });
  }

  private uniqueStrings(values: string[]): string[] {
    const unique: string[] = [];
    values.forEach((value: string) => {
      if (!unique.includes(value)) unique.push(value);
    });
    return unique;
  }

  private parseMaxTextLength(paramsJson: string | undefined): number {
    if (!paramsJson) return MAX_CONTEXT_TEXT_LENGTH;
    try {
      const params = JSON.parse(paramsJson) as Record<string, number>;
      const requested = params.maxTextLength;
      if (typeof requested === 'number' && Number.isFinite(requested)) {
        return Math.max(1, Math.min(Math.floor(requested), MAX_CONTEXT_TEXT_LENGTH));
      }
    } catch (_) {
      throw new MsdpScreenAwarenessError('INVALID_REQUEST', 'screen.context params must be valid JSON');
    }
    return MAX_CONTEXT_TEXT_LENGTH;
  }

  private parseHookId(paramsJson: string | undefined): number {
    if (!paramsJson) {
      throw new MsdpScreenAwarenessError('INVALID_REQUEST', 'screen.scrollToHook requires hookId');
    }
    try {
      const params = JSON.parse(paramsJson) as Record<string, number>;
      if (typeof params.hookId === 'number' && Number.isInteger(params.hookId)) return params.hookId;
    } catch (_) {
      // The public error below is clearer than a JSON parser error to DSH.
    }
    throw new MsdpScreenAwarenessError('INVALID_REQUEST', 'screen.scrollToHook requires an integer hookId');
  }

  private toSnapshot(page: onScreen.PageContent, maxTextLength: number): ScreenContextSnapshot {
    const content = page.content;
    return {
      windowId: page.windowId,
      sessionId: page.sessionId,
      bundleName: page.bundleName,
      scenario: page.scenario,
      title: page.title,
      content: this.truncate(content, maxTextLength),
      pageLink: page.pageLink,
      paragraphs: page.paragraphs?.map((paragraph: onScreen.Paragraph): ScreenParagraph => ({
        hookId: paragraph.hookId,
        chapterId: paragraph.chapterId,
        title: paragraph.title,
        text: this.truncate(paragraph.text, maxTextLength),
      })),
      truncated: content !== undefined && content.length > maxTextLength,
    };
  }

  private toSmartEdgeSnapshot(result: onScreen.OnscreenAwarenessInfo, report: SmartEdgeReport): SmartEdgeSnapshot {
    return {
      resultCode: result.resultCode,
      timestamp: result.timestamp,
      bundleName: result.bundleName,
      appName: result.appName,
      pageId: result.pageId,
      collectStrategy: result.collectStrategy,
      pageTags: result.pageTags,
      payloadJson: report.payloadJson || JSON.stringify(result),
      coverImageBase64: report.coverImageBase64,
      originalImageBase64: report.originalImageBase64,
      originalImageMimeType: report.originalImageMimeType,
      truncated: false,
    };
  }

  private truncate(value: string | undefined, maxLength: number): string | undefined {
    return value === undefined || value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  private toAwarenessError(error: Error): MsdpScreenAwarenessError {
    const businessError = error as BusinessError;
    const code = businessError?.code;
    if (code === 201) return new MsdpScreenAwarenessError('SCREEN_PERMISSION_DENIED', 'GET_SCREEN_CONTENT permission was denied');
    if (code === 801) return new MsdpScreenAwarenessError('SCREEN_AWARENESS_UNSUPPORTED', 'MSDP on-screen awareness is unavailable on this device');
    if (code === 34000002) return new MsdpScreenAwarenessError('SCREEN_PAGE_UNSUPPORTED', 'the current page does not expose MSDP screen context');
    if (code === 34000003) return new MsdpScreenAwarenessError('SCREEN_WINDOW_INVALID', 'the current screen window is not available');
    if (code === 34000004) return new MsdpScreenAwarenessError('SCREEN_PAGE_NOT_READY', 'the current page is not ready for screen context');
    if (code === 34000006) return new MsdpScreenAwarenessError('SCREEN_CONTEXT_TIMEOUT', 'MSDP timed out while reading the current screen');
    return new MsdpScreenAwarenessError('SCREEN_AWARENESS_FAILED', businessError?.message || String(error));
  }
}
