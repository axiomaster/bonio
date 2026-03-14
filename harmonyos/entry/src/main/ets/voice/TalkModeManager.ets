import { hilog } from '@kit.PerformanceAnalysisKit';
import { GatewaySession } from '../gateway/GatewaySession';
import { TalkDirectiveParser, TalkDirective } from './TalkDirectiveParser';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

/**
 * TalkModeManager — Full duplex talk mode with speech-to-text + TTS.
 * Port of Android's TalkModeManager.kt (1258 lines).
 *
 * Flow:
 * 1. Listen for speech via microphone (HarmonyOS speech recognizer)
 * 2. Detect silence → finalize transcript
 * 3. Send transcript to server via chat.send
 * 4. Wait for assistant response
 * 5. Play response via TTS (ElevenLabs or system fallback)
 * 6. Loop back to listening
 */

const TAG = 'TalkMode';
const DOMAIN = 0x3D00;
const DEFAULT_MODEL_ID = 'eleven_v3';
const DEFAULT_OUTPUT_FORMAT = 'pcm_24000';

export class TalkModeManager {
  private session: GatewaySession;
  private isConnectedFn: () => boolean;

  // State
  private _isEnabled: boolean = false;
  private _isListening: boolean = false;
  private _isSpeaking: boolean = false;
  private _statusText: string = 'Off';
  private _lastAssistantText: string | undefined = undefined;
  private _usingFallbackTts: boolean = false;

  // Speech recognition
  private stopRequested: boolean = false;
  private listeningMode: boolean = false;
  private lastTranscript: string = '';
  private lastHeardAtMs: number | undefined = undefined;
  private silenceTimerId: number = -1;
  private restartTimerId: number = -1;
  private silenceWindowMs: number = 700;

  // TTS config
  private defaultVoiceId: string | undefined = undefined;
  private currentVoiceId: string | undefined = undefined;
  private defaultModelId: string | undefined = undefined;
  private currentModelId: string | undefined = undefined;
  private defaultOutputFormat: string | undefined = undefined;
  private apiKey: string | undefined = undefined;
  private voiceAliases: Map<string, string> = new Map();
  private interruptOnSpeech: boolean = true;
  private voiceOverrideActive: boolean = false;
  private modelOverrideActive: boolean = false;
  private mainSessionKey: string = 'main';

  // Run tracking
  private pendingRunId: string | undefined = undefined;
  private lastSpokenText: string | undefined = undefined;
  private lastInterruptedAtSeconds: number | undefined = undefined;

  // Callbacks
  public onStateChange: (() => void) | undefined = undefined;

  // Getters
  get isEnabled(): boolean { return this._isEnabled; }
  get isListening(): boolean { return this._isListening; }
  get isSpeaking(): boolean { return this._isSpeaking; }
  get statusText(): string { return this._statusText; }
  get lastAssistantText(): string | undefined { return this._lastAssistantText; }
  get usingFallbackTts(): boolean { return this._usingFallbackTts; }

  constructor(
    session: GatewaySession,
    isConnected: () => boolean,
  ) {
    this.session = session;
    this.isConnectedFn = isConnected;
  }

  setMainSessionKey(sessionKey: string | undefined): void {
    const trimmed = (sessionKey || '').trim();
    if (trimmed.length === 0) return;
    if (this.mainSessionKey === 'main') return;
    this.mainSessionKey = trimmed;
  }

  setEnabled(enabled: boolean): void {
    if (this._isEnabled === enabled) return;
    this._isEnabled = enabled;
    if (enabled) {
      hilog.debug(DOMAIN, TAG, 'enabled');
      this.startInternal();
    } else {
      hilog.debug(DOMAIN, TAG, 'disabled');
      this.stopInternal();
    }
    this.notifyStateChange();
  }

