
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { huks } from '@kit.UniversalKeystoreKit';

const HUKS_KEY_ALIAS = 'openclaw_node_identity';

export interface DeviceIdentity {
  deviceId: string;
  publicKeyRawBase64: string;
  privateKeyPkcs8Base64: string;
  createdAtMs: number;
}

export class DeviceIdentityStore {
  private context: common.Context;
  private identityPath: string;
  private base64 = new util.Base64Helper();
  private encoder = util.TextEncoder.create('utf-8');

  constructor(context: common.Context) {
    this.context = context;
    this.identityPath = this.context.filesDir + '/openclaw/identity/device.json';
  }

  public async loadOrCreate(): Promise<DeviceIdentity> {
    const existing = await this.load();
    if (existing) {
      return existing;
    }
    const fresh = await this.generate();
    await this.save(fresh);
    return fresh;
  }

  public async signPayload(payload: string, identity: DeviceIdentity): Promise<string | undefined> {
    try {
      if (identity.privateKeyPkcs8Base64 !== 'HUKS_STORED') {
        throw new Error('Legacy plain-text key cannot be used. Key has been discarded.');
      }

      const properties: Array<huks.HuksParam> = [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ED25519 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN },
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
      ];
      const options: huks.HuksOptions = { properties: properties };

      await huks.hasKeyItem(HUKS_KEY_ALIAS, options); // Ensure key exists
      const handle = await huks.initSession(HUKS_KEY_ALIAS, options);

      const payloadData = this.encoder.encode(payload);
      const finishOptions: huks.HuksOptions = {
        inData: payloadData,
        properties: properties
      };
      
      const signatureResult = await huks.finishSession(handle.handle, finishOptions);
      if (!signatureResult.outData) {
        throw new Error('Signature outData is undefined');
      }
      return this.base64UrlEncode(signatureResult.outData);
    } catch (e) {
      console.error('DeviceIdentityStore', `signPayload FAILED: ${e instanceof Error ? e.message : String(e)}`);
      return undefined;
    }
  }

  public publicKeyBase64Url(identity: DeviceIdentity): string | undefined {
    try {
      const raw = this.base64.decodeSync(identity.publicKeyRawBase64);
      return this.base64UrlEncode(raw);
    } catch (e) {
      return undefined;
    }
  }

  private async load(): Promise<DeviceIdentity | undefined> {
    try {
      if (!fs.accessSync(this.identityPath)) return undefined;
      const contentStr = fs.readTextSync(this.identityPath);
      if (!contentStr) return undefined;

      const decoded = JSON.parse(contentStr) as DeviceIdentity;
      if (!decoded.deviceId || !decoded.publicKeyRawBase64 || !decoded.privateKeyPkcs8Base64) {
        return undefined;
      }
      
      if (decoded.privateKeyPkcs8Base64 !== 'HUKS_STORED') {
        console.warn('DeviceIdentityStore', 'Legacy key found, discarding to force HUKS generation');
        try { fs.unlinkSync(this.identityPath); } catch (e) {}
        return undefined;
      }

      const exist = await huks.hasKeyItem(HUKS_KEY_ALIAS, { properties: [] });
      if (!exist) {
        console.warn('DeviceIdentityStore', 'Key not found in HUKS, discarding cache');
        return undefined;
      }

      return decoded;
    } catch (e) {
      console.error('DeviceIdentityStore', `load FAILED: ${e instanceof Error ? e.message : String(e)}`);
      return undefined;
    }
  }

  private async save(identity: DeviceIdentity): Promise<void> {
    try {
      const dir = this.identityPath.substring(0, this.identityPath.lastIndexOf('/'));
      if (!fs.accessSync(dir)) {
        this.mkdirRecursive(dir);
      }
      const encoded = JSON.stringify(identity);
      let file = fs.openSync(this.identityPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, encoded);
      fs.closeSync(file);
    } catch (e) {
      console.error('DeviceIdentityStore', `save FAILED: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  private async generate(): Promise<DeviceIdentity> {
    const properties: Array<huks.HuksParam> = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_ED25519 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_SIGN | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_VERIFY },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: 256 },
      { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE },
    ];
    const options: huks.HuksOptions = { properties: properties };

    try {
      try {
        await huks.deleteKeyItem(HUKS_KEY_ALIAS, options);
      } catch (e) { }
      
      await huks.generateKeyItem(HUKS_KEY_ALIAS, options);
      const pubKeyItem = await huks.exportKeyItem(HUKS_KEY_ALIAS, options);
      
      let rawPublicBytes = pubKeyItem.outData;
      if (!rawPublicBytes) {
        throw new Error('Exported public key data is undefined');
      }
      
      if (rawPublicBytes.length === 44) {
        rawPublicBytes = rawPublicBytes.subarray(12);
      } else if (rawPublicBytes.length > 32) {
        rawPublicBytes = rawPublicBytes.subarray(rawPublicBytes.length - 32);
      }
      
      const deviceId = await this.sha256Hex(rawPublicBytes);
      
      return {
        deviceId: deviceId,
        publicKeyRawBase64: this.base64.encodeToStringSync(rawPublicBytes),
        privateKeyPkcs8Base64: 'HUKS_STORED',
        createdAtMs: Date.now()
      };
    } catch (e) {
      throw new Error(`Failed to generate identity in HUKS: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  private async sha256Hex(data: Uint8Array): Promise<string> {
    try {
      const md = cryptoFramework.createMd('SHA256');
      await md.update({ data: data });
      const digest = await md.digest();
      let hex = '';
      for (let i = 0; i < digest.data.length; i++) {
          const h = digest.data[i].toString(16);
          hex += h.length === 1 ? '0' + h : h;
      }
      return hex;
    } catch (e) {
      return '';
    }
  }

  private base64UrlEncode(data: Uint8Array): string {
    const str = this.base64.encodeToStringSync(data);
    return str.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  private mkdirRecursive(path: string): void {
    if (fs.accessSync(path)) return;
    const parent = path.substring(0, path.lastIndexOf('/'));
    if (parent && !fs.accessSync(parent)) {
      this.mkdirRecursive(parent);
    }
    fs.mkdirSync(path);
  }
}
