/**
 * Parses TTS voice directives from the first line of assistant responses.
 * Port of Android's TalkDirectiveParser.kt
 *
 * Example: '{"voice":"alloy","speed":1.2}\nHello world!'
 * → directive: { voiceId: "alloy", speed: 1.2 }, stripped: "Hello world!"
 */

export interface TalkDirective {
  voiceId?: string;
  modelId?: string;
  speed?: number;
  rateWpm?: number;
  stability?: number;
  similarity?: number;
  style?: number;
  speakerBoost?: boolean;
  seed?: number;
  normalize?: string;
  language?: string;
  outputFormat?: string;
  latencyTier?: number;
  once?: boolean;
}

export interface TalkDirectiveParseResult {
  directive: TalkDirective | undefined;
  stripped: string;
  unknownKeys: string[];
}

export class TalkDirectiveParser {
  static parse(text: string): TalkDirectiveParseResult {
    const normalized = text.replace(/\r\n/g, '\n');
    const lines = normalized.split('\n');
    if (lines.length === 0) {
      return { directive: undefined, stripped: text, unknownKeys: [] };
    }

    let firstNonEmpty = -1;
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim().length > 0) {
        firstNonEmpty = i;
        break;
      }
    }
    if (firstNonEmpty === -1) {
      return { directive: undefined, stripped: text, unknownKeys: [] };
    }

    const head = lines[firstNonEmpty].trim();
    if (!head.startsWith('{') || !head.endsWith('}')) {
      return { directive: undefined, stripped: text, unknownKeys: [] };
    }

    let obj: Record<string, Object> | undefined = undefined;
    try {
      obj = JSON.parse(head) as Record<string, Object>;
    } catch (_e) {
      return { directive: undefined, stripped: text, unknownKeys: [] };
    }
    if (!obj) {
      return { directive: undefined, stripped: text, unknownKeys: [] };
    }

    const speakerBoostVal =
      TalkDirectiveParser.boolValue(obj, ['speaker_boost', 'speakerBoost']);
    const noBoost = TalkDirectiveParser.boolValue(obj, ['no_speaker_boost', 'noSpeakerBoost']);
    const speakerBoost = speakerBoostVal !== undefined
      ? speakerBoostVal
      : (noBoost !== undefined ? !noBoost : undefined);

    const directive: TalkDirective = {
      voiceId: TalkDirectiveParser.stringValue(obj, ['voice', 'voice_id', 'voiceId']),
      modelId: TalkDirectiveParser.stringValue(obj, ['model', 'model_id', 'modelId']),
      speed: TalkDirectiveParser.doubleValue(obj, ['speed']),
      rateWpm: TalkDirectiveParser.intValue(obj, ['rate', 'wpm']),
      stability: TalkDirectiveParser.doubleValue(obj, ['stability']),
      similarity: TalkDirectiveParser.doubleValue(obj, ['similarity', 'similarity_boost', 'similarityBoost']),
      style: TalkDirectiveParser.doubleValue(obj, ['style']),
      speakerBoost: speakerBoost,
      seed: TalkDirectiveParser.intValue(obj, ['seed']),
      normalize: TalkDirectiveParser.stringValue(obj, ['normalize', 'apply_text_normalization']),
      language: TalkDirectiveParser.stringValue(obj, ['lang', 'language_code', 'language']),
      outputFormat: TalkDirectiveParser.stringValue(obj, ['output_format', 'format']),
      latencyTier: TalkDirectiveParser.intValue(obj, ['latency', 'latency_tier', 'latencyTier']),
      once: TalkDirectiveParser.boolValue(obj, ['once']),
    };

    const hasDirective = [
      directive.voiceId, directive.modelId, directive.speed,
      directive.rateWpm, directive.stability, directive.similarity,
      directive.style, directive.speakerBoost, directive.seed,
      directive.normalize, directive.language, directive.outputFormat,
      directive.latencyTier, directive.once,
    ].some((v: string | number | boolean | undefined) => v !== undefined);

    if (!hasDirective) {
      return { directive: undefined, stripped: text, unknownKeys: [] };
    }

    const knownKeys = new Set<string>([
      'voice', 'voice_id', 'voiceid',
      'model', 'model_id', 'modelid',
      'speed', 'rate', 'wpm',
      'stability', 'similarity', 'similarity_boost', 'similarityboost',
      'style',
      'speaker_boost', 'speakerboost',
      'no_speaker_boost', 'nospeakerboost',
      'seed',
      'normalize', 'apply_text_normalization',
      'lang', 'language_code', 'language',
      'output_format', 'format',
      'latency', 'latency_tier', 'latencytier',
      'once',
    ]);
    const unknownKeys = Object.keys(obj)
      .filter((k: string) => !knownKeys.has(k.toLowerCase()))
      .sort();

    // Remove directive line and optional blank line after it
    const remaining = [...lines];
    remaining.splice(firstNonEmpty, 1);
    if (firstNonEmpty < remaining.length && remaining[firstNonEmpty].trim().length === 0) {
      remaining.splice(firstNonEmpty, 1);
    }

    return { directive: directive, stripped: remaining.join('\n'), unknownKeys: unknownKeys };
  }

  private static stringValue(obj: Record<string, Object>, keys: string[]): string | undefined {
    for (const key of keys) {
      const value = obj[key];
      if (typeof value === 'string') {
        const trimmed = (value as string).trim();
        if (trimmed.length > 0) return trimmed;
      }
    }
    return undefined;
  }

  private static doubleValue(obj: Record<string, Object>, keys: string[]): number | undefined {
    for (const key of keys) {
      const value = obj[key];
      if (typeof value === 'number') return value as number;
      if (typeof value === 'string') {
        const num = parseFloat(value as string);
        if (!isNaN(num)) return num;
      }
    }
    return undefined;
  }

  private static intValue(obj: Record<string, Object>, keys: string[]): number | undefined {
    for (const key of keys) {
      const value = obj[key];
      if (typeof value === 'number') return Math.floor(value as number);
      if (typeof value === 'string') {
        const num = parseInt(value as string, 10);
        if (!isNaN(num)) return num;
      }
    }
    return undefined;
  }

  private static boolValue(obj: Record<string, Object>, keys: string[]): boolean | undefined {
    for (const key of keys) {
      const value = obj[key];
      if (typeof value === 'boolean') return value as boolean;
      if (typeof value === 'string') {
        const lower = (value as string).trim().toLowerCase();
        if (lower === 'true' || lower === 'yes' || lower === '1') return true;
        if (lower === 'false' || lower === 'no' || lower === '0') return false;
      }
      if (typeof value === 'number') {
        if (value === 1) return true;
        if (value === 0) return false;
      }
    }
    return undefined;
  }
}
