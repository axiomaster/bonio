import lottie from '@ohos/lottie';
import { NodeRuntime } from '../node/NodeRuntime';

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

  aboutToAppear() {
    this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (this.runtime) {
      this.statusTimer = setInterval(() => {
        if (this.runtime) {
          // Simplified state for floating window
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
        .onReady(() => {
          this.loadCatAnimation();
        })
    }
    .width(200)
    .height(200)
    .backgroundColor('#00000000') // Transparent
    .gesture(
      PanGesture()
        .onActionUpdate((event: GestureEvent) => {
          // Dragging logic would go here if we had access to the window object directly in the page
          // For now, it's a fixed position overlay unless we add a callback to the manager
        })
    )
  }
}
