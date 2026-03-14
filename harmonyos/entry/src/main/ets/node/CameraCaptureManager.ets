import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface SnapParams {
  facing?: string;
  quality?: number;
  maxWidth?: number;
}

export interface ClipParams {
  facing?: string;
  durationMs?: number;
  includeAudio?: boolean;
}

export interface SnapPayload {
  format: string;
  base64: string;
  width: number;
  height: number;
}

export interface ClipPayload {
  file: fileIo.File;
  durationMs: number;
  hasAudio: boolean;
}

export class CameraCaptureManager {
  private static readonly TAG = 'CameraCaptureManager';
  private static readonly DOMAIN = 0x3D00;
  private context: common.Context;
  private camManager: camera.CameraManager | undefined = undefined;

  constructor(context: common.Context) {
    this.context = context;
  }

  async init(): Promise<void> {
    try {
      this.camManager = camera.getCameraManager(this.context);
    } catch (e) {
      hilog.error(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "Failed to get CameraManager: %{public}s", String(e));
    }
  }

  async release(): Promise<void> {
    // Session management should be handled per-capture to avoid locking resources
  }

  async snap(paramsJson: string | undefined): Promise<string> {
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "snap started with params: %{public}s", paramsJson || "none");
    if (!this.camManager) await this.init();
    if (!this.camManager) throw new Error("UNAVAILABLE: camManager not initialized");

    const params: SnapParams = paramsJson ? (JSON.parse(paramsJson) as SnapParams) : ({} as SnapParams);
    const facing = params.facing === 'back' ? camera.CameraPosition.CAMERA_POSITION_BACK : camera.CameraPosition.CAMERA_POSITION_FRONT;

    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "selecting camera for facing: %{public}d", facing);
    const cameras = this.camManager.getSupportedCameras();
    const targetCamera = cameras.find((c: camera.CameraDevice) => c.cameraPosition === facing) || cameras[0];
    if (!targetCamera) throw new Error("UNAVAILABLE: no camera found");
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "target camera: %{public}s", targetCamera.cameraId);

    // 1. Create Input
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "creating camera input...");
    const camInput = this.camManager.createCameraInput(targetCamera);
    await camInput.open();
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "camera input opened");

    // 2. Create Photo Output
    const photoProfiles = this.camManager.getSupportedOutputCapability(targetCamera, camera.SceneMode.NORMAL_PHOTO);
    const profile = photoProfiles.photoProfiles[0]; // Just take first profile for now
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "creating photo output with size: %{public}dx%{public}d", profile.size.width, profile.size.height);
    
    // Creating photo output linked to the file or receiver
    const photoOutput = this.camManager.createPhotoOutput(profile);
    
    // 3. Create Session
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "creating camera session...");
    const photoSession = this.camManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
    photoSession.beginConfig();
    photoSession.addInput(camInput);
    photoSession.addOutput(photoOutput);
    await photoSession.commitConfig();
    await photoSession.start();
    hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "camera session started");

    // 4. Capture with Timeout
    return new Promise<string>((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        hilog.error(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "Capture timed out after 10s");
        photoSession.stop().then(() => photoSession.release());
        camInput.close();
        reject(new Error("Capture timed out"));
      }, 10000);

      photoOutput.on('photoAvailable', (err: Error, photo: camera.Photo) => {
        clearTimeout(timeoutId);
        hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "photoAvailable callback triggered, err: %{public}s", String(err));
        
        if (err || !photo) {
          photoSession.stop().then(() => photoSession.release());
          camInput.close();
          reject(new Error("Capture failed: " + JSON.stringify(err)));
          return;
        }

        const imagePacker = image.createImagePacker();
        const img = photo.main;
        hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "processing main image...");
        
        img.getComponent(image.ComponentType.JPEG).then((component: image.Component) => {
          hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "got JPEG component, buffer size: %{public}d", component.byteBuffer.byteLength);
          const buffer = component.byteBuffer;
          const imageSource = image.createImageSource(buffer);
          
          return imagePacker.packing(imageSource, { format: 'image/jpeg', quality: (params.quality || 0.5) * 100 });
        }).then((data: ArrayBuffer) => {
            hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "image packing completed, size: %{public}d", data.byteLength);
            const base64 = new util.Base64Helper().encodeToStringSync(new Uint8Array(data));
            const result: SnapPayload = {
              format: 'jpg',
              base64: base64,
              width: profile.size.width,
              height: profile.size.height
            };
            
            photoSession.stop().then(() => photoSession.release());
            camInput.close();
            img.release();
            hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "snap successful, resolving payload");
            resolve(JSON.stringify(result));
        }).catch((e: Error) => {
            hilog.error(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "Processing failed: %{public}s", String(e));
            photoSession.stop().then(() => photoSession.release());
            camInput.close();
            img.release();
            reject(new Error(String(e)));
        });
      });
      
      hilog.info(CameraCaptureManager.DOMAIN, CameraCaptureManager.TAG, "requesting capture...");
      photoOutput.capture({ quality: camera.QualityLevel.QUALITY_LEVEL_MEDIUM });
    });
  }

  async clip(paramsJson: string | undefined): Promise<ClipPayload> {
    // Video capture implementation using VideoOutput
    // For now, keeping it as a stub or implementing a basic flow if requested.
    // Since I'm "continuing porting", I'll try to provide a structure.
    throw new Error("NOT_IMPLEMENTED: video recording requires complex setup");
  }
}
