import { NodeRuntime } from '../node/NodeRuntime';
import { ChatController } from '../node/chat/ChatController';
import { ChatMessage, ChatMessageContent, OutgoingAttachment } from '../node/chat/ChatModels';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import lottie from '@ohos/lottie';

const DOMAIN = 0x3D00;
const TAG = 'ChatTab';

// Agent states mirroring Android AgentState
enum AgentState {
  Idle,
  Listening,
  Thinking,
  Speaking,
  Working
}

@Component
export struct ChatTab {
  runtime: NodeRuntime | undefined = undefined;

  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isSending: boolean = false;
  @State thinkingLevel: string = 'off';
  @State streamingText: string | undefined = undefined;
  @State errorText: string | undefined = undefined;
  @State healthOk: boolean = true;
  @State sessionLabel: string = 'main';
  @State showThinkingMenu: boolean = false;
  @State showAttachmentMenu: boolean = false;
  @State pendingAttachments: OutgoingAttachment[] = [];
  @State isSpeakerEnabled: boolean = true;
  @State agentState: AgentState = AgentState.Idle;
  @State pendingRunCount: number = 0;

  private scroller: Scroller = new Scroller();
  private catCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private catCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.catCanvasSettings);
  private currentLottieAnim: string = 'cat_anim';
  private lastLoadedAsset: string = '';

  aboutToAppear() {
    const ctrl = this.runtime?.chatController;
    if (ctrl) {
      this.syncFromController(ctrl);
      ctrl.onChatUpdate = () => {
        this.syncFromController(ctrl);
      };
      ctrl.refresh();
    }
  }

  aboutToDisappear() {
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (_e) { /* ignore */ }
  }

  private syncFromController(ctrl: ChatController) {
    this.messages = [...ctrl.messages];
    this.thinkingLevel = ctrl.thinkingLevel;
    this.streamingText = ctrl.streamingAssistantText;
    this.errorText = ctrl.errorText;
    this.pendingRunCount = ctrl.pendingRunCount;
    this.isSending = ctrl.pendingRunCount > 0;
    this.healthOk = ctrl.healthOk;
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  private thinkingLabel(raw: string): string {
    switch (raw.trim().toLowerCase()) {
      case 'low': return 'Low';
      case 'medium': return 'Medium';
      case 'high': return 'High';
      default: return 'Off';
    }
  }

  private getLottieAsset(): string {
    switch (this.agentState) {
      case AgentState.Idle: return 'cat-idle.json';
      case AgentState.Listening: return 'cat-listening.json';
      case AgentState.Thinking: return 'cat-thinking.json';
      case AgentState.Speaking: return 'cat-speaking.json';
      case AgentState.Working: return 'cat-working.json';
      default: return 'cat-idle.json';
    }
  }

  private loadCatAnimation() {
    const asset = this.getLottieAsset();
    if (asset === this.lastLoadedAsset) return;
    this.lastLoadedAsset = asset;
    try {
      lottie.destroy(this.currentLottieAnim);
    } catch (_e) { /* ignore if not loaded yet */ }
    lottie.loadAnimation({
      container: this.catCanvasContext,
      renderer: 'canvas',
      loop: true,
      autoplay: true,
      name: this.currentLottieAnim,
      path: asset,
    });
  }

  private async selectImages() {
    try {
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 5;
      const photoPicker = new picker.PhotoViewPicker();
      const res = await photoPicker.select(photoSelectOptions);
      if (res && res.photoUris.length > 0) {
        for (const uri of res.photoUris) {
          await this.addAttachmentFromUri(uri, 'image');
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Photo picker failed: %{public}s', error.message);
    }
  }

  private async selectFiles() {
    try {
      const documentSelectOptions = new picker.DocumentSelectOptions();
      documentSelectOptions.maxSelectNumber = 5;
      const documentPicker = new picker.DocumentViewPicker();
      const res = await documentPicker.select(documentSelectOptions);
      if (res && res.length > 0) {
        for (const uri of res) {
          await this.addAttachmentFromUri(uri, 'file');
        }
      }
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Document picker failed: %{public}s', error.message);
    }
  }

  private async addAttachmentFromUri(uri: string, type: string) {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const fileName = uri.split('/').pop() || (type === 'image' ? 'image.jpg' : 'file');
      if (stat.size > 10 * 1024 * 1024) {
        this.errorText = 'File too large (>10MB)';
        fs.closeSync(file);
        return;
      }
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const helper = new util.Base64Helper();
      const base64 = helper.encodeToStringSync(new Uint8Array(buffer));
      const mimeType = type === 'image' ? 'image/jpeg' : 'application/octet-stream';
      this.pendingAttachments.push({
        type: type,
        mimeType: mimeType,
        fileName: fileName,
        base64: base64
      });
      fs.closeSync(file.fd);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Add attachment failed: %{public}s', error.message);
    }
  }

  private removeAttachment(index: number) {
    this.pendingAttachments.splice(index, 1);
  }

  private canSend(): boolean {
    return !this.isSending && (this.inputText.trim().length > 0 || this.pendingAttachments.length > 0) && this.healthOk;
  }

  private send() {
    if (!this.canSend()) return;
    const msg = this.inputText;
    this.inputText = '';
    const atts = [...this.pendingAttachments];
    this.pendingAttachments = [];
    this.runtime?.chatController?.sendMessage(msg, this.thinkingLevel, atts);
  }

  private onCatPress() {
    if (this.pendingRunCount === 0) {
      this.agentState = AgentState.Listening;
      this.loadCatAnimation();
    }
  }

  private onCatRelease() {
    if (this.agentState === AgentState.Listening) {
      this.agentState = AgentState.Thinking;
      this.loadCatAnimation();
      // Send voice message (simulated)
      this.runtime?.chatController?.sendMessage('[Voice Message]', this.thinkingLevel, []);
      // After a delay, return to Idle
      setTimeout(() => {
        this.agentState = AgentState.Idle;
        this.loadCatAnimation();
      }, 3000);
    }
  }

  build() {
    Column() {
      // ── Session Header Bar ──
      Row() {
        // Session button (left)
        Button(this.sessionLabel)
          .type(ButtonType.Normal)
          .backgroundColor('#E8ECF0')
          .fontColor('#333333')
          .fontSize(13)
          .height(28)
          .borderRadius(8)
          .padding({ left: 10, right: 10 })

        // Connection status pill
        Row() {
          Text('●')
            .fontSize(6)
            .fontColor(this.healthOk ? '#2ECC71' : '#F39C12')
            .margin({ right: 4 })
          Text(this.healthOk ? 'Connected' : 'Offline')
            .fontSize(11)
            .fontColor('#999999')
        }
        .height(28)
        .padding({ left: 8, right: 8 })
        .borderRadius(8)
        .backgroundColor('#E8ECF0')
        .margin({ left: 6 })

        Blank()

        // SPK toggle (right)
        Button() {
          Row() {
            Text(this.isSpeakerEnabled ? '🔊' : '🔇')
              .fontSize(16)
          }
        }
        .type(ButtonType.Normal)
        .width(36)
        .height(28)
        .borderRadius(8)
        .backgroundColor(this.isSpeakerEnabled ? '#E3F2FD' : '#F0F0F0')
        .onClick(() => {
          this.isSpeakerEnabled = !this.isSpeakerEnabled;
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })

      // ── Message Area ──
      List({ scroller: this.scroller }) {
        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() { this.MessageBubble(msg) }
        }, (msg: ChatMessage) => msg.id)

        if (this.streamingText) {
          ListItem() { this.StreamingBubble(this.streamingText!) }
        }

        if (this.isSending && !this.streamingText) {
          ListItem() { this.TypingIndicator() }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })

      // ── Composer Area ──
      Column() {
        // Cat Voice Avatar (above controls, 192vp, left-aligned)
        Row() {
          Column() {
            // Lottie animation via Canvas
            Canvas(this.catCanvasContext)
              .width(192)
              .height(192)
              .onReady(() => {
                this.loadCatAnimation();
              })

            // Status overlay
            if (this.agentState === AgentState.Listening) {
              Text('Listening...')
                .fontSize(11)
                .fontColor('#0A59F7')
                .margin({ top: -20 })
            } else if (this.agentState === AgentState.Thinking) {
              Text('Thinking...')
                .fontSize(11)
                .fontColor('#999999')
                .margin({ top: -20 })
            }
          }
          .gesture(
            LongPressGesture({ repeat: false, duration: 300 })
              .onAction(() => {
                this.onCatPress();
              })
              .onActionEnd(() => {
                this.onCatRelease();
              })
          )
        }
        .width('100%')
        .padding({ left: 8 })
        .justifyContent(FlexAlign.Start)

        // Control Row: Continue/Stop (merged) + Thinking level
        Row() {
          // Dynamic Continue/Stop button
          if (this.pendingRunCount > 0) {
            Button('Stop')
              .type(ButtonType.Normal)
              .height(28)
              .borderRadius(8)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(Color.White)
              .fontColor('#666666')
              .border({ width: 1, color: '#CCCCCC' })
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                // abort not yet implemented in ChatController, use refresh as fallback
                this.runtime?.chatController?.refresh();
              })
          } else {
            Button('Continue')
              .type(ButtonType.Normal)
              .height(28)
              .borderRadius(8)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .backgroundColor(Color.White)
              .fontColor('#666666')
              .border({ width: 1, color: '#CCCCCC' })
              .padding({ left: 8, right: 8 })
              .onClick(() => {
                this.runtime?.chatController?.refresh();
              })
          }

          Blank()

          // Thinking level chip
          Button(`Thinking: ${this.thinkingLabel(this.thinkingLevel)}`)
            .type(ButtonType.Normal)
            .height(28)
            .borderRadius(8)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .backgroundColor(Color.White)
            .fontColor('#666666')
            .border({ width: 1, color: '#CCCCCC' })
            .padding({ left: 8, right: 8 })
            .bindMenu([
              { value: 'Off', action: () => { this.thinkingLevel = 'off'; this.runtime?.chatController?.setThinkingLevel('off'); } },
              { value: 'Low', action: () => { this.thinkingLevel = 'low'; this.runtime?.chatController?.setThinkingLevel('low'); } },
              { value: 'Medium', action: () => { this.thinkingLevel = 'medium'; this.runtime?.chatController?.setThinkingLevel('medium'); } },
              { value: 'High', action: () => { this.thinkingLevel = 'high'; this.runtime?.chatController?.setThinkingLevel('high'); } },
            ])
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })

        // Attachment chips strip
        if (this.pendingAttachments.length > 0) {
          Scroll(new Scroller()) {
            Row() {
              ForEach(this.pendingAttachments, (att: OutgoingAttachment, index: number) => {
                this.AttachmentChip(att, index)
              })
            }
            .padding({ left: 8, right: 8 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }

        // Input row with waveform or text
        Row() {
          if (this.agentState === AgentState.Listening) {
            // Waveform visualization during recording
            Row() {
              ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] as number[], (i: number) => {
                Column()
                  .width(4)
                  .height(8 + (i % 3) * 8)
                  .borderRadius(2)
                  .backgroundColor('#0A59F7')
                  .margin({ left: 2, right: 2 })
              })
            }
            .layoutWeight(1)
            .height(36)
            .justifyContent(FlexAlign.SpaceEvenly)
            .alignItems(VerticalAlign.Center)
            .padding({ left: 12, right: 12 })
            .borderRadius(12)
            .backgroundColor(Color.White)
            .border({ width: 1, color: '#E0E0E0' })
          } else {
            // Normal text input
            TextInput({ text: this.inputText, placeholder: 'Ask anything...' })
              .layoutWeight(1)
              .height(36)
              .borderRadius(12)
              .backgroundColor(Color.White)
              .border({ width: 1, color: '#E0E0E0' })
              .fontSize(14)
              .padding({ left: 12, right: 12 })
              .onChange((val: string) => { this.inputText = val; })
              .onSubmit(() => this.send())
          }

          // Dynamic +/Send button
          Button() {
            if (this.isSending) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(Color.White)
            } else {
              Text(this.inputText.trim().length > 0 ? '↑' : '+')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.inputText.trim().length > 0 && this.canSend() ? Color.White : '#0A59F7')
            }
          }
          .type(ButtonType.Normal)
          .width(36)
          .height(36)
          .borderRadius(8)
          .backgroundColor(this.inputText.trim().length > 0 && this.canSend() ? '#0A59F7' : '#E3F2FD')
          .margin({ left: 8 })
          .onClick(() => {
            if (this.inputText.trim().length > 0) {
              this.send();
            } else {
              this.showAttachmentMenu = !this.showAttachmentMenu;
            }
          })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })

        // Attachment menu (slide-up drawer)
        if (this.showAttachmentMenu) {
          Row() {
            // Camera
            Column() {
              Column() {
                Text('📷')
                  .fontSize(24)
              }
              .width(52)
              .height(52)
              .borderRadius(16)
              .backgroundColor(Color.White)
              .border({ width: 1, color: '#E0E0E0' })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              Text('Camera')
                .fontSize(11)
                .fontColor('#999999')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .onClick(() => {
              this.showAttachmentMenu = false;
              // TODO: camera logic
            })

            // Gallery
            Column() {
              Column() {
                Text('🖼️')
                  .fontSize(24)
              }
              .width(52)
              .height(52)
              .borderRadius(16)
              .backgroundColor(Color.White)
              .border({ width: 1, color: '#E0E0E0' })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              Text('Gallery')
                .fontSize(11)
                .fontColor('#999999')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .onClick(() => {
              this.showAttachmentMenu = false;
              this.selectImages();
            })

            // File
            Column() {
              Column() {
                Text('📄')
                  .fontSize(24)
              }
              .width(52)
              .height(52)
              .borderRadius(16)
              .backgroundColor(Color.White)
              .border({ width: 1, color: '#E0E0E0' })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              Text('File')
                .fontSize(11)
                .fontColor('#999999')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .onClick(() => {
              this.showAttachmentMenu = false;
              this.selectFiles();
            })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 12, bottom: 12 })
        }

        // Error text
        if (this.errorText) {
          Text(this.errorText)
            .fontSize(12)
            .fontColor('#E53935')
            .padding({ left: 10, right: 10, bottom: 8 })
            .maxLines(2)
        }
      }
      .width('100%')
      .padding({ bottom: 20 })
      .backgroundColor('#F0F4F8')
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }

  @Builder AttachmentChip(att: OutgoingAttachment, index: number) {
    Row() {
      Text(att.fileName)
        .fontSize(11)
        .fontColor('#333333')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 100 })
      Text('×')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('#999999')
        .margin({ left: 6 })
        .onClick(() => this.removeAttachment(index))
    }
    .height(28)
    .padding({ left: 10, right: 10 })
    .borderRadius(14)
    .backgroundColor('#E3F2FD')
    .border({ width: 1, color: '#CCCCCC' })
    .margin({ right: 8 })
  }

  @Builder MessageBubble(msg: ChatMessage) {
    Column() {
      if (this.isUserMessage(msg)) {
        Row() {
          Blank()
          Column() {
            ForEach(msg.content, (part: ChatMessageContent) => {
              if (part.type === 'text' && part.text) {
                Text(part.text)
                  .fontSize(15)
                  .fontColor(Color.White)
                  .lineHeight(22)
              } else if (part.type === 'image' && part.base64) {
                Image(`data:${part.mimeType || 'image/jpeg'};base64,${part.base64}`)
                  .width(200)
                  .borderRadius(8)
                  .margin({ top: 4, bottom: 4 })
              } else if (part.type !== 'text') {
                Row() {
                  Text('📄').margin({ right: 6 })
                  Text(part.fileName || 'file')
                    .fontSize(14)
                    .fontColor(Color.White)
                    .maxLines(1)
                }
                .padding(8)
                .backgroundColor('#20FFFFFF')
                .borderRadius(8)
                .margin({ top: 4, bottom: 4 })
              }
            })
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(16)
          .backgroundColor('#1A9E96')
          .constraintSize({ maxWidth: '85%' })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      } else {
        Row() {
          Column() {
            ForEach(msg.content, (part: ChatMessageContent) => {
              if (part.type === 'text' && part.text) {
                Text(part.text)
                  .fontSize(15)
                  .fontColor('#333333')
                  .lineHeight(22)
              } else if (part.type === 'image' && part.base64) {
                Image(`data:${part.mimeType || 'image/jpeg'};base64,${part.base64}`)
                  .width(200)
                  .borderRadius(8)
                  .margin({ top: 4, bottom: 4 })
              } else if (part.type !== 'text') {
                Row() {
                  Text('📄').margin({ right: 6 })
                  Text(part.fileName || 'file')
                    .fontSize(14)
                    .fontColor('#333333')
                    .maxLines(1)
                }
                .padding(8)
                .backgroundColor('#F0F4F8')
                .borderRadius(8)
                .margin({ top: 4, bottom: 4 })
              }
            })
          }
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .constraintSize({ maxWidth: '92%' })
          Blank()
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .margin({ top: 4, bottom: 4 })
  }

  @Builder StreamingBubble(text: string) {
    Row() {
      Column() {
        Text(text)
          .fontSize(15)
          .fontColor('#333333')
          .lineHeight(22)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .borderRadius(16)
      .backgroundColor('#E8ECF0')
      .constraintSize({ maxWidth: '92%' })
      Blank()
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .margin({ top: 4, bottom: 4 })
  }

  @Builder TypingIndicator() {
    Row() {
      Row() {
        Text('●').fontSize(6).fontColor('#999999').opacity(0.4).margin({ right: 4 })
        Text('●').fontSize(6).fontColor('#999999').opacity(0.65).margin({ right: 4 })
        Text('●').fontSize(6).fontColor('#999999').opacity(0.9).margin({ right: 8 })
        Text('Thinking…').fontSize(14).fontColor('#999999')
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .borderRadius(16)
      .backgroundColor('#E8ECF0')
      Blank()
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .margin({ top: 4, bottom: 4 })
  }

  private isUserMessage(msg: ChatMessage): boolean {
    return msg.role.toLowerCase() === 'user';
  }
}
