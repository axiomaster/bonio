import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { CameraHandler } from '../InvokeDispatcher';
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { CameraCaptureManager, ClipPayload } from '../CameraCaptureManager';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

interface CameraClipPayload {
  format: string;
  base64: string;
  durationMs: number;
  hasAudio: boolean;
}

export class CameraHandlerImpl implements CameraHandler {
  private context: common.Context;
  private cameraManager: CameraCaptureManager;

  constructor(context: common.Context) {
    this.context = context;
    this.cameraManager = new CameraCaptureManager(context);
  }
  
  private base64 = new util.Base64Helper();

  async handleSnap(paramsJson: string | undefined): Promise<InvokeResult> {
    try {
      await this.ensureCameraPermission();

      const payloadJson = await this.cameraManager.snap(paramsJson);

      return { ok: true, payloadJson: payloadJson };
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      console.error('CameraHandlerImpl', `handleSnap failed: ${errorMsg}`);
      return this.makeError("CAMERA_SNAP_FAILED", errorMsg);
    }
  }

  async handleClip(paramsJson: string | undefined): Promise<InvokeResult> {
    let tempFile: fileIo.File | undefined = undefined;

    try {
      await this.ensureCameraPermission();

      const params: Record<string, string | number | boolean | null> = paramsJson ? (JSON.parse(paramsJson) as Record<string, string | number | boolean | null>) : ({} as Record<string, string | number | boolean | null>);
      const includeAudio = (params['includeAudio'] as boolean | undefined) !== false;

      if (includeAudio) {
        await this.ensureMicPermission();
      }

      const result = await this.cameraManager.clip(paramsJson);
      tempFile = result.file;

      const bytes = await this.readFile(tempFile);
      const base64 = this.base64.encodeToStringSync(new Uint8Array(bytes));

      await fileIo.unlink(tempFile.path);

      const payload: CameraClipPayload = {
        format: 'mp4',
        base64: base64,
        durationMs: result.durationMs,
        hasAudio: result.hasAudio
      };

      return { ok: true, payloadJson: JSON.stringify(payload) };
    } catch (e) {
      const errorMsg = e instanceof Error ? e.message : String(e);
      console.error('CameraHandlerImpl', `handleClip failed: ${errorMsg}`);

      if (tempFile) {
        try {
          await fileIo.unlink(tempFile.path);
        } catch (cleanupErr) {
          console.warn('CameraHandlerImpl', `Failed to cleanup temp file: ${cleanupErr}`);
        }
      }

      return this.makeError("CAMERA_CLIP_FAILED", errorMsg);
    }
  }

  private async ensureCameraPermission(): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenID = this.context.applicationInfo.accessTokenId;
    const status = await atManager.checkAccessToken(tokenID, "ohos.permission.CAMERA");

    if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      throw new Error("CAMERA_PERMISSION_REQUIRED: ohos.permission.CAMERA not granted");
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
