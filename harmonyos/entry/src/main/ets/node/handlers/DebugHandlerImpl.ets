import { DeviceIdentityStore } from '../../common/DeviceIdentityStore';
import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { DebugHandler } from '../InvokeDispatcher';
import { common } from '@kit.AbilityKit';

export class DebugHandlerImpl implements DebugHandler {
  private context: common.Context;
  private identityStore: DeviceIdentityStore;

  constructor(context: common.Context, identityStore: DeviceIdentityStore) {
    this.context = context;
    this.identityStore = identityStore;
  }

  async handleEd25519(): Promise<InvokeResult> {
    try {
      const identity = await this.identityStore.loadOrCreate();
      const testPayload = `test|${identity.deviceId}|${Date.now()}`;
      const results: string[] = [];
      results.push(`deviceId: ${identity.deviceId}`);
      results.push(`publicKeyRawBase64: ${identity.publicKeyRawBase64.substring(0, 20)}...`);
      results.push(`privateKeyPkcs8Base64: ${identity.privateKeyPkcs8Base64.substring(0, 20)}...`);

      const pubKeyUrl = this.identityStore.publicKeyBase64Url(identity);
      results.push(`publicKeyBase64Url: ${pubKeyUrl ?? "NULL (FAILED)"}`);

      const signature = await this.identityStore.signPayload(testPayload, identity);
      results.push(`signPayload: ${signature ? `${signature.substring(0, 20)}... (OK)` : "NULL (FAILED)"}`);

      const resultPayload = JSON.stringify({ diagnostics: results.join("\n") });
      return { ok: true, payloadJson: resultPayload };
    } catch (e) {
      const err: InvokeError = { code: "ED25519_TEST_FAILED", message: `${e instanceof Error ? e.message : String(e)}` };
      return { ok: false, error: err };
    }
  }

  async handleLogs(): Promise<InvokeResult> {
    // HarmonyOS does not easily allow background logcat grabbing via child process like Android.
    // For now, return basic memory diagnostic info.
    const info = `HarmonyOS Node\nMemory diagnostics not yet available.`;
    const resultPayload = JSON.stringify({ logs: info });
    return { ok: true, payloadJson: resultPayload };
  }
}
