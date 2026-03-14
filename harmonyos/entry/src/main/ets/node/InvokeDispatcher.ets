import { GatewaySession, InvokeResult, InvokeError } from '../gateway/GatewaySession';
import {
  OpenClawCanvasCommand,
  OpenClawCanvasA2UICommand,
  OpenClawCameraCommand,
  OpenClawLocationCommand,
  OpenClawScreenCommand,
  OpenClawSmsCommand,
  CanvasCommandNamespacePrefix,
  CanvasA2UICommandNamespacePrefix,
  CameraCommandNamespacePrefix,
  CameraCommandNamespacePrefix as CameraPrefix,
  ScreenCommandNamespacePrefix,
  LocationCommandNamespacePrefix
} from '../protocol/ProtocolConstants';
import { CanvasController } from './CanvasController';

// Placeholder handlers for hardware features not yet ported
export interface CameraHandler {
  handleSnap(paramsJson: string | undefined): Promise<InvokeResult>;
  handleClip(paramsJson: string | undefined): Promise<InvokeResult>;
}

export interface LocationHandler {
  handleLocationGet(paramsJson: string | undefined): Promise<InvokeResult>;
}

export interface ScreenHandler {
  handleScreenRecord(paramsJson: string | undefined): Promise<InvokeResult>;
}

export interface SmsHandler {
  handleSmsSend(paramsJson: string | undefined): Promise<InvokeResult>;
}

export interface A2UIHandler {
  resolveA2uiHostUrl(): string | undefined;
  ensureA2uiReady(url: string): boolean;
  decodeA2uiMessages(command: string, paramsJson: string | undefined): string | undefined;
  get a2uiResetJS(): string;
  a2uiApplyMessagesJS(messagesJson: string): string;
}

export interface DebugHandler {
  handleEd25519(): Promise<InvokeResult>;
  handleLogs(): Promise<InvokeResult>;
}

export interface AppUpdateHandler {
  handleUpdate(paramsJson: string | undefined): Promise<InvokeResult>;
}

export class InvokeDispatcher {
  private canvas: CanvasController;
  private cameraHandler: CameraHandler;
  private locationHandler: LocationHandler;
  private screenHandler: ScreenHandler;
  private smsHandler: SmsHandler;
  private a2uiHandler: A2UIHandler;
  private debugHandler: DebugHandler;
  private appUpdateHandler: AppUpdateHandler;
  private isForeground: () => boolean;
  private cameraEnabled: () => boolean;
  private locationEnabled: () => boolean;

  constructor(
    canvas: CanvasController,
    cameraHandler: CameraHandler,
    locationHandler: LocationHandler,
    screenHandler: ScreenHandler,
    smsHandler: SmsHandler,
    a2uiHandler: A2UIHandler,
    debugHandler: DebugHandler,
    appUpdateHandler: AppUpdateHandler,
    isForeground: () => boolean,
    cameraEnabled: () => boolean,
    locationEnabled: () => boolean
  ) {
    this.canvas = canvas;
    this.cameraHandler = cameraHandler;
    this.locationHandler = locationHandler;
    this.screenHandler = screenHandler;
    this.smsHandler = smsHandler;
    this.a2uiHandler = a2uiHandler;
    this.debugHandler = debugHandler;
    this.appUpdateHandler = appUpdateHandler;
    this.isForeground = isForeground;
    this.cameraEnabled = cameraEnabled;
    this.locationEnabled = locationEnabled;
  }

