/**
 * FloatWindowPage — the global avatar host.
 *
 * With system_core signing (SYSTEM_FLOAT_WINDOW ACL) the pet lives in a real
 * system float window (TYPE_FLOAT) on top of every app.
 *
 * Rendering constraints discovered on this SDK's float windows:
 *  - @ohos/lottie canvas renderer cannot draw inside subwindow canvases
 *    (frame loop runs, clearRect works, path fills produce no pixels)
 *  - positioned/offset/margined ArkUI components are not visible in the
 *    subwindow, and even default-layout components (Circle/Text/Shape) get
 *    laid out unpredictably (pushed outside the visible area)
 *  - the ONLY reliable drawing path is a Canvas component + CanvasRendering
 *    Context2D calls (fillRect/arc/path fills verified pixel-perfect aligned
 *    to the window)
 *
 * Therefore the cat is hand-drawn on a 200x200 Canvas with 2D API calls and
 * re-rendered every 50ms by a JS timer (sine-wave animation: breathing,
 * blinking, tail sway, speaking mouth, working sway, thinking ear-drop).
 * The canvas is transparent; the yellow rounded background is the Stack.
 *
 * The avatar state is driven by:
 *   - avatar.command events from the server (setState/setBubble/moveTo/sequence)
 *   - on-device feature commands (health nags, notifications) via
 *     NodeRuntime.avatarCommandSink
 *   - chat activity (pending run -> thinking, streaming -> speaking)
 *   - connection status (disconnected -> working)
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { display } from '@kit.ArkUI';
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

  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private bubbleTimer: number = -1;
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private stateOverrideUntil: number = 0;
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
  }

  /** Start the redraw loop once the canvas is ready. */
  private startDrawLoop(): void {
    if (this.animTimer !== -1) return;
    this.animTimer = setInterval(() => {
      this.drawCat();
    }, 50);
    hilog.info(DOMAIN, TAG, 'avatar canvas draw loop started');
  }

  /** Hand-draw the cat on the 200x200 canvas (transparent bg, yellow Stack behind). */
  private drawCat(): void {
    const ctx = this.catCanvasContext;
    const t = Date.now();
    const st = this.agentState;
    // Canvas content is rendered at device dpr scale (1vp -> dpr px), so the
    // 200x200 design is scaled back to fill the window exactly.
    const dpr = display.getDefaultDisplaySync().densityPixels;
    ctx.save();
    ctx.scale(1 / dpr, 1 / dpr);

    // ---- animation params (sine waves) ----
    const breath = 1 + 0.03 * Math.sin((t / 800) * Math.PI);            // ~1.6s breathing
    const tailSwing = (st === 'idle' || st === 'listening')
      ? 8 * Math.sin((t / 1100) * Math.PI) : 0;                          // tail sway
    const bodySwing = (st === 'working' || st === 'speaking')
      ? 2.5 * Math.sin((t / 210) * Math.PI) : 0;                         // body sway
    const mouthOpen = (st === 'speaking') ? Math.max(0, Math.sin((t / 160) * Math.PI)) : 0;
    const earDrop = st === 'thinking' ? 9 : 0;
    const blinkPhase = (t % 3200) / 3200;                                // blink every 3.2s
    const eyeOpen = (blinkPhase < 0.05) ? 0.15 : 1;                      // 160ms blink

    ctx.clearRect(0, 0, 200, 200);

    // breathing scale around the body center (100, 112)
    ctx.save();
    ctx.translate(100, 112);
    ctx.scale(breath, breath);
    ctx.translate(-100, -112);
    // body sway around the feet
    ctx.translate(100, 165);
    ctx.rotate((bodySwing * Math.PI) / 180);
    ctx.translate(-100, -165);

    // ---- tail (behind body) ----
    ctx.save();
    ctx.translate(158, 140);
    ctx.rotate(((tailSwing + 26) * Math.PI) / 180);
    ctx.fillStyle = BODY_COLOR;
    ctx.strokeStyle = OUTLINE_COLOR;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(0, -18, 9, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.restore();

    // ---- ears (behind head) ----
    this.drawEar(ctx, 55, 52, -20 - earDrop);
    this.drawEar(ctx, 145, 52, 20 + earDrop);

    // ---- head ----
    ctx.fillStyle = BODY_COLOR;
    ctx.strokeStyle = OUTLINE_COLOR;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.ellipse(100, 108, 66, 56, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    // ---- eyes ----
    ctx.fillStyle = '#3D2D18';
    ctx.beginPath();
    ctx.ellipse(80, 100, 6, 7 * eyeOpen, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(120, 100, 6, 7 * eyeOpen, 0, 0, Math.PI * 2);
    ctx.fill();

    // ---- blush ----
    ctx.fillStyle = INNER_EAR_COLOR;
    ctx.globalAlpha = 0.55;
    ctx.beginPath();
    ctx.ellipse(62, 118, 10, 5.5, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(138, 118, 10, 5.5, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;

    // ---- nose ----
    ctx.fillStyle = OUTLINE_COLOR;
    ctx.beginPath();
    ctx.ellipse(100, 120, 4, 3, 0, 0, Math.PI * 2);
    ctx.fill();

    // ---- mouth ----
    ctx.strokeStyle = OUTLINE_COLOR;
    ctx.lineWidth = 2;
    if (mouthOpen > 0.15) {
      // open mouth while speaking
      ctx.fillStyle = '#C97B4A';
      ctx.beginPath();
      ctx.ellipse(100, 130, 9, 6 * mouthOpen, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    } else {
      // closed 'w' mouth
      ctx.beginPath();
      ctx.moveTo(88, 128);
      ctx.quadraticCurveTo(94, 133, 100, 128);
      ctx.quadraticCurveTo(106, 133, 112, 128);
      ctx.stroke();
    }

    // ---- whiskers ----
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(40, 112);
    ctx.lineTo(20, 106);
    ctx.moveTo(40, 120);
    ctx.lineTo(20, 124);
    ctx.moveTo(160, 112);
    ctx.lineTo(180, 106);
    ctx.moveTo(160, 120);
    ctx.lineTo(180, 124);
    ctx.stroke();

    ctx.restore();

    // ---- speech bubble (canvas-drawn; Text component not reliable here) ----
    if (this.bubbleText !== '') {
      this.drawBubble(ctx, this.bubbleText);
    }
    ctx.restore();
  }

  private drawEar(ctx: CanvasRenderingContext2D, x: number, y: number, angle: number): void {
    ctx.save();
    ctx.translate(x, y);
    ctx.rotate((angle * Math.PI) / 180);
    ctx.fillStyle = BODY_COLOR;
    ctx.strokeStyle = OUTLINE_COLOR;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.ellipse(0, -16, 13, 18, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = INNER_EAR_COLOR;
    ctx.beginPath();
    ctx.ellipse(0, -16, 7, 10, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  private drawBubble(ctx: CanvasRenderingContext2D, text: string): void {
    ctx.save();
    const w = Math.min(180, 24 + text.length * 7);
    const x = 10;
    const y = 4;
    ctx.fillStyle = '#FFFFFF';
    ctx.strokeStyle = '#CCCCCC';
    ctx.lineWidth = 1;
    // rounded rect
    ctx.beginPath();
    ctx.moveTo(x + 8, y);
    ctx.lineTo(x + w - 8, y);
    ctx.quadraticCurveTo(x + w, y, x + w, y + 8);
    ctx.lineTo(x + w, y + 30);
    ctx.quadraticCurveTo(x + w, y + 38, x + w - 8, y + 38);
    ctx.lineTo(x + 8, y + 38);
    ctx.quadraticCurveTo(x, y + 38, x, y + 30);
    ctx.lineTo(x, y + 8);
    ctx.quadraticCurveTo(x, y, x + 8, y);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = '#3D2D18';
    ctx.font = '12vp sans-serif';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(text.length > 24 ? text.slice(0, 23) + '...' : text, x + 10, y + 19);
    ctx.restore();
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
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer);
      this.animTimer = -1;
    }
  }

  build() {
    Stack() {
      // Canvas-drawn cat (transparent; yellow rounded bg on the Stack)
      Canvas(this.catCanvasContext)
        .width(200)
        .height(200)
        .onReady(() => {
          this.startDrawLoop();
        })
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
