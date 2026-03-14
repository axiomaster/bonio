import { webview } from '@kit.ArkWeb';
import { NodeRuntime } from '../node/NodeRuntime';

@Component
export struct CanvasTab {
  runtime: NodeRuntime | undefined = undefined;
  @Prop serverName: string = '';
  @Prop statusText: string = '';
  controller: webview.WebviewController = new webview.WebviewController();

  // No longer attaching in aboutToAppear to avoid association error
  aboutToAppear() {
  }

  build() {
    Column() {
      // Status bar
      Row() {
        Text("●")
          .fontSize(10)
          .fontColor('#4CAF50')
          .margin({ right: 8 })
        Text(this.serverName ? `Connected to ${this.serverName}` : this.statusText)
          .fontSize(14)
          .fontColor('#666666')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#F5F5F5')

      // Real Canvas Web component
      Web({
        src: $rawfile('scaffold.html'),
        controller: this.controller
      })
      .id("canvas_web_comp")
      .layoutWeight(1)
      .width('100%')
      .domStorageAccess(true)
      .javaScriptAccess(true)
      .imageAccess(true)
      .onControllerAttached(() => {
        if (this.runtime) {
          this.runtime.canvas.attach(this.controller);
        }
      })
      .onPageEnd(() => {
        // Initial sync if needed
      })
    }
    .width('100%')
    .height('100%')
  }
}
