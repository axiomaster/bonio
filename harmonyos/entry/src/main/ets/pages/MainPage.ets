import { NodeRuntime } from '../node/NodeRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatTab } from './ChatTab';
import { CanvasTab } from './CanvasTab';
import { ServerTab } from './ServerTab';
import { SettingsTab } from './SettingsTab';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  @State isConnected: boolean = false;
  @State serverName: string = '';
  @State statusText: string = 'Offline';

  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private controller: TabsController = new TabsController();

  async aboutToAppear() {
    // Wait for NodeRuntime to be initialized by EntryAbility
    let retries = 0;
    const maxRetries = 10;
    while (retries < maxRetries) {
      this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
      if (this.runtime) break;
      hilog.info(0x3D00, 'MainPage', `NodeRuntime not found, retrying ${retries + 1}/${maxRetries}...`);
      await new Promise<void>(resolve => setTimeout(resolve, 500));
      retries++;
    }

    if (this.runtime) {
      this.serverName = this.runtime.serverName || '';
      this.statusText = this.runtime.statusText;
      this.isConnected = this.runtime.isConnected;

      this.statusTimer = setInterval(() => {
        if (this.runtime) {
          this.isConnected = this.runtime.isConnected;
          this.statusText = this.runtime.statusText;
          this.serverName = this.runtime.serverName || '';
        }
      }, 500);
    } else {
      this.statusText = 'NodeRuntime not found';
    }
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  @Builder TabBarIcon(icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentIndex === index ? '#0A59F7' : '#999999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.Start, controller: this.controller, index: this.currentIndex }) {
        TabContent() {
          ChatTab({ runtime: this.runtime })
        }
        .tabBar(this.TabBarIcon($r('app.media.ic_tab_chat'), 0))

        TabContent() {
          CanvasTab({ runtime: this.runtime, serverName: this.serverName, statusText: this.statusText })
        }
        .tabBar(this.TabBarIcon($r('app.media.ic_tab_screen'), 1))

        TabContent() {
          ServerTab({ runtime: this.runtime })
        }
        .tabBar(this.TabBarIcon($r('app.media.ic_tab_server'), 2))

        TabContent() {
          SettingsTab({ runtime: this.runtime, onDisconnect: () => {
            this.runtime?.disconnect();
          }})
        }
        .tabBar(this.TabBarIcon($r('app.media.ic_tab_settings'), 3))
      }
      .barHeight(48)
      .barBackgroundColor('#F8F8F8')
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
  }
}
