import { ChatController } from '../node/chat/ChatController';
import { ChatMessage, ChatMessageContent, OutgoingAttachment } from '../node/chat/ChatModels';

@Component
export struct ChatSheet {
  controller: ChatController | undefined = undefined;
  @State messages: ChatMessage[] = [];
  @State inputText: string = "";
  @State isSending: boolean = false;
  @State thinkingLevel: string = "off";
  @State streamingText: string | undefined = undefined;
  @State errorText: string | undefined = undefined;

  private scroller: Scroller = new Scroller();

  aboutToAppear() {
    if (this.controller) {
      this.messages = [...this.controller.messages];
      this.thinkingLevel = this.controller.thinkingLevel;
      this.streamingText = this.controller.streamingAssistantText;
      this.errorText = this.controller.errorText;
      this.isSending = this.controller.pendingRunCount > 0;

      this.controller.onChatUpdate = () => {
        if (this.controller) {
          this.messages = [...this.controller.messages];
          this.thinkingLevel = this.controller.thinkingLevel;
          this.streamingText = this.controller.streamingAssistantText;
          this.errorText = this.controller.errorText;
          this.isSending = this.controller.pendingRunCount > 0;
          
          // Scroll to bottom on new messages
          this.scroller.scrollEdge(Edge.Bottom);
        }
      };
      
      this.controller.refresh();
    }
  }

  build() {
    Column() {
      // Header
      Row() {
        Text("Chat")
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        
        Blank()
        
        Button(this.thinkingLevel.toUpperCase())
          .fontSize(12)
          .height(24)
          .margin({ right: 40 })
          .onClick(() => {
            const levels = ["off", "low", "medium", "high"];
            const next = levels[(levels.indexOf(this.thinkingLevel) + 1) % levels.length];
            this.controller?.setThinkingLevel(next);
          })
      }
      .width('100%')
      .padding(15)
      .backgroundColor('#F5F5F5')

      // Message List
      List({ scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            this.MessageItem(msg)
          }
        }, (msg: ChatMessage) => msg.id)
        
        if (this.streamingText) {
          ListItem() {
            this.StreamingItem(this.streamingText)
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 10, right: 10 })
      .divider({ strokeWidth: 1, color: '#EEEEEE', startMargin: 10, endMargin: 10 })

      if (this.errorText) {
        Text(this.errorText)
          .fontSize(12)
          .fontColor(Color.Red)
          .padding(5)
      }

      // Input Area
      Row() {
        TextInput({ text: this.inputText, placeholder: 'Type a message...' })
          .layoutWeight(1)
          .onChange((val: string) => this.inputText = val)
          .onSubmit(() => this.send())
        
        Button(this.isSending ? '...' : 'Send')
          .enabled(!this.isSending && (this.inputText.trim().length > 0))
          .margin({ left: 10 })
          .onClick(() => this.send())
      }
      .width('100%')
      .padding(10)
      .backgroundColor(Color.White)
    }
    .width('100%')
    .height('100%')
  }

  @Builder MessageItem(msg: ChatMessage) {
    Column() {
      Row() {
        Text(msg.role.toUpperCase())
          .fontSize(10)
          .fontWeight(FontWeight.Bold)
          .fontColor(msg.role === 'user' ? Color.Blue : Color.Gray)
      }
      .width('100%')
      .margin({ bottom: 4 })

      Column() {
        ForEach(msg.content, (content: ChatMessageContent) => {
          if (content.type === 'text' && content.text) {
            Text(content.text)
              .fontSize(14)
              .width('100%')
          } else {
             Text(`[${content.type}] ${content.fileName || ''}`)
              .fontSize(12)
              .fontColor(Color.Gray)
              .fontStyle(FontStyle.Italic)
          }
        })
      }
      .padding(8)
      .backgroundColor(msg.role === 'user' ? '#E3F2FD' : '#F5F5F5')
      .borderRadius(8)
    }
    .margin({ top: 8, bottom: 8 })
    .alignItems(msg.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  @Builder StreamingItem(text: string) {
    Column() {
      Text("ASSISTANT (streaming)")
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.Gray)
        .margin({ bottom: 4 })
      
      Text(text)
        .fontSize(14)
        .width('100%')
        .padding(8)
        .backgroundColor('#FFF9C4')
        .borderRadius(8)
    }
    .margin({ top: 8, bottom: 12 })
    .alignItems(HorizontalAlign.Start)
  }

  private send() {
    if (this.inputText.trim() === "") return;
    const msg = this.inputText;
    this.inputText = "";
    this.controller?.sendMessage(msg, this.thinkingLevel, []);
  }
}
