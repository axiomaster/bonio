import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowManager';
const FLOAT_WINDOW_NAME = 'CatSystemFloatWindow';
const FLOAT_WINDOW_SIZE = 200;

export class FloatWindowManager {
  private static instance: FloatWindowManager;
  private floatWindow: window.Window | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  private constructor() {}

  public static getInstance(): FloatWindowManager {
    if (!FloatWindowManager.instance) {
      FloatWindowManager.instance = new FloatWindowManager();
    }
    return FloatWindowManager.instance;
  }

  public setAbilityContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  public async showFloatWindow(): Promise<boolean> {
    if (this.floatWindow) {
      hilog.info(DOMAIN, TAG, 'Float window already exists');
      return true;
    }

    if (!this.abilityContext) {
      hilog.error(DOMAIN, TAG, 'UIAbilityContext not set');
      return false;
    }

    try {
      this.floatWindow = await window.createWindow({
        name: FLOAT_WINDOW_NAME,
        windowType: window.WindowType.TYPE_FLOAT,
        ctx: this.abilityContext
      });
      hilog.info(DOMAIN, TAG, 'System float window created successfully');

      await this.floatWindow.moveWindowTo(100, 100);
      await this.floatWindow.resize(FLOAT_WINDOW_SIZE, FLOAT_WINDOW_SIZE);
      this.floatWindow.setWindowBackgroundColor('#00000000');
      await this.floatWindow.setWindowFocusable(false);
      await this.floatWindow.setWindowTouchable(true);
      await this.floatWindow.setUIContent('pages/FloatWindowPage');
      await this.floatWindow.showWindow();
      hilog.info(DOMAIN, TAG, 'System float window shown successfully');
      return true;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to create system float window: %{public}s', JSON.stringify(error));
      await this.destroyCreatedWindow();
      return false;
    }
  }

  public async startDragging(offsetX: number = FLOAT_WINDOW_SIZE / 2, offsetY: number = FLOAT_WINDOW_SIZE / 2): Promise<void> {
    if (!this.floatWindow) {
      hilog.warn(DOMAIN, TAG, 'startDragging ignored because float window is not showing');
      return;
    }

    try {
      await this.floatWindow.startMoving(Math.floor(offsetX), Math.floor(offsetY));
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to start moving float window: %{public}s', JSON.stringify(error));
    }
  }

  private async destroyCreatedWindow(): Promise<void> {
    if (this.floatWindow) {
      try {
        await this.floatWindow.destroyWindow();
      } catch (err) {
        const error = err as BusinessError;
        hilog.error(DOMAIN, TAG, 'Failed to clean up float window: %{public}s', JSON.stringify(error));
      }
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
