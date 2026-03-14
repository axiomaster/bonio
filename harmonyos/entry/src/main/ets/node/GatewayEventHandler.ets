import { SecurePrefs } from '../common/SecurePrefs';
import { GatewaySession } from '../gateway/GatewaySession';

export class GatewayEventHandler {
  private prefs: SecurePrefs;
  private session: GatewaySession;
  private isConnected: () => boolean;
  
  public onWakeWordsChanged: ((words: string[]) => void) | undefined = undefined;

  private suppressWakeWordsSync: boolean = false;
  private wakeWordsSyncTimer: number = -1;

  constructor(
    prefs: SecurePrefs,
    session: GatewaySession,
    isConnected: () => boolean
  ) {
    this.prefs = prefs;
    this.session = session;
    this.isConnected = isConnected;
  }

  public applyWakeWordsFromGateway(words: string[]): void {
    this.suppressWakeWordsSync = true;
    this.prefs.setWakeWords(words);
    if (this.onWakeWordsChanged) {
      this.onWakeWordsChanged(words);
    }
    this.suppressWakeWordsSync = false;
  }

  public scheduleWakeWordsSyncIfNeeded(): void {
    if (this.suppressWakeWordsSync) return;
    if (!this.isConnected()) return;

    const snapshot = this.prefs.getWakeWords();
    if (this.wakeWordsSyncTimer !== -1) {
      clearTimeout(this.wakeWordsSyncTimer);
    }
    
    this.wakeWordsSyncTimer = setTimeout(async () => {
      this.wakeWordsSyncTimer = -1;
      class VoiceWakeParams {
        triggers: string[] = [];
      }
      const paramsObj = new VoiceWakeParams();
      paramsObj.triggers = snapshot;
      try {
        await this.session.request("voicewake.set", paramsObj);
      } catch (e) {
        // ignore
        console.warn('GatewayEventHandler', `voicewake.set failed: ${e instanceof Error ? e.message : String(e)}`);
      }
    }, 650);
  }

  public async refreshWakeWordsFromGateway(): Promise<void> {
    if (!this.isConnected()) return;
    try {
      const res = await this.session.request("voicewake.get", new Object());
      const payload = res.payload as Record<string, Object> || (res.payloadJSON ? JSON.parse(res.payloadJSON) as Record<string, Object> : undefined);
      if (payload && Array.isArray(payload.triggers)) {
        const triggers: string[] = [];
        for (const item of payload.triggers as Object[]) {
          if (typeof item === 'string') triggers.push(item);
        }
        this.applyWakeWordsFromGateway(triggers);
      }
    } catch (err) {
      const e = err as Error;
      console.warn('GatewayEventHandler', `voicewake.get failed: ${e.message}`);
    }
  }

  public handleEvent(event: string, payloadJson: string | undefined): void {
    if (event === "voicewake.changed") {
      this.handleVoiceWakeChangedEvent(payloadJson);
    }
  }

  public handleVoiceWakeChangedEvent(payloadJson: string | undefined): void {
    if (!payloadJson || payloadJson.trim() === '') return;
    try {
      const payload = JSON.parse(payloadJson) as Record<string, Object>;
      if (payload && Array.isArray(payload.triggers)) {
        const triggers: string[] = [];
        for (const item of payload.triggers as Object[]) {
          if (typeof item === 'string') triggers.push(item);
        }
        this.applyWakeWordsFromGateway(triggers);
      }
    } catch (e) {
      // ignore
    }
  }
}
