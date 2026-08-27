/**
 * IntentRouter — local STT intent classification.
 *
 * Port of hiclaw's intent_router.cpp into ArkTS. Classifies voice/final STT
 * transcripts into Chat / ScreenCapture / Summarize intents using keyword
 * matching, so the on-device bonio-app no longer needs the hiclaw backend
 * for this decision.
 */

export enum Intent {
  Chat = 'chat',
  ScreenCapture = 'screen_capture',
  Summarize = 'summarize',
}

const CAPTURE_KEYWORDS: string[] = [
  'save this', 'remember this', 'note this', 'screenshot', 'take a picture',
  'capture this', 'save what',
  '记一下', '帮我存', '保存一下', '帮我记', '截图', '截个图', '拍下来',
];

const SUMMARIZE_KEYWORDS: string[] = [
  'summarize', 'summary', 'read this', 'too long', 'what does this say',
  'tldr', 'read it',
  '太长了', '帮我总结', '总结一下', '帮我看看', '帮我读', '读一下',
  '看一下', '读给我听',
];

export class IntentRouter {
  private containsAny(text: string, keywords: string[]): boolean {
    for (const kw of keywords) {
      if (text.includes(kw)) return true;
    }
    return false;
  }

  /** Classify a transcript; defaults to Chat. */
  classify(text: string): Intent {
    const lower = text.toLowerCase();
    if (this.containsAny(lower, SUMMARIZE_KEYWORDS)) return Intent.Summarize;
    if (this.containsAny(lower, CAPTURE_KEYWORDS)) return Intent.ScreenCapture;
    return Intent.Chat;
  }
}
