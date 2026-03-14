import { hilog } from '@kit.PerformanceAnalysisKit';
import { Context } from '@kit.AbilityKit';

export class ToolDisplaySummary {
  name: string = '';
  emoji: string = '🧩';
  title: string = '';
  label: string = '';
  verb: string | undefined = undefined;
  detail: string | undefined = undefined;

  get detailLine(): string | undefined {
    const parts: string[] = [];
    if (this.verb && this.verb.trim().length > 0) parts.push(this.verb);
    if (this.detail && this.detail.trim().length > 0) parts.push(this.detail);
    return parts.length === 0 ? undefined : parts.join(' · ');
  }

  get summaryLine(): string {
    const dl = this.detailLine;
    return dl ? `${this.emoji} ${this.label}: ${dl}` : `${this.emoji} ${this.label}`;
  }
}

interface ToolDisplayActionSpec {
  label?: string;
  detailKeys?: string[];
}

interface ToolDisplaySpec {
  emoji?: string;
  title?: string;
  label?: string;
  detailKeys?: string[];
  actions?: Record<string, ToolDisplayActionSpec>;
}

interface ToolDisplayConfig {
  version?: number;
  fallback?: ToolDisplaySpec;
  tools?: Record<string, ToolDisplaySpec>;
}

export class ToolDisplayRegistry {
  private static cachedConfig: ToolDisplayConfig | undefined = undefined;

  static resolve(
    context: Context,
    name: string | undefined,
    argsJson: string | undefined,
    meta: string | undefined = undefined
  ): ToolDisplaySummary {
    const trimmedName = (name || '').trim() || 'tool';
    const key = trimmedName.toLowerCase();
    const config = ToolDisplayRegistry.loadConfig(context);
    const spec: ToolDisplaySpec | undefined = config.tools ? config.tools[key] : undefined;
    const fallback: ToolDisplaySpec | undefined = config.fallback;

    const summary = new ToolDisplaySummary();
    summary.name = trimmedName;
    summary.emoji = spec?.emoji || fallback?.emoji || '🧩';
    summary.title = spec?.title || ToolDisplayRegistry.titleFromName(trimmedName);
    summary.label = spec?.label || trimmedName;

    let args: Record<string, Object> | undefined = undefined;
    if (argsJson && argsJson.trim().length > 0) {
      try {
        args = JSON.parse(argsJson) as Record<string, Object>;
      } catch (_e) {
        // ignore
      }
    }

    const actionRaw = ToolDisplayRegistry.asStringOrNull(args, 'action')?.trim();
    const action = actionRaw && actionRaw.length > 0 ? actionRaw : undefined;
    const actionSpec: ToolDisplayActionSpec | undefined =
      action && spec?.actions ? spec.actions[action] : undefined;
    summary.verb = ToolDisplayRegistry.normalizeVerb(actionSpec?.label || action);

    let detail: string | undefined = undefined;
    if (key === 'read') {
      detail = ToolDisplayRegistry.readDetail(args);
    } else if (key === 'write' || key === 'edit' || key === 'attach') {
      detail = ToolDisplayRegistry.pathDetail(args);
    }

    const detailKeys: string[] =
      actionSpec?.detailKeys || spec?.detailKeys || fallback?.detailKeys || [];
    if (!detail) {
      detail = ToolDisplayRegistry.firstValue(args, detailKeys);
    }
    if (!detail) {
      detail = meta;
    }

    summary.detail = detail;
    return summary;
  }

  private static loadConfig(context: Context): ToolDisplayConfig {
    if (ToolDisplayRegistry.cachedConfig) return ToolDisplayRegistry.cachedConfig;
    try {
      const mgr = context.resourceManager;
      const data = mgr.getRawFileContentSync('tool-display.json');
      const jsonStr = ToolDisplayRegistry.uint8ArrayToString(data);
      const config = JSON.parse(jsonStr) as ToolDisplayConfig;
      ToolDisplayRegistry.cachedConfig = config;
      return config;
    } catch (e) {
      hilog.warn(0x3D00, 'ToolDisplay', 'loadConfig failed: %{public}s', String(e));
      const fallback: ToolDisplayConfig = {};
      ToolDisplayRegistry.cachedConfig = fallback;
      return fallback;
    }
  }

