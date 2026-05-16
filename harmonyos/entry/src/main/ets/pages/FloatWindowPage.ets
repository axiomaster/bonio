import lottie from '@ohos/lottie';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { NodeRuntime } from '../node/NodeRuntime';
import { FloatWindowManager } from '../common/FloatWindowManager';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowPage';

@Entry
@Component
struct FloatWindowPage {
  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private currentLottieAnim: string = 'cat_float_anim';
  private lastLoadedAsset: string = '';
  private canvasReady: boolean = false;

  @State agentState: string = 'idle';
  @State blinkMarker: boolean = false;
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private blinkTimer: number = -1;
  private isDragging: boolean = false;
  private dragStartScreenX: number = 0;
  private dragStartScreenY: number = 0;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'Float window page appearing');
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
    this.blinkTimer = setInterval(() => {
      this.blinkMarker = !this.blinkMarker;
    }, 1200);
  }

  aboutToDisappear() {
    hilog.info(DOMAIN, TAG, 'Float window page disappearing');
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    if (this.blinkTimer !== -1) {
      clearInterval(this.blinkTimer);
      this.blinkTimer = -1;
    }
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (_e) { /* ignore */ }
    try {
      lottie.setAttachedCanvasHasVisibleArea(this.catCanvasContext, false);
    } catch (_e) { /* ignore */ }
    this.canvasReady = false;
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
    if (!this.canvasReady) return;
    const asset = this.getLottieAsset();
    if (asset === this.lastLoadedAsset) return;
    this.lastLoadedAsset = asset;
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (_e) { /* ignore */ }

    hilog.info(DOMAIN, TAG, 'Loading float avatar lottie: %{public}s', asset);
    try {
      lottie.setAttachedCanvasHasVisibleArea(this.catCanvasContext, true);
    } catch (_e) { /* ignore */ }
    lottie.loadAnimation({
      container: this.catCanvasContext,
      renderer: 'canvas',
      loop: true,
      autoplay: true,
      name: this.currentLottieAnim,
      path: asset,
    });
    try {
      lottie.resize(176, 176, this.currentLottieAnim, true);
      lottie.play(this.currentLottieAnim, true);
    } catch (_e) { /* ignore */ }
  }

  private onCatCanvasReady() {
    hilog.info(DOMAIN, TAG, 'Float avatar canvas ready');
    this.canvasReady = true;
    this.lastLoadedAsset = '';
    try {
      lottie.bindContext2dToCoordinator(this.catCanvasContext);
      lottie.setAttachedCanvasHasVisibleArea(this.catCanvasContext, true);
    } catch (_e) { /* ignore */ }
    setTimeout(() => {
      this.loadCatAnimation();
    }, 50);
  }

  build() {
    Stack() {
      this.NativeCatAvatar()
      Canvas(this.catCanvasContext)
        .width(176)
        .height(176)
        .backgroundColor('#00000000')
        .onReady(() => {
          this.onCatCanvasReady();
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

  @Builder
  NativeCatAvatar() {
    Stack() {
      Circle()
        .width(118)
        .height(118)
        .fill('#F9D27D')
        .stroke('#6A4A1F')
        .strokeWidth(4)
        .margin({ top: 42 })

      Row() {
        this.CatEar(28)
        Blank().width(54)
        this.CatEar(-28)
      }
      .width(140)
      .height(80)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 22 })

      Column() {
        Row() {
          Text(this.blinkMarker ? '-' : 'o')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#3D2D18')
            .width(34)
            .textAlign(TextAlign.Center)
          Text(this.blinkMarker ? '-' : 'o')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#3D2D18')
            .width(34)
            .textAlign(TextAlign.Center)
        }
        .justifyContent(FlexAlign.Center)
        .margin({ top: 74 })

        Text('w')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3D2D18')
          .margin({ top: -2 })

        Text(this.agentState === 'working' ? '...' : '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#3D2D18')
          .height(18)
          .margin({ top: -8 })
      }
      .width(140)
      .height(150)
      .alignItems(HorizontalAlign.Center)
    }
    .width(200)
    .height(200)
    .backgroundColor('#00000000')
  }

  @Builder
  CatEar(angle: number) {
    Column()
      .width(40)
      .height(52)
      .backgroundColor('#F9D27D')
      .border({ width: 4, color: '#6A4A1F' })
      .borderRadius({ topLeft: 24, topRight: 24, bottomLeft: 6, bottomRight: 6 })
      .rotate({ angle: angle })
  }
}
