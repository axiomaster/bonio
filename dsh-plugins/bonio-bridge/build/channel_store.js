/**
 * channel_store — wechat channel binding state and ilink QR-code proxy for
 * the dsh bonio-bridge gateway.
 *
 * The Bonio backend is DSH, not the hiclaw server: binding state is persisted
 * in the bridge-owned <home>/.bonio/wechat.json. A legacy hiclaw.json
 * 'wechat' block (written before the split) is imported once for migration.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
/** Resolve the on-device bonio home (~/.bonio lives under it). */
export function bonioHome() {
    const h = process.env.DSH_HOME || process.env.HOME || os.homedir();
    return h === '/root' ? '/data/local/home' : h;
}
function configPath() {
    return path.join(bonioHome(), '.bonio', 'wechat.json');
}
/** Pre-split storage; read-only, imported into wechat.json on first access. */
function legacyConfigPath() {
    return path.join(bonioHome(), '.bonio', 'hiclaw.json');
}
async function loadConfig() {
    try {
        const raw = await fs.readFile(configPath(), 'utf8');
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object' && Object.keys(parsed).length > 0)
            return parsed;
    }
    catch { /* fall through to legacy import */ }
    try {
        const legacy = JSON.parse(await fs.readFile(legacyConfigPath(), 'utf8'));
        const imported = {};
        if (legacy && typeof legacy === 'object' && legacy['wechat'] !== undefined) {
            imported['wechat'] = legacy['wechat'];
        }
        if (Object.keys(imported).length > 0)
            await saveConfig(imported);
        return imported;
    }
    catch {
        return {};
    }
}
async function saveConfig(config) {
    const dir = path.dirname(configPath());
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(configPath(), JSON.stringify(config, null, 2), 'utf8');
}
function wechatBlock(config) {
    const wc = config['wechat'];
    return wc && typeof wc === 'object' ? wc : null;
}
function str(v, fallback = '') {
    return typeof v === 'string' ? v : fallback;
}
export async function getChannelConfig() {
    const config = await loadConfig();
    const wc = wechatBlock(config);
    return {
        enabled: wc?.['enabled'] === true,
        mode: str(wc?.['mode']),
        wecomBotId: str(wc?.['wecom']?.['bot_id']),
    };
}
export async function getWechatBinding() {
    const config = await loadConfig();
    const wc = wechatBlock(config);
    const wx = wc?.['weixin'] ?? {};
    const allow = wc?.['allow_from'];
    return {
        enabled: wc?.['enabled'] === true,
        mode: str(wc?.['mode']),
        token: str(wx['token']),
        baseUrl: str(wx['base_url'], 'https://ilinkai.weixin.qq.com'),
        allowFrom: Array.isArray(allow) ? allow.filter((v) => typeof v === 'string') : [],
    };
}
export async function setWechatBinding(binding) {
    const config = await loadConfig();
    const wc = wechatBlock(config) ?? {};
    wc['enabled'] = true;
    wc['mode'] = 'weixin';
    const wx = wc['weixin'] ?? {};
    wx['token'] = binding.token;
    if (binding.baseUrl)
        wx['base_url'] = binding.baseUrl;
    wc['weixin'] = wx;
    if (binding.allowFrom && binding.allowFrom.length > 0)
        wc['allow_from'] = binding.allowFrom;
    config['wechat'] = wc;
    await saveConfig(config);
    return { saved: true };
}
export async function disableWechat() {
    const config = await loadConfig();
    if (wechatBlock(config)) {
        delete config['wechat'];
        await saveConfig(config);
    }
    return { saved: true };
}
// ── ilink QR-code proxy (mirrors hiclaw gateway.cpp) ──
const ILINK_BASE = 'https://ilinkai.weixin.qq.com';
export async function fetchWechatQrCode() {
    const binding = await getWechatBinding();
    const body = {};
    if (binding.token)
        body['local_token_list'] = [binding.token];
    const res = await fetch(`${ILINK_BASE}/ilink/bot/get_bot_qrcode?bot_type=3`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'iLink-App-ClientVersion': '1' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(15000),
    });
    if (!res.ok)
        throw new Error('failed to fetch QR code from ilink');
    const j = (await res.json());
    return {
        qrcode_key: str(j['qrcode']),
        qrcode_img: str(j['qrcode_img_content']),
    };
}
export async function pollWechatQrStatus(qrcodeKey, verifyCode) {
    let url = `${ILINK_BASE}/ilink/bot/get_qrcode_status?qrcode=${encodeURIComponent(qrcodeKey)}`;
    if (verifyCode)
        url += `&verify_code=${encodeURIComponent(verifyCode)}`;
    // ilink long-polls up to ~30s; give it 45s.
    const res = await fetch(url, {
        headers: { 'iLink-App-ClientVersion': '1' },
        signal: AbortSignal.timeout(45000),
    });
    if (!res.ok)
        throw new Error('failed to poll QR status');
    const j = (await res.json());
    return {
        status: str(j['status'], 'wait'),
        bot_token: typeof j['bot_token'] === 'string' ? j['bot_token'] : undefined,
        ilink_user_id: typeof j['ilink_user_id'] === 'string' ? j['ilink_user_id'] : undefined,
        baseurl: typeof j['baseurl'] === 'string' ? j['baseurl'] : undefined,
    };
}
