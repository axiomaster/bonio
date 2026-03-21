import { NodeRuntime } from '../node/NodeRuntime';

@Component
export struct ServerTab {
  runtime: NodeRuntime | undefined = undefined;

  @State manualHost: string = '';
  @State manualPort: string = '18789';
  @State manualToken: string = '';
  @State manualTls: boolean = false;
  @State isConnected: boolean = false;
  @State statusText: string = 'Offline';
  @State isConnecting: boolean = false;

  private statusTimer: number = -1;

  aboutToAppear() {
    if (this.runtime) {
      this.manualHost = this.runtime.prefs.getManualHost() || '';
      this.manualPort = this.runtime.prefs.getManualPort().toString() || '18789';
      this.manualToken = this.runtime.prefs.getGatewayToken() || '';
      this.manualTls = this.runtime.prefs.getManualTls();
      this.refreshStatus();
      this.statusTimer = setInterval(() => { this.refreshStatus(); }, 500);
    }
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  private refreshStatus() {
    if (this.runtime) {
      this.isConnected = this.runtime.isConnected;
      this.statusText = this.runtime.statusText;
      if (this.isConnecting && (this.isConnected || this.statusText.toLowerCase().includes('fail') || this.statusText.toLowerCase().includes('error'))) {
        this.isConnecting = false;
      }
    }
  }

  private doConnect() {
    if (!this.runtime) return;
    this.runtime.prefs.setManualHost(this.manualHost);
    this.runtime.prefs.setManualPort(parseInt(this.manualPort, 10));
    this.runtime.prefs.setGatewayToken(this.manualToken);
    this.runtime.prefs.setManualTls(this.manualTls);
    this.runtime.connectManual();
    this.isConnecting = true;
  }

  private doDisconnect() {
    if (!this.runtime) return;
    this.runtime.disconnect();
    this.isConnected = false;
    this.statusText = 'Disconnected';
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // Header
          Text('SERVER')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0A59F7')
            .width('100%')
            .margin({ bottom: 4 })
          Text('Connection Settings')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .width('100%')
            .margin({ bottom: 4 })
          Text('Manage your gateway connection endpoint and tokens.')
            .fontSize(13)
            .fontColor('#999999')
            .width('100%')
            .margin({ bottom: 16 })

          Divider().color('#E0E0E0').margin({ bottom: 16 })

          // Gateway Connection Card
          Column() {
            Text('Gateway Connection')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0A59F7')
              .margin({ bottom: 8 })

            Text(`Status: ${this.statusText}`)
              .fontSize(13)
              .fontColor(this.isConnected ? '#2ECC71' : '#333333')
              .margin({ bottom: 12 })

            TextInput({ placeholder: 'Gateway Host', text: this.manualHost })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .margin({ bottom: 10 })
              .backgroundColor('#F5F5F5')
              .fontColor('#333333')
              .placeholderColor('#999999')
              .onChange((value: string) => { this.manualHost = value; })

            TextInput({ placeholder: 'Port', text: this.manualPort })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .type(InputType.Number)
              .margin({ bottom: 10 })
              .backgroundColor('#F5F5F5')
              .fontColor('#333333')
              .placeholderColor('#999999')
              .onChange((value: string) => { this.manualPort = value; })

            TextInput({ placeholder: 'Token', text: this.manualToken })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .type(InputType.Password)
              .margin({ bottom: 10 })
              .backgroundColor('#F5F5F5')
              .fontColor('#333333')
              .placeholderColor('#999999')
              .onChange((value: string) => { this.manualToken = value; })

            Row() {
              Text('Enable TLS')
                .fontSize(14)
                .fontColor('#333333')
                .fontWeight(FontWeight.Medium)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.manualTls })
                .selectedColor('#0A59F7')
                .onChange((isOn: boolean) => { this.manualTls = isOn; })
            }
            .width('100%')
            .height(40)
            .margin({ bottom: 12 })

            Button(this.isConnected ? 'Disconnect' : (this.isConnecting ? 'Connecting...' : 'Connect'))
              .width('100%')
              .height(44)
              .borderRadius(12)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(this.isConnected ? '#E53935' : '#0A59F7')
              .fontColor(Color.White)
              .enabled(!this.isConnecting)
              .onClick(() => {
                if (this.isConnected) {
                  this.doDisconnect();
                } else {
                  this.doConnect();
                }
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.White)
          .border({ width: 1, color: '#E0E0E0' })
        }
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}
