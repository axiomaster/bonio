import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowManager';

export class FloatWindowManager {
  private static instance: FloatWindowManager;
  private floatWindow: window.Window | null = null;
  private context: Context | null = null;

  private constructor() {}

  public static getInstance(): FloatWindowManager {
    if (!FloatWindowManager.instance) {
      FloatWindowManager.instance = new FloatWindowManager();
    }
    return FloatWindowManager.instance;
  }

  public init(context: Context): void {
    this.context = context;
  }

  public async showFloatWindow(): Promise<void> {
    if (this.floatWindow) {
      hilog.info(DOMAIN, TAG, 'Float window already exists');
      return;
    }

    if (!this.context) {
      hilog.error(DOMAIN, TAG, 'Context not initialized');
      return;
    }

    try {
      const config: window.Configuration = {
        name: "CatFloatWindow",
        windowType: window.WindowType.TYPE_FLOAT,
        ctx: this.context
      };

      this.floatWindow = await window.createWindow(config);
      hilog.info(DOMAIN, TAG, 'Float window created successfully');

      await this.floatWindow.moveTo(100, 100);
      await this.floatWindow.setWindowLayoutFullScreen(true);
      await this.floatWindow.resize(200, 200);
      
      // Background should be transparent
      await this.floatWindow.setWindowBackgroundColor('#00000000');

      await this.floatWindow.loadContent('pages/FloatWindowPage');
      await this.floatWindow.showWindow();
      hilog.info(DOMAIN, TAG, 'Float window shown successfully');
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to create float window: %{public}s', JSON.stringify(error));
      this.floatWindow = null;
    }
  }

  public async hideFloatWindow(): Promise<void> {
    if (this.floatWindow) {
      try {
        await this.floatWindow.destroyWindow();
        this.floatWindow = null;
        hilog.info(DOMAIN, TAG, 'Float window destroyed successfully');
      } catch (err) {
        const error = err as BusinessError;
        hilog.error(DOMAIN, TAG, 'Failed to destroy float window: %{public}s', JSON.stringify(error));
      }
    }
  }

  public isWindowShowing(): boolean {
    return this.floatWindow !== null;
  }
}
