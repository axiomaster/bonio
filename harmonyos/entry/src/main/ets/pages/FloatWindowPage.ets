/**
 * FloatWindowPage — the global avatar host.
 *
 * With system_core signing (SYSTEM_FLOAT_WINDOW ACL) the pet lives in a real
 * system float window (TYPE_FLOAT) on top of every app.
 *
 * Avatar rendering: the lottie canvas renderer (@ohos/lottie 2.0.x) does not
 * draw inside float-window canvases on this SDK (verified: loop runs, clearRect
 * works, path fills produce no pixels), so the cat is drawn with plain ArkUI
 * components + property animations — guaranteed to render in a subwindow.
 *
 * The avatar state is driven by:
 *   - avatar.command events from the server (setState/setBubble/moveTo/sequence)
 *   - on-device feature commands (health nags, notifications) via
 *     NodeRuntime.avatarCommandSink
 *   - chat activity (pending run -> thinking, streaming -> speaking)
 *   - connection status (disconnected -> working)
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { NodeRuntime } from '../node/NodeRuntime';
import { FloatWindowManager } from '../common/FloatWindowManager';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowPage';
/** avatar.command setState overrides the derived state for this long. */
const STATE_OVERRIDE_MS = 8000;

// Palette (mirrors the lottie cat design)
const BODY_COLOR = '#F9D27D';
const OUTLINE_COLOR = '#6A4A1F';
const INNER_EAR_COLOR = '#F5A9B8';

@Entry
@Component
struct FloatWindowPage {
  @State agentState: string = 'idle';
  @State bubbleText: string = '';

  // ---- property-animation state ----
  @State breathScale: number = 1;        // idle breathing
  @State eyeScaleY: number = 1;          // blink
  @State bodySwing: number = 0;          // working/speaking sway (deg)
  @State mouthScaleY: number = 1;        // speaking mouth open/close
  @State earDrop: number = 0;            // thinking: ears droop (deg)
  @State tailAngle: number = 0;          // idle tail sway
  private blinkPhase: number = 0;

  private bubbleTimer: number = -1;
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private stateOverrideUntil: number = 0;
  private blinkTimer: number = -1;
  private animTimer: number = -1;
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

