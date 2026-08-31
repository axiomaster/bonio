/**
 * FloatWindowPage - the global system-float avatar host.
 *
 * The cat animations live in resources/rawfile. Lottie paths cannot resolve
 * rawfile resources, so the page reads each JSON file with ResourceManager and
 * supplies it as animationData. The 500x500 source composition and Contain
 * mode keep the whole avatar visible in the 300x300 float window.
 */

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import lottie, { AnimationItem } from '@ohos/lottie';
import { NodeRuntime } from '../node/NodeRuntime';
import { FloatWindowManager } from '../common/FloatWindowManager';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowPage';
const AVATAR_SIZE = 300;
const AVATAR_SIZE_PX = `${AVATAR_SIZE}px`;
const STATE_OVERRIDE_MS = 8000;

@Entry
@Component
struct FloatWindowPage {
  @State agentState: string = 'idle';
  @State bubbleText: string = '';

  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private bubbleCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private bubbleCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.bubbleCanvasSettings);
  private catAnimation: AnimationItem | undefined = undefined;
  private readonly animationName: string = 'float_cat_animation';
  private requestedAsset: string = '';
  private loadedAsset: string = '';
  private catCanvasReady: boolean = false;
  private bubbleCanvasReady: boolean = false;
  private disposed: boolean = false;

  private bubbleTimer: number = -1;
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private stateOverrideUntil: number = 0;
  private isDragging: boolean = false;
  private dragStartScreenX: number = 0;
  private dragStartScreenY: number = 0;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    hilog.info(DOMAIN, TAG, 'Float window page appearing');
    this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (this.runtime) {
      this.statusTimer = setInterval(() => this.tickState(), 1000);
      this.runtime.chatController.onAvatarCommand = (payloadJson: string) => {
        this.handleAvatarCommand(payloadJson);
      };
      this.runtime.avatarCommandSink = (payloadJson: string) => {
        this.handleAvatarCommand(payloadJson);
      };
    }
  }

  private tickState(): void {
    if (Date.now() < this.stateOverrideUntil || !this.runtime) return;
    const chat = this.runtime.chatController;
    const next = chat.pendingRunCount > 0
      ? 'thinking'
      : chat.streamingAssistantText !== undefined && chat.streamingAssistantText.length > 0
        ? 'speaking'
        : this.runtime.isConnected ? 'idle' : 'working';
    if (next !== this.agentState) this.setAgentState(next);
  }

  private setAgentState(state: string): void {
    this.agentState = state;
    hilog.info(DOMAIN, TAG, 'avatar state -> %{public}s', state);
    void this.loadCatAnimation();
  }

  private getLottieAsset(): string {
    switch (this.agentState) {
      case 'listening': return 'cat-listening.json';
      case 'thinking': return 'cat-thinking.json';
      case 'speaking': return 'cat-speaking.json';
      case 'working': return 'cat-working.json';
      default: return 'cat-idle.json';
    }
  }

  private async loadCatAnimation(): Promise<void> {
    if (!this.catCanvasReady || this.disposed) return;
    const asset = this.getLottieAsset();
    if (asset === this.loadedAsset || asset === this.requestedAsset) return;
    this.requestedAsset = asset;

    try {
      const context = getContext(this) as common.UIAbilityContext;
      const data = await context.resourceManager.getRawFileContent(asset);
      if (this.disposed || !this.catCanvasReady || this.requestedAsset !== asset) return;

      const decoder = new util.TextDecoder('utf-8');
      const animationData = JSON.parse(decoder.decode(data)) as Object;
      this.destroyCatAnimation();
      this.catAnimation = lottie.loadAnimation({
        container: this.catCanvasContext,
        renderer: 'canvas',
        loop: true,
        autoplay: false,
        name: this.animationName,
        contentMode: 'Contain',
        animationData: animationData,
      });
      this.loadedAsset = asset;
      this.catAnimation.addEventListener('DOMLoaded', () => {
        if (!this.disposed && this.loadedAsset === asset) {
          this.catAnimation?.resize();
          this.catAnimation?.play();
        }
      });
      hilog.info(DOMAIN, TAG, 'loaded complete Lottie animation %{public}s', asset);
    } catch (err) {
      if (this.requestedAsset === asset) this.requestedAsset = '';
      hilog.error(DOMAIN, TAG, 'failed to load Lottie %{public}s: %{public}s', asset,
        err instanceof Error ? err.message : String(err));
    }
  }

  private destroyCatAnimation(): void {
    try {
      lottie.destroy(this.animationName);
    } catch (_) {
      // No animation has been attached yet.
    }
    this.catAnimation = undefined;
    this.loadedAsset = '';
  }

  private renderBubble(): void {
    if (!this.bubbleCanvasReady) return;
    const ctx = this.bubbleCanvasContext;
    ctx.clearRect(0, 0, AVATAR_SIZE, AVATAR_SIZE);
    if (this.bubbleText === '') return;

    const text = this.bubbleText.length > 24 ? `${this.bubbleText.slice(0, 23)}...` : this.bubbleText;
    const width = Math.min(180, 24 + text.length * 7);
    const x = 10;
    const y = 4;
    ctx.fillStyle = '#FFFFFF';
    ctx.strokeStyle = '#CCCCCC';
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x + 8, y);
    ctx.lineTo(x + width - 8, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + 8);
    ctx.lineTo(x + width, y + 30);
    ctx.quadraticCurveTo(x + width, y + 38, x + width - 8, y + 38);
    ctx.lineTo(x + 8, y + 38);
    ctx.quadraticCurveTo(x, y + 38, x, y + 30);
    ctx.lineTo(x, y + 8);
    ctx.quadraticCurveTo(x, y, x + 8, y);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#3D2D18';
    ctx.font = '12px sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, x + 10, y + 19);
  }

  private setBubble(text: string): void {
    this.bubbleText = text;
    if (this.bubbleTimer !== -1) clearTimeout(this.bubbleTimer);
    this.bubbleTimer = setTimeout(() => {
      this.bubbleText = '';
      this.bubbleTimer = -1;
      this.renderBubble();
    }, 5000);
    this.renderBubble();
  }

  private handleAvatarCommand(payloadJson: string): void {
    try {
      const cmd = JSON.parse(payloadJson) as Record<string, Object>;
      const action = cmd.action as string | undefined;
      const params = (cmd.params as Record<string, Object>) || {};
      if (action === 'sequence') {
        const steps = params.steps as Object[] | undefined;
        if (Array.isArray(steps)) this.runSequence(steps);
        return;
      }
      if (action === 'setBubble' && params.text) {
        this.setBubble(params.text as string);
      } else if (action === 'clearBubble') {
        this.bubbleText = '';
        this.renderBubble();
      } else if (action === 'setState' && params.state) {
        this.stateOverrideUntil = Date.now() + STATE_OVERRIDE_MS;
        this.setAgentState(params.state as string);
      } else if (action === 'moveTo' && params.x !== undefined && params.y !== undefined) {
        void FloatWindowManager.getInstance().moveWindowTo(params.x as number, params.y as number);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'avatar.command parse failed: %{public}s',
        err instanceof Error ? err.message : String(err));
    }
  }

  private runSequence(steps: Object[]): void {
    let delay = 0;
    for (const step of steps) {
      const item = step as Record<string, Object>;
      delay += (item.delayMs as number) || 0;
      setTimeout(() => {
        this.handleAvatarCommand(JSON.stringify({
          action: item.action as string | undefined,
          params: (item.params as Record<string, Object>) || {},
        }));
      }, delay);
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.statusTimer !== -1) clearInterval(this.statusTimer);
    if (this.bubbleTimer !== -1) clearTimeout(this.bubbleTimer);
    this.statusTimer = -1;
    this.bubbleTimer = -1;
    this.requestedAsset = '';
    this.destroyCatAnimation();
  }

  build() {
    Stack() {
      Canvas(this.catCanvasContext)
        .width(AVATAR_SIZE_PX)
        .height(AVATAR_SIZE_PX)
        .onReady(() => {
          this.catCanvasReady = true;
          this.catCanvasContext.imageSmoothingEnabled = true;
          this.catCanvasContext.imageSmoothingQuality = 'high';
          void this.loadCatAnimation();
        })

      Canvas(this.bubbleCanvasContext)
        .width(AVATAR_SIZE_PX)
        .height(AVATAR_SIZE_PX)
        .onReady(() => {
          this.bubbleCanvasReady = true;
          this.renderBubble();
        })
    }
    .width(AVATAR_SIZE_PX)
    .height(AVATAR_SIZE_PX)
    .backgroundColor(Color.Transparent)
    .clip(true)
    .onTouch((event: TouchEvent) => this.handleDrag(event))
  }

  private handleDrag(event: TouchEvent): void {
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
    } else if (event.type === TouchType.Move && this.isDragging) {
      void manager.moveWindowTo(
        this.dragStartWindowX + touch.screenX - this.dragStartScreenX,
        this.dragStartWindowY + touch.screenY - this.dragStartScreenY,
      );
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.isDragging = false;
    }
  }
}
