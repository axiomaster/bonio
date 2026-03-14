import { NodeRuntime } from '../node/NodeRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct LoginPage {
  @State message: string = 'Offline';
  @State deviceId: string = 'Unknown';
  @State isConnecting: boolean = false;

  @State manualHost: string = "192.168.43.4";
  @State manualPort: string = "18789";
  @State manualToken: string = "lism";
  @State manualTls: boolean = false;

  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;

  async aboutToAppear() {
    try {
      let retries = 0;
      const maxRetries = 10;
      while (retries < maxRetries) {
        this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
        if (this.runtime) break;
        hilog.info(0x3D00, 'LoginPage', `NodeRuntime not found, retrying ${retries + 1}/${maxRetries}...`);
        await new Promise<void>(resolve => setTimeout(resolve, 500));
        retries++;
      }

      if (this.runtime) {
        this.deviceId = this.runtime.prefs.getInstanceId() || 'Unknown';
        this.manualHost = this.runtime.prefs.getManualHost() || "192.168.43.4";
        this.manualPort = this.runtime.prefs.getManualPort().toString() || "18789";
        this.manualToken = this.runtime.prefs.getGatewayToken() || "lism";
        this.manualTls = this.runtime.prefs.getManualTls();

        // Poll for connection status
        this.statusTimer = setInterval(() => {
          if (this.runtime) {
            this.message = this.runtime.statusText;
            if (this.runtime.isConnected) {
              this.navigateToMain();
            } else if (this.isConnecting && (this.message.toLowerCase().includes('failed') || this.message.toLowerCase().includes('error'))) {
              this.isConnecting = false;
            }
          }
        }, 500);

      } else {
        this.message = "NodeRuntime not found";
      }
    } catch (e) {
      this.message = `Init Failed: ${e instanceof Error ? e.message : String(e)}`;
    }
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  private navigateToMain() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    router.replaceUrl({ url: 'pages/MainPage' });
  }

  private doConnect() {
    if (!this.runtime) return;
    this.runtime.prefs.setManualHost(this.manualHost);
    this.runtime.prefs.setManualPort(parseInt(this.manualPort, 10));
    this.runtime.prefs.setGatewayToken(this.manualToken);
    this.runtime.prefs.setManualTls(this.manualTls);
    this.runtime.connectManual();
    this.isConnecting = true;
    this.message = 'Connecting...';
  }

  build() {
    Column() {
      // Top spacer
      Blank().height(60)

      // Logo area
      Image($r('app.media.openclaw_logo'))
        .width(120)
        .height(120)
        .margin({ bottom: 8 })

      Text("OpenClaw Node")
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')

      Text("v1.0.0-dev")
        .fontSize(14)
        .fontColor('#999999')
        .margin({ bottom: 40 })

      // Connection Form
      Column() {
        TextInput({ placeholder: 'Gateway Host', text: this.manualHost })
          .width('100%')
          .height(48)
          .borderRadius(12)
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.manualHost = value;
          })

        TextInput({ placeholder: 'Port', text: this.manualPort })
          .width('100%')
          .height(48)
          .borderRadius(12)
          .type(InputType.Number)
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.manualPort = value;
          })

        TextInput({ placeholder: 'Token', text: this.manualToken })
          .width('100%')
          .height(48)
          .borderRadius(12)
          .type(InputType.Password)
          .margin({ bottom: 12 })
          .onChange((value: string) => {
            this.manualToken = value;
          })

        Row() {
          Text("Enable TLS")
            .fontSize(16)
            .fontColor('#333333')
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.manualTls })
            .selectedColor('#0A59F7')
            .onChange((isOn: boolean) => {
              this.manualTls = isOn;
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 4, right: 4 })
        .margin({ bottom: 24 })
      }
      .width('85%')

      // Connect Button
      Button(this.isConnecting ? 'Connecting...' : 'Connect')
        .width('85%')
        .height(48)
        .borderRadius(24)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .backgroundColor('#0A59F7')
        .enabled(!this.isConnecting)
        .onClick(() => {
          this.doConnect();
        })

      // Status
      Text(this.message)
        .fontSize(14)
        .fontColor(this.message.includes('fail') || this.message.includes('error') ? '#E53935' : '#999999')
        .margin({ top: 20 })

      Text(`Device: ${this.deviceId}`)
        .fontSize(12)
        .fontColor('#BBBBBB')
        .margin({ top: 8 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }
}
