/**
 * Utility for parsing and managing voice wake trigger words.
 */
export class WakeWords {
  static readonly maxWords: number = 32;
  static readonly maxWordLength: number = 64;

  static parseCommaSeparated(input: string): string[] {
    return input.split(',')
      .map((s: string) => s.trim())
      .filter((s: string) => s.length > 0);
  }

  static parseIfChanged(input: string, current: string[]): string[] | undefined {
    const parsed = WakeWords.parseCommaSeparated(input);
    if (parsed.length === current.length &&
      parsed.every((val: string, idx: number) => val === current[idx])) {
      return undefined;
    }
    return parsed;
  }

  static sanitize(words: string[], defaults: string[]): string[] {
    const cleaned = words
      .map((s: string) => s.trim())
      .filter((s: string) => s.length > 0)
      .slice(0, WakeWords.maxWords)
      .map((s: string) => s.substring(0, WakeWords.maxWordLength));
    return cleaned.length > 0 ? cleaned : defaults;
  }
}
