import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface RecordParams {
  durationMs?: number;
  fps?: number;
  includeAudio?: boolean;
  format?: string;
}

export interface RecordPayload {
  file: fileIo.File;
  durationMs: number;
  fps: number;
  hasAudio: boolean;
}

export class ScreenRecordManager {
  private static readonly TAG = 'ScreenRecordManager';
  private static readonly DOMAIN = 0x3D00;
  private context: common.Context;
  private screenCapture: media.AVScreenCaptureRecorder | undefined = undefined;

  constructor(context: common.Context) {
    this.context = context;
  }

  async init(): Promise<void> {
    try {
      this.screenCapture = await media.createAVScreenCaptureRecorder();
    } catch (e) {
      hilog.error(ScreenRecordManager.DOMAIN, ScreenRecordManager.TAG, "Failed to create AVScreenCaptureRecorder: %{public}s", String(e));
    }
  }

  async release(): Promise<void> {
    if (this.screenCapture) {
      await this.screenCapture.release();
      this.screenCapture = undefined;
    }
  }

  async record(paramsJson: string | undefined): Promise<RecordPayload> {
    if (!this.screenCapture) await this.init();
    if (!this.screenCapture) throw new Error("UNAVAILABLE: screenCapture not initialized");

    const params: RecordParams = paramsJson ? (JSON.parse(paramsJson) as RecordParams) : ({} as RecordParams);
    const durationMs = (params.durationMs || 3000).valueOf();
    const fps = params.fps || 15;
    const includeAudio = params.includeAudio !== false;

    // Recording to a file requires an FD
    const filePath = this.context.tempDir + '/screen_' + Date.now() + '.mp4';
    const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
    const fd = file.fd;

    // Setup configuration based on AVScreenCaptureRecordConfig
    const config: media.AVScreenCaptureRecordConfig = {
        fd: fd,
        frameWidth: 720,
        frameHeight: 1280
    };

    try {
      await this.screenCapture.init(config);
      if (includeAudio) {
        // Enforce microphone after init
        await this.screenCapture.setMicEnabled(true);
      }
      
      await this.screenCapture.startRecording();
      
      hilog.info(ScreenRecordManager.DOMAIN, ScreenRecordManager.TAG, "Screen recording started for %{public}dms", durationMs);
      
      await new Promise<void>(resolve => setTimeout(resolve, durationMs));
      
      await this.screenCapture.stopRecording();
      hilog.info(ScreenRecordManager.DOMAIN, ScreenRecordManager.TAG, "Screen recording stopped");
      
      fileIo.closeSync(file);
      const readFile = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      
      return {
        file: readFile,
        durationMs: durationMs,
        fps: fps,
        hasAudio: includeAudio
      };
    } catch (e) {
      hilog.error(ScreenRecordManager.DOMAIN, ScreenRecordManager.TAG, "Screen recording failed: %{public}s", String(e));
      fileIo.closeSync(file);
      throw new Error(String(e));
    } finally {
      await this.release();
    }
  }
}
