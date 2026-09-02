/**
 * channel_store — wechat channel binding state (hiclaw-compatible) and
 * ilink QR-code proxy for the dsh bonio-bridge gateway.
 *
 * State is persisted in <home>/.bonio/hiclaw.json under the 'wechat' key,
 * matching the hiclaw server config format so the bridge and hiclaw can
 * share the same on-device configuration.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

export interface ChannelConfig {
  enabled: boolean;
  mode: string;
  wecomBotId: string;
}

export interface WechatBinding {
  enabled: boolean;
  mode: string;
  token: string;
  baseUrl: string;
  allowFrom: string[];
}

function home(): string {
  const h = process.env.DSH_HOME || process.env.HOME || os.homedir();
  return h === '/root' ? '/data/local/home' : h;
}

function configPath(): string {
  return path.join(home(), '.bonio', 'hiclaw.json');
}

type JsonObject = Record<string, unknown>;

async function loadConfig(): Promise<JsonObject> {
  try {
    const raw = await fs.readFile(configPath(), 'utf8');
    const parsed = JSON.parse(raw) as JsonObject;
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

async function saveConfig(config: JsonObject): Promise<void> {
  const dir = path.dirname(configPath());
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(configPath(), JSON.stringify(config, null, 2), 'utf8');
}

function wechatBlock(config: JsonObject): JsonObject | null {
  const wc = config['wechat'];
  return wc && typeof wc === 'object' ? (wc as JsonObject) : null;
}

function str(v: unknown, fallback = ''): string {
  return typeof v === 'string' ? v : fallback;
}

export async function getChannelConfig(): Promise<ChannelConfig> {
  const config = await loadConfig();
  const wc = wechatBlock(config);
  return {
    enabled: wc?.['enabled'] === true,
    mode: str(wc?.['mode']),
    wecomBotId: str((wc?.['wecom'] as JsonObject | undefined)?.['bot_id']),
  };
}

export async function getWechatBinding(): Promise<WechatBinding> {
  const config = await loadConfig();
  const wc = wechatBlock(config);
  const wx = (wc?.['weixin'] as JsonObject | undefined) ?? {};
  const allow = wc?.['allow_from'];
  return {
    enabled: wc?.['enabled'] === true,
    mode: str(wc?.['mode']),
    token: str(wx['token']),
    baseUrl: str(wx['base_url'], 'https://ilinkai.weixin.qq.com'),
    allowFrom: Array.isArray(allow) ? allow.filter((v): v is string => typeof v === 'string') : [],
  };
}

export async function setWechatBinding(binding: {
  token: string;
  baseUrl?: string;
  allowFrom?: string[];
}): Promise<{ saved: boolean }> {
  const config = await loadConfig();
  const wc = wechatBlock(config) ?? {};
  wc['enabled'] = true;
  wc['mode'] = 'weixin';
  const wx = (wc['weixin'] as JsonObject | undefined) ?? {};
  wx['token'] = binding.token;
  if (binding.baseUrl) wx['base_url'] = binding.baseUrl;
  wc['weixin'] = wx;
  if (binding.allowFrom && binding.allowFrom.length > 0) wc['allow_from'] = binding.allowFrom;
  config['wechat'] = wc;
  await saveConfig(config);
  return { saved: true };
}

export async function disableWechat(): Promise<{ saved: boolean }> {
  const config = await loadConfig();
  if (wechatBlock(config)) {
    delete config['wechat'];
    await saveConfig(config);
  }
  return { saved: true };
}

// ── ilink QR-code proxy (mirrors hiclaw gateway.cpp) ──
const ILINK_BASE = 'https://ilinkai.weixin.qq.com';

export async function fetchWechatQrCode(): Promise<{ qrcode_key: string; qrcode_img: string }> {
  const binding = await getWechatBinding();
  const body: JsonObject = {};
  if (binding.token) body['local_token_list'] = [binding.token];
  const res = await fetch(`${ILINK_BASE}/ilink/bot/get_bot_qrcode?bot_type=3`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'iLink-App-ClientVersion': '1' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error('failed to fetch QR code from ilink');
  const j = (await res.json()) as JsonObject;
  return {
    qrcode_key: str(j['qrcode']),
    qrcode_img: str(j['qrcode_img_content']),
  };
}

export async function pollWechatQrStatus(qrcodeKey: string, verifyCode?: string): Promise<{
  status: string;
  bot_token?: string;
  ilink_user_id?: string;
  baseurl?: string;
}> {
  let url = `${ILINK_BASE}/ilink/bot/get_qrcode_status?qrcode=${encodeURIComponent(qrcodeKey)}`;
  if (verifyCode) url += `&verify_code=${encodeURIComponent(verifyCode)}`;
  // ilink long-polls up to ~30s; give it 45s.
  const res = await fetch(url, {
    headers: { 'iLink-App-ClientVersion': '1' },
    signal: AbortSignal.timeout(45000),
  });
  if (!res.ok) throw new Error('failed to poll QR status');
  const j = (await res.json()) as JsonObject;
  return {
    status: str(j['status'], 'wait'),
    bot_token: typeof j['bot_token'] === 'string' ? j['bot_token'] as string : undefined,
    ilink_user_id: typeof j['ilink_user_id'] === 'string' ? j['ilink_user_id'] as string : undefined,
    baseurl: typeof j['baseurl'] === 'string' ? j['baseurl'] as string : undefined,
  };
}
