export enum OpenClawCapability {
  Canvas = "canvas",
  Camera = "camera",
  Screen = "screen",
  Sms = "sms",
  VoiceWake = "voiceWake",
  Location = "location",
}

export enum OpenClawCanvasCommand {
  Present = "canvas.present",
  Hide = "canvas.hide",
  Navigate = "canvas.navigate",
  Eval = "canvas.eval",
  Snapshot = "canvas.snapshot",
}

export const CanvasCommandNamespacePrefix = "canvas.";

export enum OpenClawCanvasA2UICommand {
  Push = "canvas.a2ui.push",
  PushJSONL = "canvas.a2ui.pushJSONL",
  Reset = "canvas.a2ui.reset",
}

export const CanvasA2UICommandNamespacePrefix = "canvas.a2ui.";

export enum OpenClawCameraCommand {
  Snap = "camera.snap",
  Clip = "camera.clip",
}

export const CameraCommandNamespacePrefix = "camera.";

export enum OpenClawScreenCommand {
  Record = "screen.record",
}

export const ScreenCommandNamespacePrefix = "screen.";

export enum OpenClawSmsCommand {
  Send = "sms.send",
}

export const SmsCommandNamespacePrefix = "sms.";

export enum OpenClawLocationCommand {
  Get = "location.get",
}

export const LocationCommandNamespacePrefix = "location.";
