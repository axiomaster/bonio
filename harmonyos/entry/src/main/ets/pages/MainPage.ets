import { NodeRuntime } from '../node/NodeRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { CanvasTab } from './CanvasTab';
import { ChatTab } from './ChatTab';
import { VoiceTab } from './VoiceTab';
import { SettingsTab } from './SettingsTab';

@Entry
@Component
struct MainPage {
  @State currentIndex: number = 0;
  @State isConnected: boolean = true;
  @State serverName: string = '';
  @State statusText: string = 'Connected';

  private runtime: NodeRuntime | undefined = undefined;
  private statusTimer: number = -1;
  private controller: TabsController = new TabsController();

  aboutToAppear() {
    this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    if (!this.runtime) {
      router.replaceUrl({ url: 'pages/LoginPage' });
      return;
    }

    this.serverName = this.runtime.serverName || '';
    this.statusText = this.runtime.statusText;

    this.statusTimer = setInterval(() => {
      if (this.runtime) {
        this.isConnected = this.runtime.isConnected;
        this.statusText = this.runtime.statusText;
        this.serverName = this.runtime.serverName || '';
        if (!this.isConnected) {
          // If disconnected, go back to login
          this.navigateToLogin();
        }
      }
    }, 500);
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  private navigateToLogin() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  @Builder TabBarItem(title: string, icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === index ? '#0A59F7' : '#999999')
      Text(title)
        .fontSize(11)
        .fontColor(this.currentIndex === index ? '#0A59F7' : '#999999')
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 2 })
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
          CanvasTab({ runtime: this.runtime, serverName: this.serverName, statusText: this.statusText })
        }
        .tabBar(this.TabBarItem('Canvas', $r('app.media.ic_tab_canvas'), 0))

        TabContent() {
          ChatTab({ runtime: this.runtime })
        }
        .tabBar(this.TabBarItem('Chat', $r('app.media.ic_tab_chat'), 1))

        TabContent() {
          VoiceTab({ runtime: this.runtime })
        }
        .tabBar(this.TabBarItem('Voice', $r('app.media.ic_tab_voice'), 2))

        TabContent() {
          SettingsTab({ runtime: this.runtime, onDisconnect: () => {
            this.runtime?.disconnect();
            this.navigateToLogin();
          }})
        }
        .tabBar(this.TabBarItem('Settings', $r('app.media.ic_tab_settings'), 3))
      }
      .barHeight(56)
      .barBackgroundColor('#F8F8F8')
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
  }
}
