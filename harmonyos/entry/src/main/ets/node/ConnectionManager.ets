import {
  GatewayTlsParams,
  GatewayEndpoint,
  LocationMode,
  VoiceWakeMode,
  GatewayConnectOptions,
  GatewayClientInfo
} from '../models/CommonModels';
import { SecurePrefs } from '../common/SecurePrefs';
import {
  OpenClawCanvasCommand,
  OpenClawCanvasA2UICommand,
  OpenClawScreenCommand,
  OpenClawCameraCommand,
  OpenClawLocationCommand,
  OpenClawSmsCommand,
  OpenClawCapability
} from '../protocol/ProtocolConstants';
import { deviceInfo } from '@kit.BasicServicesKit';

export class ConnectionManager {
  private prefs: SecurePrefs;
  private cameraEnabled: () => boolean;
  private locationMode: () => LocationMode;
  private voiceWakeMode: () => VoiceWakeMode;
  private smsAvailable: () => boolean;
  private hasRecordAudioPermission: () => boolean;
  private manualTls: () => boolean;

  constructor(
    prefs: SecurePrefs,
    cameraEnabled: () => boolean,
    locationMode: () => LocationMode,
    voiceWakeMode: () => VoiceWakeMode,
    smsAvailable: () => boolean,
    hasRecordAudioPermission: () => boolean,
    manualTls: () => boolean
  ) {
    this.prefs = prefs;
    this.cameraEnabled = cameraEnabled;
    this.locationMode = locationMode;
    this.voiceWakeMode = voiceWakeMode;
    this.smsAvailable = smsAvailable;
    this.hasRecordAudioPermission = hasRecordAudioPermission;
    this.manualTls = manualTls;
  }

  public static resolveTlsParamsForEndpoint(
    endpoint: GatewayEndpoint,
    storedFingerprint: string | undefined,
    manualTlsEnabled: boolean
  ): GatewayTlsParams | undefined {
    const stableId = endpoint.stableId;
    const stored = storedFingerprint?.trim() || undefined;
    const isManual = stableId.startsWith("manual|");

    if (isManual) {
      if (!manualTlsEnabled) return undefined;
      if (stored) {
        return {
          required: true,
          expectedFingerprint: stored,
          allowTOFU: false,
          stableId: stableId,
        };
      }
      return {
        required: true,
        expectedFingerprint: undefined,
        allowTOFU: false,
        stableId: stableId,
      };
    }

    if (stored) {
      return {
        required: true,
        expectedFingerprint: stored,
        allowTOFU: false,
        stableId: stableId,
      };
    }

    const hinted = endpoint.tlsEnabled || (endpoint.tlsFingerprintSha256 && endpoint.tlsFingerprintSha256.trim().length > 0);
    if (hinted) {
      return {
        required: true,
        expectedFingerprint: undefined,
        allowTOFU: false,
        stableId: stableId,
      };
    }

    return undefined;
  }

  public buildInvokeCommands(): string[] {
    const list: string[] = [];
    list.push(OpenClawCanvasCommand.Present);
    list.push(OpenClawCanvasCommand.Hide);
    list.push(OpenClawCanvasCommand.Navigate);
    list.push(OpenClawCanvasCommand.Eval);
    list.push(OpenClawCanvasCommand.Snapshot);
    list.push(OpenClawCanvasA2UICommand.Push);
    list.push(OpenClawCanvasA2UICommand.PushJSONL);
    list.push(OpenClawCanvasA2UICommand.Reset);
    
    if (this.prefs.getScreenRecordEnabled()) {
      list.push(OpenClawScreenCommand.Record);
    }
    
    if (this.cameraEnabled()) {
      list.push(OpenClawCameraCommand.Snap);
    }
    if (this.locationMode() !== LocationMode.Off) {
      list.push(OpenClawLocationCommand.Get);
    }
    if (this.smsAvailable()) {
      list.push(OpenClawSmsCommand.Send);
    }
    
    // Add debug and app commands
    list.push("debug.logs");
    list.push("debug.ed25519");
    list.push("app.update");
    
    return list;
  }

  public buildCapabilities(): string[] {
    const list: string[] = [];
    list.push(OpenClawCapability.Canvas);
    
    if (this.prefs.getScreenRecordEnabled()) {
      list.push(OpenClawCapability.Screen);
    }
    
    if (this.cameraEnabled()) list.push(OpenClawCapability.Camera);
    if (this.smsAvailable()) list.push(OpenClawCapability.Sms);
    if (this.voiceWakeMode() !== VoiceWakeMode.Off && this.hasRecordAudioPermission()) {
      list.push(OpenClawCapability.VoiceWake);
    }
    if (this.locationMode() !== LocationMode.Off) {
      list.push(OpenClawCapability.Location);
    }
    
    return list;
  }

  public resolvedVersionName(): string {
    // TODO: Read from bundleInfo
    return "1.0.0-dev";
  }

  public resolveModelIdentifier(): string | undefined {
    return deviceInfo.productModel;
  }

  public buildUserAgent(): string {
    const version = this.resolvedVersionName();
    return `OpenClawNode/${version} (Android)`;
  }

  public buildClientInfo(clientId: string, clientMode: string): GatewayClientInfo {
    return {
      id: clientId,
      displayName: this.prefs.getDisplayName(),
      version: this.resolvedVersionName(),
      platform: "android", // Mimic Android to bypass server-side origin checks for now
      mode: clientMode,
      instanceId: this.prefs.getInstanceId(),
      deviceFamily: "HarmonyOS",
      modelIdentifier: this.resolveModelIdentifier() || undefined,
    } as GatewayClientInfo;
  }

  public buildNodeConnectOptions(): GatewayConnectOptions {
    return {
      role: "node",
      scopes: [],
      caps: this.buildCapabilities(),
      commands: this.buildInvokeCommands(),
      permissions: {},
      client: this.buildClientInfo("openclaw-android", "node"),
      userAgent: this.buildUserAgent(),
    };
  }

  public buildOperatorConnectOptions(): GatewayConnectOptions {
    return {
      role: "operator",
      scopes: ["operator.read", "operator.write", "operator.talk.secrets"],
      caps: [],
      commands: [],
      permissions: {},
      client: this.buildClientInfo("openclaw-android", "ui"), // Spoof Android identity to bypass origin checks
      userAgent: this.buildUserAgent(),
    };
  }
}
