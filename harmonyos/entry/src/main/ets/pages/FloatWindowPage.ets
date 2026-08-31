/**
 * FloatWindowPage — the global avatar host.
 *
 * With system_core signing (SYSTEM_FLOAT_WINDOW ACL) the pet lives in a real
 * system float window (TYPE_FLOAT) on top of every app. The page plays the
 * lottie cat animations (resources/rawfile/cat-*.json) driven by:
 *   - avatar.command events from the server (setState/setBubble/moveTo/sequence)
 *   - on-device feature commands (health nags, notifications) via
 *     NodeRuntime.avatarCommandSink
 *   - chat activity (pending run -> thinking, streaming -> speaking)
 *   - connection status (disconnected -> working)
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { NodeRuntime } from '../node/NodeRuntime';
import { FloatWindowManager } from '../common/FloatWindowManager';
import lottie from '@ohos/lottie';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowPage';
/** avatar.command setState overrides the derived state for this long. */
const STATE_OVERRIDE_MS = 8000;

@Entry
@Component
struct FloatWindowPage {
  @State agentState: string = 'idle';
  @State bubbleText: string = '';
  private bubbleTimer: number = -1;
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private stateOverrideUntil: number = 0;
  private isDragging: boolean = false;
  private dragStartScreenX: number = 0;
  private dragStartScreenY: number = 0;
  private dragStartWindowX: number = 0;
  private dragStartWindowY: number = 0;

  // Lottie cat animation rendered into a Canvas (same pattern as the old ChatTab avatar)
  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private currentLottieAnim: string = 'float_cat_anim';
  private lastLoadedAsset: string = '';

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'Float window page appearing');
    this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (this.runtime) {
      this.statusTimer = setInterval(() => {
        if (this.runtime) {
          this.tickState();
        }
      }, 1000);

      // DSH refactor: consume server-driven avatar.command events.
      if (this.runtime.chatController) {
        this.runtime.chatController.onAvatarCommand = (payloadJson: string) => {
          this.handleAvatarCommand(payloadJson);
        };
      }

      // Phase 4: consume on-device feature avatar commands (health/notifications).
      this.runtime.avatarCommandSink = (payloadJson: string) => {
        this.handleAvatarCommand(payloadJson);
      };
    }
  }

  /** Derive the avatar state from chat activity / connection unless overridden. */
  private tickState(): void {
    if (Date.now() < this.stateOverrideUntil) return;
    const r = this.runtime;
    if (!r) return;
    const c = r.chatController;
    let next: string;
    if (c && c.pendingRunCount > 0) {
      next = 'thinking';
    } else if (c && c.streamingAssistantText !== undefined && c.streamingAssistantText.length > 0) {
      next = 'speaking';
    } else {
      next = r.isConnected ? 'idle' : 'working';
    }
    if (next !== this.agentState) {
      this.agentState = next;
      this.loadCatAnimation();
    }
  }

  private handleAvatarCommand(payloadJson: string) {
    try {
      const cmd = JSON.parse(payloadJson) as Record<string, Object>;
      const action = cmd.action as string | undefined;
      const params = (cmd.params as Record<string, Object>) || {};

      if (action === 'sequence') {
        const steps = params.steps as Object[] | undefined;
        if (Array.isArray(steps)) {
          this.runSequence(steps);
        }
        return;
      }

      if (action === 'setBubble' && params.text) {
        this.bubbleText = params.text as string;
        if (this.bubbleTimer !== -1) clearTimeout(this.bubbleTimer);
        this.bubbleTimer = setTimeout(() => {
          this.bubbleText = '';
          this.bubbleTimer = -1;
        }, 5000);
      } else if (action === 'clearBubble') {
        this.bubbleText = '';
      } else if (action === 'setState' && params.state) {
        this.agentState = params.state as string;
        this.stateOverrideUntil = Date.now() + STATE_OVERRIDE_MS;
        this.loadCatAnimation();
      } else if (action === 'moveTo' && params.x !== undefined && params.y !== undefined) {
        FloatWindowManager.getInstance().moveWindowTo(params.x as number, params.y as number);
      }
      // playSound / tts accepted; sound handled by the host app when present.
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'avatar.command parse failed: %{public}s', e instanceof Error ? e.message : String(e));
    }
  }

  private runSequence(steps: Object[]) {
    let delay = 0;
    for (const step of steps) {
      const s = step as Record<string, Object>;
      const stepAction = s.action as string | undefined;
      const stepParams = (s.params as Record<string, Object>) || {};
      const stepDelay = (s.delayMs as number) || 0;
      delay += stepDelay;
      setTimeout(() => {
        const payload = JSON.stringify({ action: stepAction, params: stepParams });
        this.handleAvatarCommand(payload);
      }, delay);
    }
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
    } catch (_e) { /* ignore if not loaded yet */ }
    lottie.loadAnimation({
      container: this.catCanvasContext,
      renderer: 'canvas',
      loop: true,
      autoplay: true,
      name: this.currentLottieAnim,
      path: asset,
    });
    hilog.info(DOMAIN, TAG, 'avatar animation -> %{public}s', asset);
  }

  aboutToDisappear() {
    hilog.info(DOMAIN, TAG, 'Float window page disappearing');
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (_e) { /* ignore */ }
    this.lastLoadedAsset = '';
  }

  build() {
    Stack() {
      // Lottie cat animation, driven by agentState (global avatar host)
      Canvas(this.catCanvasContext)
        .width(200)
        .height(200)
        .onReady(() => {
          this.loadCatAnimation();
        })

      // Speech bubble (avatar.command setBubble)
      if (this.bubbleText !== '') {
        Text(this.bubbleText)
          .fontSize(13)
          .fontColor('#3D2D18')
          .backgroundColor('#FFFFFF')
          .borderRadius(10)
          .padding(8)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(170)
          .margin({ top: -4 })
          .position({ x: 15, y: 0 })
      }
    }
    .width(200)
    .height(200)
    .backgroundColor('#FFF7E4')
    .borderRadius(24)
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
