import { InvokeResult } from '../gateway/GatewaySession';
import { CameraHandler, ScreenHandler } from './InvokeDispatcher';

export class DummyCameraHandler implements CameraHandler {
  async handleSnap(paramsJson: string | undefined): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Camera not ported yet" } };
  }
  async handleClip(paramsJson: string | undefined): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Camera not ported yet" } };
  }
}

export class DummyScreenHandler implements ScreenHandler {
  startScreenAwareness(): void {}

  setScreenAwarenessEnabled(enabled: boolean): void {}

  async handleScreenRecord(paramsJson: string | undefined): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Screen Record not ported yet" } };
  }

  async handleScreenContext(paramsJson: string | undefined): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Screen Awareness not ported yet" } };
  }

  async handleScreenScrollToHook(paramsJson: string | undefined): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Screen Awareness not ported yet" } };
  }

  async handleSmartEdgeTrigger(): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "SmartEdge trigger not ported yet" } };
  }

  async handleScreenshotCapture(): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Screenshot capture not ported yet" } };
  }
}
