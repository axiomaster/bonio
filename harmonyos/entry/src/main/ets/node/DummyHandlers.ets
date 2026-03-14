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
  async handleScreenRecord(paramsJson: string | undefined): Promise<InvokeResult> {
    return { ok: false, error: { code: "NOT_IMPLEMENTED", message: "Screen Record not ported yet" } };
  }
}