  handleGatewayEvent(event: string, payloadJson: string | undefined): void {
    if (event !== 'chat') return;
    if (!payloadJson || payloadJson.trim().length === 0) return;
    const pending = this.pendingRunId;
    if (!pending) return;
    try {
      const obj = JSON.parse(payloadJson) as Record<string, Object>;
      const runId = obj['runId'] as string | undefined;
      if (runId !== pending) return;
      const state = obj['state'] as string | undefined;
      if (state === 'final') {
        this.pendingRunId = undefined;
      }
    } catch (_e) {
      // ignore
    }
  }

  private startInternal(): void {
    if (this._isListening) return;
    this.stopRequested = false;
    this.listeningMode = true;
    hilog.debug(DOMAIN, TAG, 'start');

    this._statusText = 'Listening';
    this._isListening = true;
    this.notifyStateChange();
    this.startSilenceMonitor();
  }

  private stopInternal(): void {
    this.stopRequested = true;
    this.listeningMode = false;
    this.cancelRestart();
    this.cancelSilenceMonitor();
    this.lastTranscript = '';
    this.lastHeardAtMs = undefined;
    this._isListening = false;
    this._statusText = 'Off';
    this._usingFallbackTts = false;
    this.notifyStateChange();
  }

  /**
   * Process transcribed text from speech recognition.
   * Called by the speech recognizer callback.
   */
  public handleTranscript(text: string, isFinal: boolean): void {
    const trimmed = text.trim();

    if (this._isSpeaking && this.interruptOnSpeech) {
      if (this.shouldInterrupt(trimmed)) {
        this.stopSpeaking();
      }
      return;
    }

    if (!this._isListening) return;

    if (trimmed.length > 0) {
      this.lastTranscript = trimmed;
      this.lastHeardAtMs = Date.now();
    }

    if (isFinal) {
      this.lastTranscript = trimmed;
    }
  }

  private startSilenceMonitor(): void {
    this.cancelSilenceMonitor();
    this.silenceTimerId = setInterval(() => {
      this.checkSilence();
    }, 200);
  }

  private cancelSilenceMonitor(): void {
    if (this.silenceTimerId >= 0) {
      clearInterval(this.silenceTimerId);
      this.silenceTimerId = -1;
    }
  }

  private checkSilence(): void {
    if (!this._isListening) return;
    const transcript = this.lastTranscript.trim();
    if (transcript.length === 0) return;
    const lastHeard = this.lastHeardAtMs;
    if (lastHeard === undefined) return;
    const elapsed = Date.now() - lastHeard;
    if (elapsed < this.silenceWindowMs) return;
    this.finalizeTranscript(transcript);
  }

  private async finalizeTranscript(transcript: string): Promise<void> {
    this.listeningMode = false;
    this._isListening = false;
    this._statusText = 'Thinking…';
    this.lastTranscript = '';
    this.lastHeardAtMs = undefined;
    this.notifyStateChange();

    await this.reloadConfig();
    const prompt = this.buildPrompt(transcript);

    if (!this.isConnectedFn()) {
      this._statusText = 'Gateway not connected';
      hilog.warn(DOMAIN, TAG, 'finalize: gateway not connected');
      this.notifyStateChange();
      this.startInternal();
      return;
    }

    try {
      const startedAt = Date.now() / 1000.0;
      const resVal = await this.sendChat(prompt);
      const runId = this.parseRunIdFromObj(resVal);
      hilog.debug(DOMAIN, TAG, 'chat.send ok runId=%{public}s', runId);

      const assistantText = await this.waitForAssistantText(startedAt, 25000);
      if (!assistantText || assistantText.trim().length === 0) {
        this._statusText = 'No reply';
        hilog.warn(DOMAIN, TAG, 'assistant text timeout runId=%{public}s', runId);
        this.notifyStateChange();
        this.startInternal();
        return;
      }

      hilog.debug(DOMAIN, TAG, 'assistant text ok chars=%{public}d', assistantText.length);
      await this.playAssistant(assistantText);
    } catch (err) {
      this._statusText = `Talk failed: ${err instanceof Error ? err.message : String(err)}`;
      hilog.warn(DOMAIN, TAG, 'finalize failed: %{public}s', String(err));
      this.notifyStateChange();
    }

    if (this._isEnabled) {
      this.startInternal();
    }
  }

