import { SecurePrefs } from '../common/SecurePrefs';
import { DeviceIdentityStore } from '../common/DeviceIdentityStore';
import { NodeRuntime } from '../node/NodeRuntime';
import { ChatSheet } from './ChatSheet';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State message: string = 'Initializing...';
  @State deviceId: string = 'Unknown';
  @State isConnected: boolean = false;
  @State showChat: boolean = false;

  @State manualHost: string = "";
  @State manualPort: string = "18789";
  @State manualToken: string = "";
  @State manualTls: boolean = false;
  
  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private readonly DOMAIN: number = 0x3D00;

  async aboutToAppear() {
    try {
      // TCP Header Sniffer removed
      // Retry mechanism to wait for EntryAbility to finish async initialization
      let retries = 0;
      const maxRetries = 10;
      while (retries < maxRetries) {
        this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
        if (this.runtime) break;
        
        hilog.info(0x3D00, 'testTag', `Index: NodeRuntime not found in AppStorage, retrying ${retries + 1}/${maxRetries}...`);
        await new Promise<void>(resolve => setTimeout(resolve, 500));
        retries++;
      }

      if (this.runtime) {
        this.deviceId = this.runtime.prefs.getInstanceId() || 'Unknown';
        this.message = this.runtime.statusText;
        this.manualHost = this.runtime.prefs.getManualHost() || "192.168.43.4";
        this.manualPort = this.runtime.prefs.getManualPort().toString() || "18789";
        this.manualToken = this.runtime.prefs.getGatewayToken() || "lism";
        this.manualTls = this.runtime.prefs.getManualTls();
        
        // Simple polling for status updates to avoid large reactivity refactor in NodeRuntime for Phase 1
        this.statusTimer = setInterval(() => {
          if (this.runtime) {
            this.message = this.runtime.statusText;
            const wasConnected = this.isConnected;
            this.isConnected = this.runtime.isConnected;
            if (!wasConnected && this.isConnected) {
              this.showChat = true;
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
    }
  }

  build() {
    RelativeContainer() {
      Column() {
        Row() {
          Text("OpenClaw Node")
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
          
          Blank()
          
          Button("Settings")
            .type(ButtonType.Capsule)
            .fontSize(14)
            .onClick(() => {
              router.pushUrl({ url: 'pages/SettingsPage' });
            })
        }
        .width('90%')
        .margin({ bottom: 20, top: 20 })
          
        Text(`Status: ${this.message}`)
          .fontSize(16)
          .fontColor(this.isConnected ? Color.Green : Color.Orange)
          .margin({ bottom: 5 })

        Text(`Device ID: ${this.deviceId}`)
          .fontSize(14)
          .fontColor(Color.Gray)
          .margin({ bottom: 30 })

        if (!this.isConnected) {
          TextInput({ placeholder: '192.168.1.x', text: this.manualHost })
            .width('80%')
            .margin({ bottom: 10 })
            .onChange((value: string) => {
              this.manualHost = value;
              this.runtime?.prefs.setManualHost(value);
            })

          TextInput({ placeholder: '8080', text: this.manualPort })
            .width('80%')
            .margin({ bottom: 10 })
            .type(InputType.Number)
            .onChange((value: string) => {
              this.manualPort = value;
              const port = parseInt(value, 10);
              if (!isNaN(port)) {
                this.runtime?.prefs.setManualPort(port);
              }
            })

          TextInput({ placeholder: 'Gateway Token', text: this.manualToken })
            .width('80%')
            .margin({ bottom: 20 })
            .onChange((value: string) => {
              this.manualToken = value;
              this.runtime?.prefs.setGatewayToken(value);
            })

          Row() {
            Text("Use TLS (wss://)")
              .fontSize(16)
            Toggle({ type: ToggleType.Switch, isOn: this.manualTls })
              .onChange((isOn: boolean) => {
                this.manualTls = isOn;
                this.runtime?.prefs.setManualTls(isOn);
              })
          }
          .width('80%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ bottom: 20 })

          Button('Connect to Gateway')
            .width('80%')
            .onClick(() => {
              this.runtime?.connectManual();
            })
        } else {
          Button('Disconnect')
            .width('80%')
            .backgroundColor(Color.Red)
            .margin({ bottom: 10 })
            .onClick(() => {
              this.runtime?.disconnect();
            })

          Button('Open Chat')
            .width('80%')
            .onClick(() => {
              this.showChat = true;
            })
            .bindSheet(this.showChat, this.ChatBuilder(), {
              height: SheetSize.LARGE,
              onDisappear: () => this.showChat = false
            })
        }
      }
      .alignRules({
        center: { anchor: '__container__', align: VerticalAlign.Center },
        middle: { anchor: '__container__', align: HorizontalAlign.Center }
      })
    }
    .height('100%')
    .width('100%')
  }

  @Builder ChatBuilder() {
    if (this.runtime) {
      ChatSheet({ controller: this.runtime.chatController })
    }
  }
}
