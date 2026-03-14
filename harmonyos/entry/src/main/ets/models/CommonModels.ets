
export enum LocationMode {
  Off = 'off',
  WhileUsing = 'whileUsing',
  Always = 'always',
}

export function locationModeFromRaw(raw: string | undefined): LocationMode {
  if (!raw) return LocationMode.Off;
  const normalized = raw.trim().toLowerCase();
  if (normalized === LocationMode.WhileUsing.toLowerCase()) return LocationMode.WhileUsing;
  if (normalized === LocationMode.Always.toLowerCase()) return LocationMode.Always;
  return LocationMode.Off;
}

export enum VoiceWakeMode {
  Off = 'off',
  Foreground = 'foreground',
  Always = 'always',
}

export function voiceWakeModeFromRaw(raw: string | undefined): VoiceWakeMode {
  if (!raw) return VoiceWakeMode.Foreground;
  const normalized = raw.trim().toLowerCase();
  if (normalized === VoiceWakeMode.Off.toLowerCase()) return VoiceWakeMode.Off;
  if (normalized === VoiceWakeMode.Always.toLowerCase()) return VoiceWakeMode.Always;
  return VoiceWakeMode.Foreground;
}

export interface GatewayEndpoint {
  stableId: string;
  name: string;
  host: string;
  port: number;
  lanHost?: string;
  tailnetDns?: string;
  gatewayPort?: number;
  canvasPort?: number;
  tlsEnabled: boolean;
  tlsFingerprintSha256?: string;
}

export interface GatewayTlsParams {
  required: boolean;
  expectedFingerprint: string | undefined;
  allowTOFU: boolean;
  stableId: string;
}


export function createManualEndpoint(host: string, port: number): GatewayEndpoint {
  return {
    stableId: `manual|${host.toLowerCase()}|${port}`,
    name: `${host}:${port}`,
    host: host,
    port: port,
    tlsEnabled: false
  };
}

export interface GatewayClientInfo {
  id: string;
  displayName?: string;
  version: string;
  platform: string;
  mode: string;
  instanceId?: string;
  deviceFamily?: string;
  modelIdentifier?: string;
}

export interface GatewayConnectOptions {
  role: string;
  scopes: string[];
  caps: string[];
  commands: string[];
  permissions: Record<string, boolean>;
  client: GatewayClientInfo;
  userAgent?: string;
}
