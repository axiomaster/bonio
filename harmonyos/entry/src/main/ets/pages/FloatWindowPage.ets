import lottie from '@ohos/lottie';
import { NodeRuntime } from '../node/NodeRuntime';
import { FloatWindowManager } from '../common/FloatWindowManager';

@Entry
@Component
struct FloatWindowPage {
  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private currentLottieAnim: string = 'cat_float_anim';
  private lastLoadedAsset: string = '';

  @State agentState: string = 'idle';
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private isDragging: boolean = false;
  private dragStartScreenX: number = 0;
  private dragStartScreenY: number = 0;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;

  aboutToAppear() {
    this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (this.runtime) {
      this.statusTimer = setInterval(() => {
        if (this.runtime) {
          const state = this.runtime.isConnected ? 'idle' : 'working';
          if (this.agentState !== state) {
            this.agentState = state;
            this.loadCatAnimation();
          }
        }
      }, 1000);
    }
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
    }
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (e) { /* ignore */ }
  }

  private getLottieAsset(): string {
    switch (this.agentState) {
      case 'idle': return 'cat-idle.json';
      case 'listening': return 'cat-listening.json';
      case 'thinking': return 'cat-thinking.json';
      case 'speaking': return 'cat-speaking.json';
      case 'working': return 'cat-working.json';
      default: return 'cat-idle.json';
    }
  }

  private loadCatAnimation() {
    const asset = this.getLottieAsset();
    if (asset === this.lastLoadedAsset) return;
    this.lastLoadedAsset = asset;
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (e) { /* ignore */ }

    lottie.loadAnimation({
      container: this.catCanvasContext,
      renderer: 'canvas',
      loop: true,
      autoplay: true,
      name: this.currentLottieAnim,
      path: asset,
    });
  }

  build() {
    Stack() {
      Canvas(this.catCanvasContext)
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onReady(() => {
          this.loadCatAnimation();
        })
    }
    .width(200)
    .height(200)
    .backgroundColor('#00000000')
    .onTouch((event: TouchEvent) => {
      if (event.touches.length === 0) {
        this.isDragging = false;
        return;
      }

      const touch = event.touches[0];
      const manager = FloatWindowManager.getInstance();
      if (event.type === TouchType.Down) {
        const position = manager.getWindowPosition();
        this.isDragging = true;
        this.dragStartScreenX = touch.screenX;
        this.dragStartScreenY = touch.screenY;
        this.dragStartWindowX = position[0];
        this.dragStartWindowY = position[1];
        return;
      }

      if (event.type === TouchType.Move && this.isDragging) {
        const targetX = this.dragStartWindowX + touch.screenX - this.dragStartScreenX;
        const targetY = this.dragStartWindowY + touch.screenY - this.dragStartScreenY;
        manager.moveWindowTo(targetX, targetY);
        return;
      }

      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isDragging = false;
      }
    })
  }
}
