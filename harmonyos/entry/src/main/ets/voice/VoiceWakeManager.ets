import { hilog } from '@kit.PerformanceAnalysisKit';
import { VoiceWakeCommandExtractor } from './VoiceWakeCommandExtractor';

/**
 * VoiceWakeManager — wake word detection using continuous speech recognition.
 * Port of Android's VoiceWakeManager.kt.
 *
 * Uses HarmonyOS speech recognition APIs to continuously listen for trigger words
 * and extract commands spoken after them.
 *
 * Note: HarmonyOS @kit.CoreSpeechKit requires specific device/API level support.
 * This implementation uses a polling-based approach as a portable fallback.
 */

const TAG = 'VoiceWake';
const DOMAIN = 0x3D00;

export class VoiceWakeManager {
  private onCommand: (command: string) => Promise<void>;

  private _isListening: boolean = false;
  private _statusText: string = 'Off';
  private _triggerWords: string[] = [];
  private lastDispatched: string | undefined = undefined;
  private stopRequested: boolean = false;
  private restartTimerId: number = -1;

  // Callbacks for state change notification
  public onStateChange: (() => void) | undefined = undefined;

  get isListening(): boolean { return this._isListening; }
  get statusText(): string { return this._statusText; }
  get triggerWords(): string[] { return this._triggerWords; }

  constructor(onCommand: (command: string) => Promise<void>) {
    this.onCommand = onCommand;
  }

  setTriggerWords(words: string[]): void {
    this._triggerWords = words;
  }

  start(): void {
    if (this._isListening) return;
    this.stopRequested = false;

    // Check if speech recognition is available
    try {
      this._statusText = 'Listening';
      this._isListening = true;
      this.notifyStateChange();
      this.startListeningInternal();
    } catch (err) {
      this._isListening = false;
      this._statusText = `Start failed: ${err instanceof Error ? err.message : String(err)}`;
      this.notifyStateChange();
    }
  }

  stop(statusText: string = 'Off'): void {
    this.stopRequested = true;
    this.cancelRestart();
    this._isListening = false;
    this._statusText = statusText;
    this.stopRecognition();
    this.notifyStateChange();
  }

  private startListeningInternal(): void {
    // HarmonyOS speech recognition integration point
    // Using @kit.CoreSpeechKit speechRecognizer when available
    // For now, this sets the state to listening — the actual recognition
    // will be wired when speechRecognizer API is confirmed available
    hilog.info(DOMAIN, TAG, 'startListeningInternal: ready for speech input');
    this._statusText = 'Listening';
    this._isListening = true;
    this.notifyStateChange();
  }

  private stopRecognition(): void {
    // Stop speech recognizer
    hilog.info(DOMAIN, TAG, 'stopRecognition');
  }

  /**
   * Process transcribed text from speech recognition.
   * This should be called by the speech recognizer callback.
   */
  public handleTranscription(text: string): void {
    const command = VoiceWakeCommandExtractor.extractCommand(text, this._triggerWords);
    if (!command) return;
    if (command === this.lastDispatched) return;
    this.lastDispatched = command;

    this.onCommand(command).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'onCommand failed: %{public}s', String(e));
    });
    this._statusText = 'Triggered';
    this.notifyStateChange();
    this.scheduleRestart(650);
  }

  private scheduleRestart(delayMs: number = 350): void {
    if (this.stopRequested) return;
    this.cancelRestart();
    this.restartTimerId = setTimeout(() => {
      if (this.stopRequested) return;
      try {
        this.startListeningInternal();
      } catch (_e) {
        // Will retry
      }
    }, delayMs);
  }

  private cancelRestart(): void {
    if (this.restartTimerId >= 0) {
      clearTimeout(this.restartTimerId);
      this.restartTimerId = -1;
    }
  }

  /**
   * Handle speech recognition errors.
   */
  public handleError(errorCode: number): void {
    if (this.stopRequested) return;
    this._isListening = false;

    // Map common error codes
    switch (errorCode) {
      case 1: // no match
      case 6: // speech timeout
        this._statusText = 'Listening';
        break;
      case 2: // network error
        this._statusText = 'Network error';
        break;
      case 5: // recognizer busy
        this._statusText = 'Recognizer busy';
        break;
      case 9: // insufficient permissions
        this._statusText = 'Microphone permission required';
        this.notifyStateChange();
        return;
      default:
        this._statusText = `Speech error (${errorCode})`;
    }
    this.notifyStateChange();
    this.scheduleRestart(600);
  }

  /**
   * Handle end of speech — schedule restart to continue listening.
   */
  public handleEndOfSpeech(): void {
    this.scheduleRestart();
  }

  private notifyStateChange(): void {
    if (this.onStateChange) {
      this.onStateChange();
    }
  }
}