  private static uint8ArrayToString(arr: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeWithStream(arr);
  }

  private static titleFromName(name: string): string {
    const cleaned = name.replace(/_/g, ' ').trim();
    if (cleaned.length === 0) return 'Tool';
    return cleaned
      .split(/\s+/)
      .map((part: string) => {
        const upper = part.toUpperCase();
        if (part.length <= 2 && part === upper) return part;
        return upper.charAt(0) + part.toLowerCase().slice(1);
      })
      .join(' ');
  }

  private static normalizeVerb(value: string | undefined): string | undefined {
    const trimmed = (value || '').trim();
    if (trimmed.length === 0) return undefined;
    return trimmed.replace(/_/g, ' ');
  }

  private static readDetail(args: Record<string, Object> | undefined): string | undefined {
    const path = ToolDisplayRegistry.asStringOrNull(args, 'path');
    if (!path) return undefined;
    const offset = ToolDisplayRegistry.asNumberOrNull(args, 'offset');
    const limit = ToolDisplayRegistry.asNumberOrNull(args, 'limit');
    if (offset !== undefined && limit !== undefined) {
      const end = offset + limit;
      return `${path}:${Math.floor(offset)}-${Math.floor(end)}`;
    }
    return path;
  }

  private static pathDetail(args: Record<string, Object> | undefined): string | undefined {
    return ToolDisplayRegistry.asStringOrNull(args, 'path');
  }

  private static firstValue(
    args: Record<string, Object> | undefined,
    keys: string[]
  ): string | undefined {
    for (const key of keys) {
      const value = ToolDisplayRegistry.valueForPath(args, key);
      const rendered = ToolDisplayRegistry.renderValue(value);
      if (rendered && rendered.trim().length > 0) return rendered;
    }
    return undefined;
  }

  private static valueForPath(
    args: Record<string, Object> | undefined,
    path: string
  ): Object | undefined {
    let current: Object | undefined = args;
    const segments = path.split('.');
    for (const segment of segments) {
      if (!segment || segment.length === 0) return undefined;
      if (current === null || current === undefined) return undefined;
      if (typeof current !== 'object') return undefined;
      current = (current as Record<string, Object>)[segment];
    }
    return current;
  }

  private static renderValue(value: Object | undefined): string | undefined {
    if (value === null || value === undefined) return undefined;

    if (typeof value === 'string') {
      const trimmed = (value as string).trim();
      if (trimmed.length === 0) return undefined;
      const firstLine = trimmed.split('\n')[0].trim();
      if (firstLine.length === 0) return undefined;
      return firstLine.length > 160 ? firstLine.substring(0, 157) + '…' : firstLine;
    }

    if (typeof value === 'boolean' || typeof value === 'number') {
      return String(value);
    }

    if (Array.isArray(value)) {
      const items = (value as Object[])
        .map((item: Object) => ToolDisplayRegistry.renderValue(item))
        .filter((item: string | undefined) => item !== undefined) as string[];
      if (items.length === 0) return undefined;
      const preview = items.slice(0, 3).join(', ');
      return items.length > 3 ? `${preview}…` : preview;
    }

    return undefined;
  }

  private static asStringOrNull(
    obj: Record<string, Object> | undefined,
    key: string
  ): string | undefined {
    if (!obj) return undefined;
    const value = obj[key];
    if (typeof value === 'string') return value as string;
    if (typeof value === 'number' || typeof value === 'boolean') return String(value);
    return undefined;
  }

  private static asNumberOrNull(
    obj: Record<string, Object> | undefined,
    key: string
  ): number | undefined {
    if (!obj) return undefined;
    const value = obj[key];
    if (typeof value === 'number') return value as number;
    if (typeof value === 'string') {
      const num = Number(value);
      return isNaN(num) ? undefined : num;
    }
    return undefined;
  }
}

import { util } from '@kit.ArkTS';
