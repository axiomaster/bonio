/**
 * Extracts a command from transcribed speech by matching trigger words.
 * Port of Android's VoiceWakeCommandExtractor.kt
 */
export class VoiceWakeCommandExtractor {
  /**
   * Given transcribed text and a list of trigger words, extracts the command
   * spoken after the trigger word.
   *
   * Example: text = "hey claw open the browser"  trigger = "hey claw"
   *          returns "open the browser"
   */
  static extractCommand(text: string, triggerWords: string[]): string | undefined {
    const raw = text.trim();
    if (raw.length === 0) return undefined;

    const triggers = triggerWords
      .map((w: string) => w.trim().toLowerCase())
      .filter((w: string) => w.length > 0);
    // Remove duplicates
    const uniqueTriggers: string[] = [];
    for (const t of triggers) {
      if (uniqueTriggers.indexOf(t) < 0) uniqueTriggers.push(t);
    }
    if (uniqueTriggers.length === 0) return undefined;

    const alternation = uniqueTriggers
      .map((w: string) => VoiceWakeCommandExtractor.escapeRegex(w))
      .join('|');
    // Match: "<anything> <trigger><punct/space> <command>"
    const regex = new RegExp(`(?:^|\\s)(${alternation})\\b[\\s\\p{P}]*([\\s\\S]+)$`, 'iu');
    const match = regex.exec(raw);
    if (!match || !match[2]) return undefined;
    const extracted = match[2].trim();
    if (extracted.length === 0) return undefined;

    // Strip leading whitespace and punctuation
    let cleaned = extracted;
    while (cleaned.length > 0 && VoiceWakeCommandExtractor.isWhitespaceOrPunct(cleaned.charAt(0))) {
      cleaned = cleaned.substring(1);
    }
    cleaned = cleaned.trim();
    return cleaned.length === 0 ? undefined : cleaned;
  }

  private static escapeRegex(str: string): string {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private static isWhitespaceOrPunct(ch: string): boolean {
    if (/\s/.test(ch)) return true;
    // Common punctuation
    if (/[.,;:!?'"()\[\]{}\-\/\\@#$%^&*_+=<>~`]/.test(ch)) return true;
    return false;
  }
}
