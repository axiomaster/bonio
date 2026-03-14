import { hilog } from '@kit.PerformanceAnalysisKit';
import { A2UIHandler } from '../InvokeDispatcher';
import { CanvasController } from '../CanvasController';

type A2UIJsonObject = Record<string, Object>;

interface A2UIParamsObject {
  jsonl?: string;
  messages?: Object[];
}

export class A2UIHandlerImpl implements A2UIHandler {
  private static readonly TAG = 'A2UIHandler';
  private static readonly DOMAIN = 0x3D00;
  private canvas: CanvasController;
  private getNodeCanvasHostUrl: () => string | undefined;
  private getOperatorCanvasHostUrl: () => string | undefined;

  constructor(
    canvas: CanvasController,
    getNodeCanvasHostUrl: () => string | undefined,
    getOperatorCanvasHostUrl: () => string | undefined
  ) {
    this.canvas = canvas;
    this.getNodeCanvasHostUrl = getNodeCanvasHostUrl;
    this.getOperatorCanvasHostUrl = getOperatorCanvasHostUrl;
  }

  resolveA2uiHostUrl(): string | undefined {
    const nodeRaw = (this.getNodeCanvasHostUrl() || '').trim();
    const operatorRaw = (this.getOperatorCanvasHostUrl() || '').trim();
    const raw = nodeRaw.length > 0 ? nodeRaw : operatorRaw;
    if (raw.length === 0) return undefined;
    const base = raw.endsWith('/') ? raw.slice(0, -1) : raw;
    return `${base}/__openclaw__/a2ui/?platform=harmonyos`;
  }

  ensureA2uiReady(url: string): boolean {
    // Synchronous check — navigate and hope it's ready.
    // Full async polling would require changing the interface to async.
    try {
      const already = this.canvas.eval(A2UIHandlerImpl.A2UI_READY_CHECK_JS);
      if (already === 'true') return true;
    } catch (_e) {
      // ignore
    }
    this.canvas.navigate(url);
    return false;
  }

  decodeA2uiMessages(command: string, paramsJson: string | undefined): string | undefined {
    const raw = (paramsJson || '').trim();
    if (raw.length === 0) {
      hilog.error(A2UIHandlerImpl.DOMAIN, A2UIHandlerImpl.TAG, 'decodeA2uiMessages: empty params');
      return undefined;
    }

    try {
      const obj = JSON.parse(raw) as A2UIParamsObject;

      const jsonlField = (obj.jsonl || '').trim();
      const hasMessagesArray = Array.isArray(obj.messages);

      if (command === 'canvas.a2ui.pushJSONL' || (!hasMessagesArray && jsonlField.length > 0)) {
        if (jsonlField.length === 0) {
          hilog.error(A2UIHandlerImpl.DOMAIN, A2UIHandlerImpl.TAG, 'decodeA2uiMessages: jsonl required');
          return undefined;
        }
        const lines = jsonlField.split('\n');
        const messages: A2UIJsonObject[] = [];
        for (let idx = 0; idx < lines.length; idx++) {
          const line = lines[idx].trim();
          if (line.length === 0) continue;
          const msg = JSON.parse(line) as A2UIJsonObject;
          this.validateA2uiV0_8(msg, idx + 1);
          messages.push(msg);
        }
        return JSON.stringify(messages);
      }

      if (!hasMessagesArray || !obj.messages) {
        hilog.error(A2UIHandlerImpl.DOMAIN, A2UIHandlerImpl.TAG, 'decodeA2uiMessages: messages[] required');
        return undefined;
      }

      const out: A2UIJsonObject[] = [];
      for (let idx = 0; idx < obj.messages.length; idx++) {
        const msg = obj.messages[idx] as A2UIJsonObject;
        this.validateA2uiV0_8(msg, idx + 1);
        out.push(msg);
      }
      return JSON.stringify(out);
    } catch (e) {
      hilog.error(A2UIHandlerImpl.DOMAIN, A2UIHandlerImpl.TAG, 'decodeA2uiMessages failed: %{public}s', String(e));
      return undefined;
    }
  }

  private validateA2uiV0_8(msg: A2UIJsonObject, lineNumber: number): void {
    const keys = Object.keys(msg);
    if (keys.indexOf('createSurface') >= 0) {
      throw new Error(`A2UI JSONL line ${lineNumber}: looks like A2UI v0.9 (createSurface). Canvas supports v0.8 messages only.`);
    }
    const allowed = ['beginRendering', 'surfaceUpdate', 'dataModelUpdate', 'deleteSurface'];
    const matched = keys.filter((k: string) => allowed.indexOf(k) >= 0);
    if (matched.length !== 1) {
      const found = keys.sort().join(', ');
      throw new Error(`A2UI JSONL line ${lineNumber}: expected exactly one of ${allowed.sort().join(', ')}; found: ${found}`);
    }
  }

  get a2uiResetJS(): string {
    return A2UIHandlerImpl.A2UI_RESET_JS;
  }

  a2uiApplyMessagesJS(messagesJson: string): string {
    return `
      (() => {
        try {
          const host = globalThis.openclawA2UI;
          if (!host) return { ok: false, error: "missing openclawA2UI" };
          const messages = ${messagesJson};
          return host.applyMessages(messages);
        } catch (e) {
          return { ok: false, error: String(e?.message ?? e) };
        }
      })()
    `;
  }

  private static readonly A2UI_READY_CHECK_JS: string =
    `(() => {
      try {
        const host = globalThis.openclawA2UI;
        return !!host && typeof host.applyMessages === 'function';
      } catch (_) {
        return false;
      }
    })()`;

  private static readonly A2UI_RESET_JS: string =
    `(() => {
      try {
        const host = globalThis.openclawA2UI;
        if (!host) return { ok: false, error: "missing openclawA2UI" };
        return host.reset();
      } catch (e) {
        return { ok: false, error: String(e?.message ?? e) };
      }
    })()`;
}
