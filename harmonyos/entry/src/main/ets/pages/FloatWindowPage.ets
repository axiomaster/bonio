/**
 * Global system-float avatar host. Cat uses Lottie rawfiles; Kun uses the
 * supplied 8x9 WebP spritesheet. The bubble occupies a separate top strip so
 * it never overlays the avatar. All window/content dimensions are physical px.
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
const BUBBLE_AREA_HEIGHT = 48;
const FLOAT_WINDOW_HEIGHT = AVATAR_SIZE + BUBBLE_AREA_HEIGHT;
const BUBBLE_AREA_HEIGHT_PX = `${BUBBLE_AREA_HEIGHT}px`;
const FLOAT_WINDOW_HEIGHT_PX = `${FLOAT_WINDOW_HEIGHT}px`;
const COMMAND_OVERRIDE_MS = 8000;
const INTERACTION_MS = 2400;
const LONG_PRESS_MS = 500;
const DOUBLE_TAP_MS = 320;
const DRAG_THRESHOLD_PX = 8;
const KUN_FRAME_WIDTH = 192 * AVATAR_SIZE / 208;
const KUN_SHEET_WIDTH = KUN_FRAME_WIDTH * 8;
const KUN_SHEET_HEIGHT = AVATAR_SIZE * 9;

class KunAnimationSpec {
  row: number;
  frameDurations: number[];

  constructor(row: number, frameDurations: number[]) {
    this.row = row;
    this.frameDurations = frameDurations;
  }
}

class KunAnimations {
  static readonly idle = new KunAnimationSpec(0, [280, 110, 110, 140, 140, 320]);
  static readonly runRight = new KunAnimationSpec(1, [120, 120, 120, 120, 120, 120, 120, 220]);
  static readonly runLeft = new KunAnimationSpec(2, [120, 120, 120, 120, 120, 120, 120, 220]);
  static readonly wave = new KunAnimationSpec(3, [140, 140, 140, 280]);
  static readonly jump = new KunAnimationSpec(4, [140, 140, 140, 140, 280]);
  static readonly failed = new KunAnimationSpec(5, [140, 140, 140, 140, 140, 140, 140, 240]);
  static readonly waiting = new KunAnimationSpec(6, [150, 150, 150, 150, 150, 260]);
  static readonly working = new KunAnimationSpec(7, [120, 120, 120, 120, 120, 220]);
  static readonly thinking = new KunAnimationSpec(8, [150, 150, 150, 150, 150, 280]);
}

function getAgentBubble(state: string): string | undefined {
  switch (state) {
    case 'working': return '努力工作中…';
    case 'thinking': return '思考中…';
    case 'waiting': return '在等你回复哦~';
    case 'failed': return '呜…出错了 (._.)';
    case 'idle': return '休息中~ 有事叫我';
    case 'completed': return '完成啦！你干嘛~哎哟';
    default: return undefined;
  }
}

@Entry
@Component
struct FloatWindowPage {
  @State visualState: string = 'idle';
  @State avatarSkin: string = 'cat';
  @State bubbleText: string = '休息中~ 有事叫我';
  @State kunFrame: number = 0;

  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private catAnimation: AnimationItem | undefined = undefined;
  private readonly animationName: string = 'float_cat_animation';
  private requestedAsset: string = '';
  private loadedAsset: string = '';
  private catCanvasReady: boolean = false;
  private disposed: boolean = false;
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private bubbleTimer: number = -1;
  private kunTimer: number = -1;
  private longPressTimer: number = -1;
  private clickTimer: number = -1;
  private interactionUntil: number = 0;
  private commandOverrideUntil: number = 0;
  private interactionState: string = '';
  private commandState: string = '';
  private baseAgentState: string = 'idle';
  private celebrateWithJump: boolean = false;

  private isTouchActive: boolean = false;
  private isDragging: boolean = false;
  private longPressTriggered: boolean = false;
  private talkModeStartedByAvatar: boolean = false;
  private dragStartDisplayX: number = 0;
  private dragStartDisplayY: number = 0;
  private dragVpToPxScale: number = 1;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;
  private lastTapAtMs: number = 0;

  aboutToAppear(): void {
    this.disposed = false;
    this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    this.avatarSkin = this.runtime?.prefs.getAvatarSkin() || 'cat';
    this.baseAgentState = this.runtime?.chatController.avatarAgentState || 'idle';
    this.statusTimer = setInterval(() => this.tickState(), 200);
    if (this.runtime) {
      this.runtime.chatController.onAvatarCommand = (payloadJson: string) => this.handleAvatarCommand(payloadJson);
      this.runtime.avatarCommandSink = (payloadJson: string) => this.handleAvatarCommand(payloadJson);
    }
    this.refreshVisualState();
  }

  private tickState(): void {
    this.syncSkin();
    const now = Date.now();
    if (this.runtime) {
      const nextAgentState = this.normalizeState(this.runtime.chatController.avatarAgentState);
      if (nextAgentState !== this.baseAgentState) {
        this.baseAgentState = nextAgentState;
        if (nextAgentState === 'completed') {
          this.celebrateWithJump = !this.celebrateWithJump;
        }
      }
    }
    if (this.interactionState !== '' && now >= this.interactionUntil) this.interactionState = '';
    if (this.commandState !== '' && now >= this.commandOverrideUntil) this.commandState = '';
    this.refreshVisualState();
  }

  private syncSkin(): void {
    const selected = AppStorage.get<string>('avatarSkin') || this.runtime?.prefs.getAvatarSkin() || 'cat';
    if (selected === this.avatarSkin) return;
    this.avatarSkin = selected === 'kun' ? 'kun' : 'cat';
    this.kunFrame = 0;
    this.destroyCatAnimation();
    if (this.avatarSkin === 'cat') void this.loadCatAnimation();
    else this.scheduleKunFrame();
  }

  private normalizeState(state: string | undefined): string {
    switch (state) {
      case 'working': case 'thinking': case 'waiting': case 'failed': case 'idle':
      case 'completed': case 'listening': case 'speaking': case 'interacting':
      case 'recording': case 'dragLeft': case 'dragRight':
        return state;
      case 'happy': return 'completed';
      case 'confused': return 'thinking';
      default: return 'idle';
    }
  }

  private refreshVisualState(): void {
    const now = Date.now();
    const next = this.interactionState !== '' && now < this.interactionUntil
      ? this.interactionState
      : this.commandState !== '' && now < this.commandOverrideUntil
        ? this.commandState
        : this.baseAgentState;
    this.setVisualState(next);
  }

  private setVisualState(state: string): void {
    const normalized = this.normalizeState(state);
    if (normalized === this.visualState) return;
    this.visualState = normalized;
    this.kunFrame = 0;
    const bubble = getAgentBubble(normalized);
    if (bubble) this.setStatusBubble(bubble);
    if (this.avatarSkin === 'cat') void this.loadCatAnimation();
    else this.scheduleKunFrame();
    hilog.info(DOMAIN, TAG, 'avatar visual state -> %{public}s', normalized);
  }

  private getLottieAsset(): string {
    switch (this.visualState) {
      case 'listening': return 'cat-listening.json';
      case 'working': case 'dragLeft': case 'dragRight': return 'cat-working.json';
      case 'thinking': case 'recording': case 'failed': return 'cat-thinking.json';
      case 'speaking': case 'interacting': case 'completed': return 'cat-speaking.json';
      default: return 'cat-idle.json';
    }
  }

  private getKunAnimation(): KunAnimationSpec {
    switch (this.visualState) {
      case 'working': return KunAnimations.working;
      case 'thinking': return KunAnimations.thinking;
      case 'waiting': case 'listening': return KunAnimations.waiting;
      case 'failed': return KunAnimations.failed;
      case 'completed': return this.celebrateWithJump ? KunAnimations.jump : KunAnimations.wave;
      case 'interacting': case 'recording': return KunAnimations.wave;
      case 'dragLeft': return KunAnimations.runLeft;
      case 'dragRight': return KunAnimations.runRight;
      default: return KunAnimations.idle;
    }
  }

  private async loadCatAnimation(): Promise<void> {
    if (this.avatarSkin !== 'cat' || !this.catCanvasReady || this.disposed) return;
    const asset = this.getLottieAsset();
    if (asset === this.loadedAsset || asset === this.requestedAsset) return;
    this.requestedAsset = asset;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const data = await context.resourceManager.getRawFileContent(asset);
      if (this.disposed || this.avatarSkin !== 'cat' || !this.catCanvasReady || this.requestedAsset !== asset) return;
      const decoder = new util.TextDecoder('utf-8');
      const animationData = JSON.parse(decoder.decode(data)) as Object;
      this.destroyCatAnimation();
      this.catAnimation = lottie.loadAnimation({
        container: this.catCanvasContext, renderer: 'canvas', loop: true, autoplay: false,
        name: this.animationName, contentMode: 'Contain', animationData: animationData,
      });
      this.loadedAsset = asset;
      this.catAnimation.addEventListener('DOMLoaded', () => {
        if (!this.disposed && this.avatarSkin === 'cat' && this.loadedAsset === asset) {
          this.catAnimation?.resize();
          this.catAnimation?.play();
        }
      });
    } catch (err) {
      if (this.requestedAsset === asset) this.requestedAsset = '';
      hilog.error(DOMAIN, TAG, 'failed to load Lottie %{public}s: %{public}s', asset,
        err instanceof Error ? err.message : String(err));
    }
  }

  private destroyCatAnimation(): void {
    try { lottie.destroy(this.animationName); } catch (_) { /* Not attached yet. */ }
    this.catAnimation = undefined;
    this.loadedAsset = '';
  }

  private scheduleKunFrame(): void {
    if (this.kunTimer !== -1) clearTimeout(this.kunTimer);
    this.kunTimer = -1;
    if (this.avatarSkin !== 'kun' || this.disposed) return;
    const spec = this.getKunAnimation();
    const delay = spec.frameDurations[this.kunFrame] || 150;
    this.kunTimer = setTimeout(() => {
      this.kunFrame = (this.kunFrame + 1) % spec.frameDurations.length;
      this.scheduleKunFrame();
    }, delay);
  }

  private kunImageX(): string {
    return `${(AVATAR_SIZE - KUN_FRAME_WIDTH) / 2 - this.kunFrame * KUN_FRAME_WIDTH}px`;
  }

  private kunImageY(): string {
    return `${-this.getKunAnimation().row * AVATAR_SIZE}px`;
  }

  private setStatusBubble(text: string): void {
    if (this.bubbleTimer !== -1) clearTimeout(this.bubbleTimer);
    this.bubbleTimer = -1;
    this.bubbleText = text;
  }

  private setTransientBubble(text: string, durationMs: number = INTERACTION_MS): void {
    this.bubbleText = text;
    if (this.bubbleTimer !== -1) clearTimeout(this.bubbleTimer);
    this.bubbleTimer = setTimeout(() => {
      this.bubbleTimer = -1;
      this.bubbleText = getAgentBubble(this.baseAgentState) || getAgentBubble('idle') || '';
    }, durationMs);
  }

  private beginInteraction(state: string, bubble: string, durationMs: number = INTERACTION_MS): void {
    this.interactionState = state;
    this.interactionUntil = Date.now() + durationMs;
    this.setTransientBubble(bubble, durationMs);
    this.refreshVisualState();
  }

  private handleAvatarCommand(payloadJson: string): void {
    try {
      const cmd = JSON.parse(payloadJson) as Record<string, Object>;
      const action = cmd.action as string | undefined;
      const params = (cmd.params as Record<string, Object>) || {};
      if (action === 'sequence') {
        const steps = params.steps as Object[] | undefined;
        if (Array.isArray(steps)) this.runSequence(steps);
      } else if (action === 'setBubble' && params.text) {
        this.setTransientBubble(params.text as string, 5000);
      } else if (action === 'clearBubble') {
        this.setStatusBubble(getAgentBubble(this.baseAgentState) || getAgentBubble('idle') || '');
      } else if (action === 'setState' && params.state) {
        this.commandState = this.normalizeState(params.state as string);
        this.commandOverrideUntil = Date.now() + COMMAND_OVERRIDE_MS;
        this.refreshVisualState();
      } else if (action === 'moveTo' && params.x !== undefined && params.y !== undefined) {
        void FloatWindowManager.getInstance().moveWindowTo(params.x as number, params.y as number);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'avatar.command parse failed: %{public}s', err instanceof Error ? err.message : String(err));
    }
  }

  private runSequence(steps: Object[]): void {
    let delay = 0;
    for (const step of steps) {
      const item = step as Record<string, Object>;
      delay += (item.delayMs as number) || 0;
      setTimeout(() => this.handleAvatarCommand(JSON.stringify({
        action: item.action as string | undefined,
        params: (item.params as Record<string, Object>) || {},
      })), delay);
    }
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.statusTimer !== -1) clearInterval(this.statusTimer);
    if (this.bubbleTimer !== -1) clearTimeout(this.bubbleTimer);
    if (this.kunTimer !== -1) clearTimeout(this.kunTimer);
    if (this.longPressTimer !== -1) clearTimeout(this.longPressTimer);
    if (this.clickTimer !== -1) clearTimeout(this.clickTimer);
    this.statusTimer = -1; this.bubbleTimer = -1; this.kunTimer = -1;
    this.longPressTimer = -1; this.clickTimer = -1; this.requestedAsset = '';
    this.destroyCatAnimation();
  }

  build() {
    Column() {
      Row() {
        if (this.bubbleText !== '') {
          Text(this.bubbleText)
            .fontSize('24px')
            .fontColor('#3D2D18')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '260px' })
            .padding({ left: '10px', right: '10px', top: '10px', bottom: '10px' })
            .backgroundColor('#FFFFFFFF')
            .border({ width: '1px', color: '#CCCCCC' })
            .borderRadius('8px')
        }
      }
        .width(AVATAR_SIZE_PX)
        .height(BUBBLE_AREA_HEIGHT_PX)
        .justifyContent(FlexAlign.Start)
        .alignItems(VerticalAlign.Center)
        .padding({ left: '10px', right: '10px' })
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.avatarSkin === 'cat') {
          Canvas(this.catCanvasContext)
            .width(AVATAR_SIZE_PX)
            .height(AVATAR_SIZE_PX)
            .onReady(() => {
              this.catCanvasReady = true;
              this.catCanvasContext.imageSmoothingEnabled = true;
              this.catCanvasContext.imageSmoothingQuality = 'high';
              void this.loadCatAnimation();
            })
        } else {
          Stack({ alignContent: Alignment.TopStart }) {
            Image($rawfile('kun-spritesheet.webp'))
              .width(`${KUN_SHEET_WIDTH}px`)
              .height(`${KUN_SHEET_HEIGHT}px`)
              .objectFit(ImageFit.Fill)
              .position({ x: this.kunImageX(), y: this.kunImageY() })
              .interpolation(ImageInterpolation.None)
              // Float-window movement is handled by onTouch below, never by system drag-and-drop.
              .draggable(false)
          }
          .width(AVATAR_SIZE_PX)
          .height(AVATAR_SIZE_PX)
          .clip(true)
        }
      }
      .width(AVATAR_SIZE_PX)
      .height(AVATAR_SIZE_PX)
    }
    .width(AVATAR_SIZE_PX)
    .height(FLOAT_WINDOW_HEIGHT_PX)
    .backgroundColor(Color.Transparent)
    .clip(true)
    .draggable(false)
    .onTouch((event: TouchEvent) => this.handleTouch(event))
  }

  private handleTouch(event: TouchEvent): void {
    const manager = FloatWindowManager.getInstance();
    if (event.type === TouchType.Down && event.touches.length > 0) {
      const touch = event.touches[0];
      const position = manager.getWindowPosition();
      this.isTouchActive = true; this.isDragging = false; this.longPressTriggered = false;
      this.dragStartDisplayX = touch.globalDisplayX ?? touch.displayX;
      this.dragStartDisplayY = touch.globalDisplayY ?? touch.displayY;
      this.dragVpToPxScale = this.getUIContext().vp2px(1);
      this.dragStartWindowX = position[0]; this.dragStartWindowY = position[1];
      if (this.longPressTimer !== -1) clearTimeout(this.longPressTimer);
      this.longPressTimer = setTimeout(() => this.startVoiceInteraction(), LONG_PRESS_MS);
      return;
    }
    if (event.type === TouchType.Move && this.isTouchActive && event.touches.length > 0) {
      const touch = event.touches[0];
      const displayX = touch.globalDisplayX ?? touch.displayX;
      const displayY = touch.globalDisplayY ?? touch.displayY;
      const deltaX = (displayX - this.dragStartDisplayX) * this.dragVpToPxScale;
      const deltaY = (displayY - this.dragStartDisplayY) * this.dragVpToPxScale;
      if (!this.isDragging && (Math.abs(deltaX) >= DRAG_THRESHOLD_PX || Math.abs(deltaY) >= DRAG_THRESHOLD_PX)) {
        this.isDragging = true;
        if (this.longPressTimer !== -1) clearTimeout(this.longPressTimer);
        this.longPressTimer = -1;
      }
      if (this.isDragging) {
        this.updateDragVisual(deltaX);
        void manager.moveWindowTo(this.dragStartWindowX + deltaX, this.dragStartWindowY + deltaY);
      }
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      if (this.longPressTimer !== -1) clearTimeout(this.longPressTimer);
      this.longPressTimer = -1;
      const wasDragging = this.isDragging;
      const wasLongPress = this.longPressTriggered;
      this.isTouchActive = false; this.isDragging = false;
      if (wasLongPress) this.stopVoiceInteraction();
      if (!wasDragging && !wasLongPress && event.type === TouchType.Up) this.handleTap();
    }
  }

  private updateDragVisual(deltaX: number): void {
    const nextState = deltaX < 0 ? 'dragLeft' : 'dragRight';
    if (this.interactionState !== nextState) {
      this.beginInteraction(nextState, '呜哇~ 别拽我！', 1000);
      return;
    }
    this.interactionUntil = Date.now() + 1000;
  }

  private startVoiceInteraction(): void {
    if (!this.isTouchActive || this.isDragging) return;
    this.longPressTriggered = true;
    if (this.runtime && !this.runtime.talkModeManager.isEnabled) {
      this.runtime.talkModeManager.setEnabled(true);
      this.talkModeStartedByAvatar = true;
    }
    this.beginInteraction('listening', '我在听~', 60000);
  }

  private stopVoiceInteraction(): void {
    if (this.talkModeStartedByAvatar) this.runtime?.talkModeManager.setEnabled(false);
    this.talkModeStartedByAvatar = false;
    this.interactionState = ''; this.interactionUntil = 0;
    this.refreshVisualState();
  }

  private handleTap(): void {
    const now = Date.now();
    if (now - this.lastTapAtMs <= DOUBLE_TAP_MS) {
      if (this.clickTimer !== -1) clearTimeout(this.clickTimer);
      this.clickTimer = -1; this.lastTapAtMs = 0;
      this.beginInteraction('thinking', '正在读取当前页面…', 30000);
      void this.captureCurrentScreenMemory();
      return;
    }
    this.lastTapAtMs = now;
    this.clickTimer = setTimeout(() => {
      this.clickTimer = -1; this.lastTapAtMs = 0;
      this.beginInteraction('interacting', '诶嘿~');
    }, DOUBLE_TAP_MS);
  }

  private async captureCurrentScreenMemory(): Promise<void> {
    try {
      if (!this.runtime) throw new Error('Bonio runtime is unavailable');
      await this.runtime.captureAvatarMemory();
      this.beginInteraction('completed', '已交给 Bonio 整理记忆~', 4000);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const bubble = message.includes('SCREEN_AWARENESS_DISABLED')
        ? '请先在设置开启屏幕感知~'
        : '当前页面暂时无法读取~';
      hilog.warn(DOMAIN, TAG, 'SmartEdge memory capture failed: %{public}s', message);
      this.beginInteraction('failed', bubble, 4000);
    }
  }
}