    // ---- animation loop: JS-timer driven @State updates (subwindow-safe) ----
    this.animTimer = setInterval(() => {
      this.tickAnimations();
    }, 50);
    // Blink every ~3.2s (phase-based)
    this.blinkTimer = setInterval(() => {
      this.blinkPhase = Date.now();
    }, 3200);
  }

  /** 50ms animation tick: drive body/ear/mouth/tail @State with sine waves. */
  private tickAnimations(): void {
    const t = Date.now() % 100000;
    const st = this.agentState;
    // Breathing ~1.6s period
    this.breathScale = 1 + 0.035 * Math.sin((t / 1600) * Math.PI * 2);
    // Tail sway ~2.2s period (base + state factor)
    this.tailAngle = (7 + 7 * Math.sin((t / 2200) * Math.PI * 2)) * this.animFactor('tail');
    // Body sway for working/speaking ~0.42s period
    this.bodySwing = 2.5 * Math.sin((t / 420) * Math.PI * 2) * this.animFactor('sway');
    // Mouth for speaking ~0.32s period
    this.mouthScaleY = 1 - 0.55 * Math.max(0, Math.sin((t / 320) * Math.PI * 2)) * this.animFactor('mouth');
    // Thinking: ears droop
    this.earDrop = st === 'thinking' ? 10 : 0;
    // Blink: close for 160ms after blinkPhase
    const blinkAge = t - (this.blinkPhase % 100000);
    if (blinkAge >= 0 && blinkAge < 160) {
      this.eyeScaleY = 0.1;
    } else {
      this.eyeScaleY = 1;
    }
  }

  /** 0 or 1 factor per state for a given motion channel. */
  private animFactor(channel: string): number {
    const st = this.agentState;
    if (channel === 'sway') return (st === 'working' || st === 'speaking') ? 1 : 0;
    if (channel === 'mouth') return st === 'speaking' ? 1 : 0;
    if (channel === 'tail') return (st === 'idle' || st === 'listening') ? 1 : 0;
    return 1;
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
      this.setAgentState(next);
    }
  }

  private setAgentState(state: string): void {
    this.agentState = state;
    hilog.info(DOMAIN, TAG, 'avatar state -> %{public}s', state);
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
        this.setAgentState(params.state as string);
        this.stateOverrideUntil = Date.now() + STATE_OVERRIDE_MS;
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
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer);
      this.animTimer = -1;
    }
  }

  build() {
    Stack() {
      // ---- Cat (ArkUI components + property animations) ----
      Stack() {
        // Tail (behind body)
        Ellipse()
          .width(30)
          .height(60)
          .fill(BODY_COLOR)
          .stroke(OUTLINE_COLOR)
          .strokeWidth(3)
          .position({ x: 158, y: 128 })
          .rotate({ angle: this.tailAngle + 30, centerX: 8, centerY: 0 })

        // Body group (breathing + sway)
        Stack() {
          // Ears (behind head)
          this.CatEar(38, 55, -22 - this.earDrop)
          this.CatEar(162, 55, 22 + this.earDrop)

          // Head
          Ellipse()
            .width(132)
            .height(112)
            .fill(BODY_COLOR)
            .stroke(OUTLINE_COLOR)
            .strokeWidth(4)
            .position({ x: 34, y: 34 })

          // Eyes
          Circle()
            .width(14)
            .height(16)
            .fill('#3D2D18')
            .position({ x: 68, y: 86 })
            .scale({ y: this.eyeScaleY })
          Circle()
            .width(14)
            .height(16)
            .fill('#3D2D18')
            .position({ x: 118, y: 86 })
            .scale({ y: this.eyeScaleY })

          // Blush
          Ellipse()
            .width(22)
            .height(12)
            .fill('#F5A9B8')
            .opacity(0.55)
            .position({ x: 52, y: 108 })
          Ellipse()
            .width(22)
            .height(12)
            .fill('#F5A9B8')
            .opacity(0.55)
            .position({ x: 126, y: 108 })

          // Nose
          Ellipse()
            .width(10)
            .height(7)
            .fill(OUTLINE_COLOR)
            .position({ x: 95, y: 108 })

          // Mouth (w shape via small ellipses)
          if (this.mouthScaleY >= 0.8) {
            Text('w')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(OUTLINE_COLOR)
              .position({ x: 86, y: 114 })
          } else {
            // Open mouth while speaking
            Ellipse()
              .width(22)
              .height(14)
              .fill('#C97B4A')
              .stroke(OUTLINE_COLOR)
              .strokeWidth(2)
              .position({ x: 89, y: 114 })
              .scale({ y: this.mouthScaleY * 2 })
          }

          // Whiskers
          this.Whisker(40, 100, -18, true)
          this.Whisker(40, 118, 18, true)
          this.Whisker(160, 100, 18, false)
          this.Whisker(160, 118, -18, false)
        }
        .width(200)
        .height(200)
        .scale({ x: this.breathScale, y: this.breathScale, centerX: 100, centerY: 110 })
        .rotate({ angle: this.bodySwing, centerX: 100, centerY: 150 })
      }
      .width(200)
      .height(200)

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
    .clip(true)
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
  CatEar(x: number, y: number, angle: number) {
    Stack() {
      Ellipse()
        .width(38)
        .height(52)
        .fill(BODY_COLOR)
        .stroke(OUTLINE_COLOR)
        .strokeWidth(4)
      Ellipse()
        .width(20)
        .height(28)
        .fill(INNER_EAR_COLOR)
        .position({ x: 9, y: 12 })
    }
    .width(38)
    .height(52)
    .position({ x: x, y: y })
    .rotate({ angle: angle, centerX: 19, centerY: 0 })
  }

  @Builder
  Whisker(x: number, y: number, angle: number, left: boolean) {
    Rect()
      .width(26)
      .height(2)
      .fill(OUTLINE_COLOR)
      .borderRadius(1)
      .position({ x: x, y: y })
      .rotate({ angle: angle })
      .translate({ x: left ? -13 : 13 })
  }
}