  public async handleInvoke(command: string, paramsJson: string | undefined): Promise<InvokeResult> {
    if (
      command.startsWith(CanvasCommandNamespacePrefix) ||
      command.startsWith(CanvasA2UICommandNamespacePrefix) ||
      command.startsWith(CameraCommandNamespacePrefix) ||
      command.startsWith(ScreenCommandNamespacePrefix)
    ) {
      if (!this.isForeground()) {
        return this.makeError("NODE_BACKGROUND_UNAVAILABLE", "NODE_BACKGROUND_UNAVAILABLE: canvas/camera/screen commands require foreground");
      }
    }

    if (command.startsWith(CameraCommandNamespacePrefix) && !this.cameraEnabled()) {
      return this.makeError("CAMERA_DISABLED", "CAMERA_DISABLED: enable Camera in Settings");
    }

    if (command.startsWith(LocationCommandNamespacePrefix) && !this.locationEnabled()) {
      return this.makeError("LOCATION_DISABLED", "LOCATION_DISABLED: enable Location in Settings");
    }

    try {
      switch (command) {
        case OpenClawCanvasCommand.Present:
        case OpenClawCanvasCommand.Navigate:
          // Placeholder for canvas navigation parsing
          // Placeholder for canvas navigation parsing
          this.canvas.navigate(paramsJson ? (JSON.parse(paramsJson) as Record<string, string>).url : undefined);
          return this.makeSuccess();

        case OpenClawCanvasCommand.Hide:
          return this.makeSuccess();
          
        case OpenClawCanvasCommand.Eval:
          if (!paramsJson) {
            return this.makeError("INVALID_REQUEST", "INVALID_REQUEST: javaScript required");
          }
          const evalParams = JSON.parse(paramsJson) as Record<string, string>;
          const js = evalParams.javaScript || evalParams.js;
          const result = this.canvas.eval(js);
          const evalRes: Record<string, string> = { "result": result };
          return this.makeSuccess(JSON.stringify(evalRes));
          
        case OpenClawCanvasCommand.Snapshot:
          let format = "jpeg";
          let quality = 80;
          let maxWidth = 1920;
          if (paramsJson) {
            try {
              const opts = JSON.parse(paramsJson) as Record<string, Object>;
              if (opts.format) format = opts.format as string;
              if (opts.quality) quality = opts.quality as number;
              if (opts.maxWidth) maxWidth = opts.maxWidth as number;
            } catch (e) { /* ignore parse error */ }
          }
          const resultBase64 = await this.canvas.snapshotBase64(); // Note: Actual implementation would need to pass these to canvas
          if (resultBase64 === "") {
            return this.makeError("NOT_IMPLEMENTED", "Canvas Snapshot not fully implemented yet");
          }
          return this.makeSuccess(JSON.stringify({ format: format, base64: resultBase64 }));

        case OpenClawCanvasA2UICommand.Reset:
          const resetUrl = this.a2uiHandler.resolveA2uiHostUrl();
          if (!resetUrl) {
            return this.makeError("A2UI_HOST_NOT_CONFIGURED", "A2UI_HOST_NOT_CONFIGURED: gateway did not advertise canvas host");
          }
          this.canvas.eval(this.a2uiHandler.a2uiResetJS);
          return this.makeSuccess();

        case OpenClawCanvasA2UICommand.Push:
        case OpenClawCanvasA2UICommand.PushJSONL:
          const messagesJson = this.a2uiHandler.decodeA2uiMessages(command, paramsJson);
          if (!messagesJson) {
             return this.makeError("INVALID_REQUEST", "invalid A2UI payload");
          }
          const pushUrl = this.a2uiHandler.resolveA2uiHostUrl();
          if (!pushUrl) {
            return this.makeError("A2UI_HOST_NOT_CONFIGURED", "A2UI_HOST_NOT_CONFIGURED");
          }
          this.canvas.eval(this.a2uiHandler.a2uiApplyMessagesJS(messagesJson));
          return this.makeSuccess();

        case OpenClawCameraCommand.Snap:
          return await this.cameraHandler.handleSnap(paramsJson);
          
        case OpenClawCameraCommand.Clip:
          return await this.cameraHandler.handleClip(paramsJson);

        case OpenClawLocationCommand.Get:
          return await this.locationHandler.handleLocationGet(paramsJson);

        case OpenClawScreenCommand.Record:
          return await this.screenHandler.handleScreenRecord(paramsJson);

        case OpenClawSmsCommand.Send:
          return await this.smsHandler.handleSmsSend(paramsJson);

        case "debug.ed25519":
          return await this.debugHandler.handleEd25519();
          
        case "debug.logs":
          return await this.debugHandler.handleLogs();

        case "app.update":
          return await this.appUpdateHandler.handleUpdate(paramsJson);

        default:
          return this.makeError("INVALID_REQUEST", "INVALID_REQUEST: unknown command");
      }
    } catch (err) {
      return this.makeError("INTERNAL_ERROR", err instanceof Error ? err.message : String(err));
    }
  }

  private makeError(code: string, message: string): InvokeResult {
    const err: InvokeError = { code: code, message: message };
    const res: InvokeResult = { ok: false, error: err };
    return res;
  }

  private makeSuccess(payloadJson?: string): InvokeResult {
    const res: InvokeResult = { ok: true, payloadJson: payloadJson };
    return res;
  }
}