  private buildPrompt(transcript: string): string {
    const lines: string[] = [
      'Talk Mode active. Reply in a concise, spoken tone.',
      'You may optionally prefix the response with JSON (first line) to set ElevenLabs voice.',
    ];
    if (this.lastInterruptedAtSeconds !== undefined) {
      lines.push(`Assistant speech interrupted at ${this.lastInterruptedAtSeconds.toFixed(1)}s.`);
      this.lastInterruptedAtSeconds = undefined;
    }
    lines.push('');
    lines.push(transcript);
    return lines.join('\n');
  }

  private async sendChat(message: string): Promise<Object> {
    const runId = this.generateUuid();
    const params: Record<string, Object> = {
      'sessionKey': this.mainSessionKey || 'main',
      'message': message,
      'thinking': 'low',
      'timeoutMs': 30000,
      'idempotencyKey': runId,
    };
    return await this.session.request('chat.send', params);
  }

  private async waitForAssistantText(sinceSeconds: number, timeoutMs: number): Promise<string | undefined> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const text = await this.fetchLatestAssistantText(sinceSeconds);
      if (text && text.trim().length > 0) return text;
      await this.delay(300);
    }
    return undefined;
  }

  private async fetchLatestAssistantText(sinceSeconds: number): Promise<string | undefined> {
    const key = this.mainSessionKey || 'main';
    const params: Record<string, Object> = { 'sessionKey': key };
    const res = await this.session.request('chat.history', params);
    try {
      const payload = res.payload as Record<string, Object> || (res.payloadJSON ? JSON.parse(res.payloadJSON) as Record<string, Object> : undefined);
      if (!payload) return undefined;
      const messages = payload['messages'] as Object[];
      if (!Array.isArray(messages)) return undefined;

      for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i] as Record<string, Object>;
        if (msg['role'] !== 'assistant') continue;
        const timestampMs = msg['timestamp'] as number | undefined;
        if (timestampMs !== undefined && (timestampMs / 1000.0) < sinceSeconds) continue;
        const content = msg['content'] as Object[];
        if (!Array.isArray(content)) continue;
        const texts: string[] = [];
        for (const entry of content) {
          const entryObj = entry as Record<string, Object>;
          const textVal = entryObj['text'] as string | undefined;
          if (textVal && textVal.trim().length > 0) texts.push(textVal.trim());
        }
        if (texts.length > 0) return texts.join('\n');
      }
    } catch (_e) {
      // ignore
    }
    return undefined;
  }

  private async playAssistant(text: string): Promise<void> {
    const parsed = TalkDirectiveParser.parse(text);
    if (parsed.unknownKeys.length > 0) {
      hilog.warn(DOMAIN, TAG, 'Unknown talk directive keys: %{public}s', parsed.unknownKeys.join(', '));
    }
    const directive = parsed.directive;
    const cleaned = parsed.stripped.trim();
    if (cleaned.length === 0) return;
    this._lastAssistantText = cleaned;

    // Apply voice overrides
    if (directive?.voiceId) {
      const resolved = this.resolveVoiceAlias(directive.voiceId);
      if (resolved) {
        if (directive.once !== true) {
          this.currentVoiceId = resolved;
          this.voiceOverrideActive = true;
        }
      }
    }
    if (directive?.modelId) {
      if (directive.once !== true) {
        this.currentModelId = directive.modelId;
        this.modelOverrideActive = true;
      }
    }

    this._statusText = 'Speaking…';
    this._isSpeaking = true;
    this.lastSpokenText = cleaned;
    this.notifyStateChange();

    try {
      const voiceId = this.currentVoiceId || this.defaultVoiceId;
      const canUseElevenLabs = voiceId && voiceId.length > 0 &&
        this.apiKey && this.apiKey.length > 0;

      if (!canUseElevenLabs) {
        hilog.warn(DOMAIN, TAG, 'No ElevenLabs config; using system TTS placeholder');
        this._usingFallbackTts = true;
        this._statusText = 'Speaking (System)…';
        this.notifyStateChange();
        // System TTS fallback — placeholder for HarmonyOS TTS integration
        await this.speakWithSystemTts(cleaned);
      } else {
        this._usingFallbackTts = false;
        const modelId = directive?.modelId || this.currentModelId || this.defaultModelId || DEFAULT_MODEL_ID;
        const outputFormat = directive?.outputFormat || this.defaultOutputFormat || DEFAULT_OUTPUT_FORMAT;
        await this.streamElevenLabs(voiceId!, this.apiKey!, cleaned, modelId, outputFormat, directive);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'speak failed: %{public}s', String(err));
      try {
        this._usingFallbackTts = true;
        this._statusText = 'Speaking (System)…';
        this.notifyStateChange();
        await this.speakWithSystemTts(cleaned);
      } catch (fallbackErr) {
        this._statusText = `Speak failed: ${fallbackErr instanceof Error ? fallbackErr.message : String(fallbackErr)}`;
      }
    }

    this._isSpeaking = false;
    this.notifyStateChange();
  }

  private async streamElevenLabs(
    voiceId: string, apiKey: string, text: string,
    modelId: string, outputFormat: string,
    directive: TalkDirective | undefined
  ): Promise<void> {
    const url = `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}/stream`;
    const payload: Record<string, Object> = {
      'text': text,
      'model_id': modelId,
      'output_format': outputFormat,
    };

    const voiceSettings: Record<string, Object> = {};
    if (directive?.speed !== undefined) voiceSettings['speed'] = directive.speed;
    if (directive?.stability !== undefined) voiceSettings['stability'] = directive.stability;
    if (directive?.similarity !== undefined) voiceSettings['similarity_boost'] = directive.similarity;
    if (directive?.style !== undefined) voiceSettings['style'] = directive.style;
    if (directive?.speakerBoost !== undefined) voiceSettings['use_speaker_boost'] = directive.speakerBoost;
    if (Object.keys(voiceSettings).length > 0) {
      payload['voice_settings'] = voiceSettings;
    }
    if (directive?.seed !== undefined) payload['seed'] = directive.seed;
    if (directive?.normalize) payload['apply_text_normalization'] = directive.normalize;
    if (directive?.language) payload['language_code'] = directive.language;

    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Accept': outputFormat.startsWith('pcm_') ? 'audio/pcm' : 'audio/mpeg',
          'xi-api-key': apiKey,
        },
        extraData: JSON.stringify(payload),
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 30000,
        readTimeout: 30000,
      });

      if (response.responseCode >= 400) {
        throw new Error(`ElevenLabs failed: ${response.responseCode}`);
      }

      // Audio data received — play it
      // HarmonyOS audio playback integration point
      hilog.info(DOMAIN, TAG, 'ElevenLabs stream received, data type: %{public}s',
        typeof response.result);
      // TODO: Wire to AudioRenderer for actual playback
    } finally {
      httpRequest.destroy();
    }
  }

  private async speakWithSystemTts(text: string): Promise<void> {
    // HarmonyOS system TTS integration point
    // Can use @ohos.multimedia.audio or textToSpeech when available
    hilog.info(DOMAIN, TAG, 'System TTS placeholder for: %{public}s',
      text.length > 50 ? text.substring(0, 50) + '…' : text);
    // Simulate speaking duration based on word count
    const wordCount = text.split(/\s+/).length;
    const durationMs = Math.min(wordCount * 200, 10000);
    await this.delay(durationMs);
  }

  private shouldInterrupt(transcript: string): boolean {
    const trimmed = transcript.trim();
    if (trimmed.length < 3) return false;
    const spoken = this.lastSpokenText?.toLowerCase();
    if (spoken && spoken.indexOf(trimmed.toLowerCase()) >= 0) return false;
    return true;
  }

  private stopSpeaking(): void {
    this._isSpeaking = false;
    this.notifyStateChange();
  }

  private async reloadConfig(): Promise<void> {
    try {
      const params: Record<string, Object> = { 'includeSecrets': true };
      const res = await this.session.request('talk.config', params);
      const payload = res.payload as Record<string, Object> || (res.payloadJSON ? JSON.parse(res.payloadJSON) as Record<string, Object> : undefined);
      if (!payload) return;
      
      const config = payload['config'] as Record<string, Object> | undefined;
      const talk = config?.['talk'] as Record<string, Object> | undefined;
      const sessionCfg = config?.['session'] as Record<string, Object> | undefined;

      const mainKey = (sessionCfg?.['mainKey'] as string | undefined || '').trim();
      if (mainKey.length > 0) {
        this.mainSessionKey = mainKey;
      }

      const voice = (talk?.['voiceId'] as string | undefined || '').trim();
      if (voice.length > 0) this.defaultVoiceId = voice;

      const model = (talk?.['modelId'] as string | undefined || '').trim();
      this.defaultModelId = model.length > 0 ? model : DEFAULT_MODEL_ID;
      if (!this.modelOverrideActive) this.currentModelId = this.defaultModelId;

      const format = (talk?.['outputFormat'] as string | undefined || '').trim();
      this.defaultOutputFormat = format.length > 0 ? format : DEFAULT_OUTPUT_FORMAT;

      const key = (talk?.['apiKey'] as string | undefined || '').trim();
      if (key.length > 0) this.apiKey = key;

      const interrupt = talk?.['interruptOnSpeech'];
      if (typeof interrupt === 'boolean') this.interruptOnSpeech = interrupt as boolean;

      // Parse voice aliases
      const aliases = talk?.['voiceAliases'] as Record<string, Object> | undefined;
      this.voiceAliases.clear();
      if (aliases) {
        for (const aliasKey of Object.keys(aliases)) {
          const id = (aliases[aliasKey] as string || '').trim();
          if (id.length > 0) {
            this.voiceAliases.set(aliasKey.trim().toLowerCase(), id);
          }
        }
      }

      if (!this.voiceOverrideActive) {
        this.currentVoiceId = this.defaultVoiceId;
      }
    } catch (_e) {
      this.defaultModelId = DEFAULT_MODEL_ID;
      if (!this.modelOverrideActive) this.currentModelId = this.defaultModelId;
      this.defaultOutputFormat = DEFAULT_OUTPUT_FORMAT;
    }
  }

  private resolveVoiceAlias(voiceId: string | undefined): string | undefined {
    if (!voiceId) return undefined;
    const key = voiceId.trim().toLowerCase();
    return this.voiceAliases.get(key) || voiceId;
  }

  private parseRunIdFromObj(res: Object): string | undefined {
    // If res is RpcResponse
    const anyRes = res as Record<string, Object>;
    const payload = anyRes['payload'] as Record<string, Object> || 
                   (anyRes['payloadJSON'] ? JSON.parse(anyRes['payloadJSON'] as string) as Record<string, Object> : undefined);
    
    if (payload) {
      const runId = payload['runId'] as string | undefined;
      if (runId) {
        this.pendingRunId = runId;
        return runId;
      }
    }
    return undefined;
  }

  private cancelRestart(): void {
    if (this.restartTimerId >= 0) {
      clearTimeout(this.restartTimerId);
      this.restartTimerId = -1;
    }
  }

  private notifyStateChange(): void {
    if (this.onStateChange) {
      this.onStateChange();
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  private generateUuid(): string {
    return util.generateRandomUUID(true);
  }
}
