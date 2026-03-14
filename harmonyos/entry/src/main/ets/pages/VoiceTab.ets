import { NodeRuntime } from '../node/NodeRuntime';

@Component
export struct VoiceTab {
  runtime: NodeRuntime | undefined = undefined;
  @State isListening: boolean = false;
  @State isSpeaking: boolean = false;
  @State statusText: string = "Off";
  @State talkModeEnabled: boolean = false;

  aboutToAppear() {
    this.updateState();
    if (this.runtime) {
      this.runtime.onChatUpdate = () => {
        this.updateState();
      };
    }
  }

  updateState() {
    if (!this.runtime) return;
    this.isListening = this.runtime.talkModeIsListening || this.runtime.voiceWakeIsListening;
    this.isSpeaking = this.runtime.talkModeIsSpeaking;
    this.statusText = this.runtime.talkModeIsListening ? this.runtime.talkModeStatusText : this.runtime.voiceWakeStatusText;
    this.talkModeEnabled = this.runtime.talkModeManager.isEnabled;
  }

  build() {
    Column() {
      // Header
      Row() {
        Text("Voice")
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(52)
      .padding({ left: 16 })
      .backgroundColor('#F5F5F5')

      // Voice Area
      Column() {
        // Orb display
        Column() {
          Image($r('app.media.ic_tab_voice'))
            .width(72)
            .height(72)
            .fillColor(this.isListening ? '#2196F3' : (this.isSpeaking ? '#4CAF50' : '#999999'))
        }
        .width(160)
        .height(160)
        .borderRadius(80)
        .backgroundColor(this.isListening ? '#E3F2FD' : (this.isSpeaking ? '#E8F5E9' : '#F5F5F5'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 24 })
        .shadow({ radius: this.isListening || this.isSpeaking ? 20 : 0, color: this.isListening ? '#402196F3' : '#404CAF50' })
        .onClick(() => {
          if (this.runtime) {
            const next = !this.runtime.talkModeManager.isEnabled;
            this.runtime.talkModeManager.setEnabled(next);
            this.updateState();
          }
        })

        Text(this.statusText)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isListening ? '#2196F3' : (this.isSpeaking ? '#4CAF50' : '#666666'))
          .textAlign(TextAlign.Center)
          .margin({ bottom: 8 })

        Text(this.talkModeEnabled ? "Talk Mode: ON" : "Talk Mode: OFF")
          .fontSize(14)
          .fontColor(this.talkModeEnabled ? '#2196F3' : '#999999')
          .margin({ bottom: 24 })

        Text("Tap the icon to toggle Talk Mode.\nWhen enabled, the assistant will listen\nand respond using voice.")
          .fontSize(12)
          .fontColor('#BBBBBB')
          .textAlign(TextAlign.Center)
          .lineHeight(18)
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}
