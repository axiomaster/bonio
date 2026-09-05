import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowManager';
const FLOAT_WINDOW_NAME = 'CatSystemFloatWindow';
const FLOAT_WINDOW_WIDTH_PX = 300;
const FLOAT_WINDOW_HEIGHT_PX = 348;
const INITIAL_WINDOW_X = 100;
const INITIAL_WINDOW_Y = 100;
// Magic Cue: when expanded the window widens to hold the capsule strip beside
// the avatar. Side 'left' also shifts the window origin left so the avatar
// keeps its absolute screen position.
const CUE_CAPSULE_WIDTH_PX = 420;
const CUE_GAP_PX = 16;
const CUE_OFFSET_PX = FLOAT_WINDOW_WIDTH_PX + CUE_GAP_PX;
const CUE_EXPANDED_WIDTH_PX = FLOAT_WINDOW_WIDTH_PX + CUE_GAP_PX + CUE_CAPSULE_WIDTH_PX;

export class FloatWindowManager {
  private static instance: FloatWindowManager;
  private floatWindow: window.Window | null = null;
  private abilityContext: common.UIAbilityContext | null = null;
  private windowX: number = INITIAL_WINDOW_X;
  private windowY: number = INITIAL_WINDOW_Y;
  private isMovePending: boolean = false;
  private pendingX: number = INITIAL_WINDOW_X;
  private pendingY: number = INITIAL_WINDOW_Y;
  private cueExpandedSide: string | null = null;

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

      await this.tryConfigureWindow('resize', async () => {
        await this.floatWindow?.resize(FLOAT_WINDOW_WIDTH_PX, FLOAT_WINDOW_HEIGHT_PX);
      });
      await this.tryConfigureWindow('setWindowFocusable', async () => {
        await this.floatWindow?.setWindowFocusable(false);
      });
      await this.tryConfigureWindow('setWindowTouchable', async () => {
        await this.floatWindow?.setWindowTouchable(true);
      });
      await this.moveWindowTo(INITIAL_WINDOW_X, INITIAL_WINDOW_Y, false);

      await this.floatWindow.setUIContent('pages/FloatWindowPage');
      hilog.info(DOMAIN, TAG, 'System float window UI content loaded');
      await this.tryConfigureWindow('setWindowBackgroundColor', () => {
        this.floatWindow?.setWindowBackgroundColor('#00000000');
      });
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

  private async tryConfigureWindow(name: string, operation: () => Promise<void> | void): Promise<void> {
    try {
      await operation();
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'Ignoring non-fatal float window configuration failure in %{public}s: %{public}s',
        name, JSON.stringify(error));
    }
  }

  public getWindowPosition(): [number, number] {
    return [this.windowX, this.windowY];
  }

  public async moveWindowTo(x: number, y: number, coalesce: boolean = true): Promise<void> {
    if (!this.floatWindow) {
      hilog.warn(DOMAIN, TAG, 'moveWindowTo ignored because float window is not showing');
      return;
    }

    this.pendingX = Math.max(0, Math.floor(x));
    this.pendingY = Math.max(0, Math.floor(y));
    if (coalesce && this.isMovePending) {
      return;
    }

    this.isMovePending = true;
    try {
      while (this.floatWindow) {
        const targetX = this.pendingX;
        const targetY = this.pendingY;
        await this.floatWindow.moveWindowTo(targetX, targetY);
        this.windowX = targetX;
        this.windowY = targetY;

        if (!coalesce || (this.pendingX === targetX && this.pendingY === targetY)) {
          break;
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'moveWindowTo failed: %{public}s', JSON.stringify(error));
    } finally {
      this.isMovePending = false;
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
      this.isMovePending = false;
    }
  }

  public async hideFloatWindow(): Promise<void> {
    if (this.floatWindow) {
      try {
        await this.floatWindow.destroyWindow();
        this.floatWindow = null;
        this.isMovePending = false;
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

  public isCueExpanded(): boolean {
    return this.cueExpandedSide !== null;
  }

  /** Widen the window to reveal the capsule strip; shift left for side 'left'. */
  public async setCueExpanded(side: string): Promise<void> {
    if (!this.floatWindow || this.cueExpandedSide !== null) return;
    const dir = side === 'left' ? 'left' : 'right';
    await this.tryConfigureWindow('resize', async () => {
      await this.floatWindow?.resize(CUE_EXPANDED_WIDTH_PX, FLOAT_WINDOW_HEIGHT_PX);
    });
    this.cueExpandedSide = dir;
    if (dir === 'left') {
      await this.moveWindowTo(this.windowX - CUE_OFFSET_PX, this.windowY, false);
    }
  }

  /** Restore the compact avatar window, undoing any leftward shift. */
  public async collapseCue(): Promise<void> {
    if (!this.floatWindow || this.cueExpandedSide === null) return;
    const dir = this.cueExpandedSide;
    this.cueExpandedSide = null;
    await this.tryConfigureWindow('resize', async () => {
      await this.floatWindow?.resize(FLOAT_WINDOW_WIDTH_PX, FLOAT_WINDOW_HEIGHT_PX);
    });
    if (dir === 'left') {
      await this.moveWindowTo(this.windowX + CUE_OFFSET_PX, this.windowY, false);
    }
  }
}
