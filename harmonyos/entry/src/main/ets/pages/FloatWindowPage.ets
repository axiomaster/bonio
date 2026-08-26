import { hilog } from '@kit.PerformanceAnalysisKit';
import { NodeRuntime } from '../node/NodeRuntime';
import { FloatWindowManager } from '../common/FloatWindowManager';

const DOMAIN = 0x3D00;
const TAG = 'FloatWindowPage';

@Entry
@Component
struct FloatWindowPage {
  @State agentState: string = 'idle';
  @State blinkMarker: boolean = false;
  @State bubbleText: string = '';
  private bubbleTimer: number = -1;
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
          }
        }
      }, 1000);

      // DSH refactor: consume server-driven avatar.command events.
      if (this.runtime.chatController) {
        this.runtime.chatController.onAvatarCommand = (payloadJson: string) => {
          this.handleAvatarCommand(payloadJson);
        };
      }
    }
    this.blinkTimer = setInterval(() => {
      this.blinkMarker = !this.blinkMarker;
    }, 1200);
  }

  private handleAvatarCommand(payloadJson: string) {
    try {
      const cmd = JSON.parse(payloadJson) as Record<string, Object>;
      const action = cmd.action as string | undefined;
      const params = (cmd.params as Record<string, Object>) || {};
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
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'avatar.command parse failed: %{public}s', e instanceof Error ? e.message : String(e));
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
  }

  build() {
    Stack() {
      this.NativeCatAvatar()
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

  @Builder
  NativeCatAvatar() {
    Stack() {
      // DSH refactor: server-driven speech bubble (avatar.command setBubble).
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
    .backgroundColor('#FFF7E4')
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
