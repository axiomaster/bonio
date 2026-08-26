
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { LocationMode, locationModeFromRaw, VoiceWakeMode, voiceWakeModeFromRaw } from '../models/CommonModels';
import { deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

export class SecurePrefs {
  private static instance: SecurePrefs | undefined = undefined;
  private pref: preferences.Preferences | undefined = undefined;
  
  public static readonly DEFAULT_WAKE_WORDS = ['openclaw', 'claude'];
  
  private constructor() {}
  
  public static getInstance(): SecurePrefs {
    if (!SecurePrefs.instance) {
      SecurePrefs.instance = new SecurePrefs();
    }
    return SecurePrefs.instance;
  }
  
  public async init(context: common.Context): Promise<void> {
    try {
      this.pref = await preferences.getPreferences(context, 'openclaw_node_prefs');
    } catch (e) {
      console.error('SecurePrefs', `init FAILED: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  
  private checkInited() {
    if (!this.pref) {
      throw new Error('SecurePrefs not initialized');
    }
  }

  private getSyncValue<T>(key: string, defaultValue: T): T {
    this.checkInited();
    try {
      return this.pref!.getSync(key, defaultValue as preferences.ValueType) as T;
    } catch (e) {
      return defaultValue;
    }
  }

  private putSyncValue(key: string, value: preferences.ValueType): void {
    this.checkInited();
    try {
      this.pref!.putSync(key, value);
      this.pref!.flush();
    } catch (e) {
      // Ignore or log
    }
  }

  public getInstanceId(): string {
    let id = this.getSyncValue('node.instanceId', '');
    if (!id) {
      id = this.generateUUID();
      this.putSyncValue('node.instanceId', id);
    }
    return id;
  }

  public getDisplayName(): string {
    return this.getSyncValue('node.displayName', `${deviceInfo.marketName || deviceInfo.productModel || 'HarmonyOS Node'}`);
  }

  public setDisplayName(value: string): void {
    this.putSyncValue('node.displayName', value);
  }

  public getCameraEnabled(): boolean {
    return this.getSyncValue('camera.enabled', true);
  }

  public setCameraEnabled(value: boolean): void {
    this.putSyncValue('camera.enabled', value);
  }

  public getScreenRecordEnabled(): boolean {
    return this.getSyncValue('screenRecord.enabled', true);
  }

  public setScreenRecordEnabled(value: boolean): void {
    this.putSyncValue('screenRecord.enabled', value);
  }

  public getLocationMode(): LocationMode {
    const raw = this.getSyncValue('location.enabledMode', 'off');
    return locationModeFromRaw(raw);
  }

  public setLocationMode(mode: LocationMode): void {
    this.putSyncValue('location.enabledMode', mode as string);
  }

  public getManualEnabled(): boolean {
    // DSH refactor: on-device gateway is on by default.
    return this.getSyncValue('gateway.manual.enabled', true);
  }

  public setManualEnabled(value: boolean): void {
    this.putSyncValue('gateway.manual.enabled', value);
  }

  public getManualHost(): string {
    // DSH refactor: default to the on-device dsh bonio-bridge (localhost).
    return this.getSyncValue('gateway.manual.host', '127.0.0.1');
  }

  public setManualHost(value: string): void {
    this.putSyncValue('gateway.manual.host', value);
  }

  public getManualPort(): number {
    // DSH refactor: bonio-bridge listens on hiclaw-compatible port 10724.
    return this.getSyncValue('gateway.manual.port', 10724);
  }

  public setManualPort(value: number): void {
    this.putSyncValue('gateway.manual.port', value);
  }

  public getManualTls(): boolean {
    return this.getSyncValue('gateway.manual.tls', false);
  }

  public setManualTls(value: boolean): void {
    this.putSyncValue('gateway.manual.tls', value);
  }

  public getGatewayToken(): string {
    // DSH refactor: default token matches the bridge profile's default.
    return this.getSyncValue('gateway.manual.token', 'bonio-local-token');
  }

  public setGatewayToken(value: string): void {
    this.putSyncValue('gateway.manual.token', value);
  }

  public getWakeWords(): string[] {
    const raw = this.getSyncValue('voiceWake.triggerWords', JSON.stringify(SecurePrefs.DEFAULT_WAKE_WORDS));
    try {
      return JSON.parse(raw) as string[];
    } catch (e) {
      return SecurePrefs.DEFAULT_WAKE_WORDS;
    }
  }

  public setWakeWords(words: string[]): void {
    this.putSyncValue('voiceWake.triggerWords', JSON.stringify(words));
  }

  public getVoiceWakeMode(): VoiceWakeMode {
    const raw = this.getSyncValue('voiceWake.mode', 'foreground');
    return voiceWakeModeFromRaw(raw);
  }

  public setVoiceWakeMode(mode: VoiceWakeMode): void {
    this.putSyncValue('voiceWake.mode', mode as string);
  }

  private generateUUID(): string {
    return util.generateRandomUUID(true);
  }
}
