import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { buffer } from '@kit.ArkTS';

export class CanvasController {
  private controller: webview.WebviewController | undefined = undefined;
  private currentUrl: string | undefined = undefined;
  private debugStatusEnabled: boolean = false;
  private debugStatusTitle: string | undefined = undefined;
  private debugStatusSubtitle: string | undefined = undefined;

  public attach(controller: webview.WebviewController) {
    this.controller = controller;
    hilog.info(0x3D00, 'CanvasController', "attached webview controller");
    this.reload();
  }

  public navigate(url: string | undefined) {
    const trimmed = url?.trim();
    this.currentUrl = (!trimmed || trimmed === "" || trimmed === "/") ? undefined : trimmed;
    this.reload();
  }

  public getCurrentUrl(): string | undefined {
    return this.currentUrl;
  }

  public setDebugStatusEnabled(enabled: boolean) {
    this.debugStatusEnabled = enabled;
    this.applyDebugStatus();
  }

  public setDebugStatus(title: string | undefined, subtitle: string | undefined) {
    this.debugStatusTitle = title;
    this.debugStatusSubtitle = subtitle;
    this.applyDebugStatus();
  }

  private reload() {
    if (!this.controller) return;
    try {
      if (this.currentUrl) {
        hilog.info(0x3D00, 'CanvasController', "loading url: %{public}s", this.currentUrl);
        this.controller.loadUrl(this.currentUrl);
      } else {
        hilog.info(0x3D00, 'CanvasController', "loading scaffold.html");
        this.controller.loadUrl($rawfile('scaffold.html'));
      }
    } catch (e) {
      hilog.error(0x3D00, 'CanvasController', "loadUrl failed: %{public}s", e instanceof Error ? e.message : String(e));
    }
  }

  private applyDebugStatus() {
    if (!this.controller) return;
    const enabled = this.debugStatusEnabled;
    const title = this.debugStatusTitle || "";
    const subtitle = this.debugStatusSubtitle || "";

    const js = `
      (() => {
        try {
          const api = globalThis.__openclaw;
          if (!api) return;
          if (typeof api.setDebugStatusEnabled === 'function') {
            api.setDebugStatusEnabled(${enabled});
          }
          if (!${enabled}) return;
          if (typeof api.setStatus === 'function') {
            api.setStatus(${JSON.stringify(title)}, ${JSON.stringify(subtitle)});
          }
        } catch (_) {}
      })();
    `;
    try {
      this.controller.runJavaScript(js);
    } catch (e) {
      hilog.error(0x3D00, 'CanvasController', "applyDebugStatus JS failed: %{public}s", e instanceof Error ? e.message : String(e));
    }
  }

  public eval(javaScript: string): string {
    if (!this.controller) return "Error: webview not attached";
    try {
      this.controller.runJavaScript(javaScript, (error, result) => {
        if (error) {
          hilog.error(0x3D00, 'CanvasController', "JS eval error: %{public}s", error.message);
        }
      });
    } catch (e) {
      hilog.error(0x3D00, 'CanvasController', "eval failed: %{public}s", e instanceof Error ? e.message : String(e));
      return "failed";
    }
    return "executing"; 
  }

  public async snapshotBase64(format: string = 'jpeg', quality: number = 82, maxWidth: number = 0): Promise<string> {
    try {
      // 1. Get PixelMap of the Web component
      const pixelMap = await componentSnapshot.get("canvas_web_comp");
      if (!pixelMap) return "";

      // 2. Pack PixelMap to specific format
      const imagePacker = image.createImagePacker();
      const packOptions: image.PackingOption = {
        format: `image/${format}`,
        quality: quality
      };
      
      const packedData = await imagePacker.packing(pixelMap, packOptions);
      if (!packedData) return "";

      // 3. Convert to base64
      const base64String = buffer.from(packedData).toString('base64');
      return base64String;
    } catch (e) {
      hilog.error(0x3D00, 'CanvasController', "Snapshot failed: %{public}s", e instanceof Error ? e.message : String(e));
      return "";
    }
  }
}
