import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { ScreenHandler } from '../InvokeDispatcher';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { ScreenRecordManager, RecordPayload } from '../ScreenRecordManager';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

interface ScreenRecordPayload {
  format: string;
  base64: string;
  durationMs: number;
  fps: number;
  screenIndex: number;
  hasAudio: boolean;
}

export class ScreenHandlerImpl implements ScreenHandler {
  private context: common.Context;
  private screenManager: ScreenRecordManager;

  constructor(context: common.Context) {
    this.context = context;
    this.screenManager = new ScreenRecordManager(context);
  }

  private base64 = new util.Base64Helper();

  async handleScreenRecord(paramsJson: string | undefined): Promise<InvokeResult> {
    let tempFile: fileIo.File | undefined = undefined;

    try {
      const params: Record<string, string | number | boolean | null> = paramsJson ? (JSON.parse(paramsJson) as Record<string, string | number | boolean | null>) : ({} as Record<string, string | number | boolean | null>);
      const includeAudio = (params['includeAudio'] as boolean | undefined) !== false;

      if (includeAudio) {
        await this.ensureMicPermission();
      }

      const result = await this.screenManager.record(paramsJson);
      tempFile = result.file;

      const bytes = await this.readFile(tempFile);
      const base64 = this.base64.encodeToStringSync(new Uint8Array(bytes));

      await fileIo.unlink(tempFile.path);

      const payload: ScreenRecordPayload = {
        format: 'mp4',
        base64: base64,
        durationMs: result.durationMs,
        fps: result.fps,
        screenIndex: 0,
        hasAudio: result.hasAudio
      };

      return { ok: true, payloadJson: JSON.stringify(payload) };
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      console.error('ScreenHandlerImpl', `handleScreenRecord failed: ${errorMsg}`);

      if (tempFile) {
        try {
          await fileIo.unlink(tempFile.path);
        } catch (cleanupErr) {
          console.warn('ScreenHandlerImpl', `Failed to cleanup temp file: ${cleanupErr}`);
        }
      }

      return this.makeError("SCREEN_RECORD_FAILED", errorMsg);
    }
  }

  private async ensureMicPermission(): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenID = this.context.applicationInfo.accessTokenId;
    const status = await atManager.checkAccessToken(tokenID, "ohos.permission.MICROPHONE");

    if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      throw new Error("MIC_PERMISSION_REQUIRED: ohos.permission.MICROPHONE not granted");
    }
  }

  private async readFile(file: fileIo.File): Promise<ArrayBuffer> {
    const stat = await fileIo.stat(file.path);
    const buffer = new ArrayBuffer(stat.size);
    await fileIo.read(file.fd, buffer);
    return buffer;
  }

  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    return this.base64.encodeToStringSync(new Uint8Array(buffer));
  }

  private makeError(code: string, message: string): InvokeResult {
    const err: InvokeError = { code: code, message: message };
    return { ok: false, error: err };
  }
}
