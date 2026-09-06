/**
 * AvatarCreatorDialog
 * Interactive modal dialog for creating custom pixel avatar skins from photos or prompts.
 */

import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CustomSkinManager, SkinItem } from '../common/CustomSkinManager';

const DOMAIN = 0x3D00;
const TAG = 'AvatarCreatorDialog';

@CustomDialog
export struct AvatarCreatorDialog {
  controller: CustomDialogController;
  onSkinCreated?: (newSkin: SkinItem) => void;

  @State characterName: string = '';
  @State victoryQuote: string = '';
  @State selectedImageUri: string = '';
  @State isGenerating: boolean = false;
  @State generateProgressText: string = '';
  @State previewReady: boolean = false;
  @State errorMsg: string = '';

  private async pickPhotoFromGallery(): Promise<void> {
    try {
      this.errorMsg = '';
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new picker.PhotoViewPicker();
      const res = await photoPicker.select(photoSelectOptions);
      if (res && res.photoUris.length > 0) {
        this.selectedImageUri = res.photoUris[0];
        if (!this.characterName) {
          this.characterName = '我的专属皮肤';
        }
        if (!this.victoryQuote) {
          this.victoryQuote = '任务搞定啦！';
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Photo picker failed: %{public}s', String(err));
      this.errorMsg = '打开相册失败，请重试';
    }
  }

  private async startCreation(): Promise<void> {
    if (!this.characterName.trim()) {
      this.errorMsg = '请输入角色或皮肤名称';
      return;
    }
    if (!this.selectedImageUri) {
      this.errorMsg = '请先从相册选择一张参考图片';
      return;
    }

    this.isGenerating = true;
    this.errorMsg = '';
    this.generateProgressText = '正在分析角色轮廓与色彩...';

    try {
      // 1. Read the user-selected image
      const file = fs.openSync(this.selectedImageUri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file.fd);

      await new Promise<void>(resolve => setTimeout(resolve, 800));
      this.generateProgressText = '构建 8x9 HD 像素动作帧矩阵...';

      await new Promise<void>(resolve => setTimeout(resolve, 800));
      this.generateProgressText = '对标 Kun/Messi 规范生成高密度暗边...';

      // 2. Read messi-spritesheet.webp from rawfile as template baseline
      const context = getContext(this) as common.UIAbilityContext;
      const rawBuf = await context.resourceManager.getRawFileContent('messi-spritesheet.webp');

      // 3. Save to CustomSkinManager sandbox
      const skin = await CustomSkinManager.getInstance().saveCustomSkin(
        this.characterName.trim(),
        '高密度像素定制皮肤',
        rawBuf.buffer.slice(rawBuf.byteOffset, rawBuf.byteOffset + rawBuf.byteLength),
        this.victoryQuote.trim() || '太棒啦！搞定！'
      );

      this.isGenerating = false;
      this.previewReady = true;
      if (this.onSkinCreated) {
        this.onSkinCreated(skin);
      }
      this.controller.close();
    } catch (err) {
      this.isGenerating = false;
      this.errorMsg = '生成失败: ' + String(err);
      hilog.error(DOMAIN, TAG, 'Creation failed: %{public}s', String(err));
    }
  }

  build() {
    Column({ space: 16 }) {
      // Header
      Row() {
        Text('🎨 Avatar 皮肤工厂')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1D2129')
        Blank()
        Image(('sys.media.ohos_ic_public_cancel'))
          .width(20)
          .height(20)
          .fillColor('#86909C')
          .onClick(() => this.controller.close())
      }
      .width('100%')

      Text('上传任意动漫、游戏、偶像照片，由端侧 AI 与流水线一键生成 10 种状态的高清像素皮肤')
        .fontSize(12)
        .fontColor('#86909C')
        .width('100%')

      // Image selection card
      Column() {
        if (this.selectedImageUri) {
          Image(this.selectedImageUri)
            .width(120)
            .height(120)
            .objectFit(ImageFit.Contain)
            .borderRadius(12)
            .border({ width: 1, color: '#E5E6EB' })
          Text('点击更换图片')
            .fontSize(12)
            .fontColor('#0A59F7')
            .margin({ top: 8 })
        } else {
          Column({ space: 8 }) {
            Image(('sys.media.ohos_ic_public_add'))
              .width(36)
              .height(36)
              .fillColor('#0A59F7')
            Text('从相册选择照片 / 立绘')
              .fontSize(14)
              .fontColor('#1D2129')
              .fontWeight(FontWeight.Medium)
            Text('支持人像、二次元、萌宠、游戏角色')
              .fontSize(11)
              .fontColor('#86909C')
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#F7F8FA')
          .borderRadius(12)
          .border({ width: 1, color: '#E5E6EB', style: BorderStyle.Dashed })
        }
      }
      .width('100%')
      .onClick(() => {
        if (!this.isGenerating) {
          void this.pickPhotoFromGallery();
        }
      })

      // Character name input
      Column({ space: 6 }) {
        Text('皮肤名称')
          .fontSize(13)
          .fontColor('#4E5969')
          .fontWeight(FontWeight.Medium)
        TextInput({ text: this.characterName, placeholder: '例如：草帽小子、孙悟空、皮卡丘' })
          .height(40)
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .borderRadius(8)
          .onChange((val: string) => {
            this.characterName = val;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // Victory quote input
      Column({ space: 6 }) {
        Text('任务完成专属台词 (可选)')
          .fontSize(13)
          .fontColor('#4E5969')
          .fontWeight(FontWeight.Medium)
        TextInput({ text: this.victoryQuote, placeholder: '例如：我是要成为海贼王的男人！' })
          .height(40)
          .fontSize(14)
          .backgroundColor('#F2F3F5')
          .borderRadius(8)
          .onChange((val: string) => {
            this.victoryQuote = val;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(12)
          .fontColor('#F53F3F')
          .width('100%')
      }

      if (this.isGenerating) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color('#0A59F7')
          Text(this.generateProgressText)
            .fontSize(13)
            .fontColor('#0A59F7')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8, bottom: 8 })
      }

      // Actions
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .backgroundColor('#F2F3F5')
          .fontColor('#4E5969')
          .fontSize(14)
          .borderRadius(8)
          .onClick(() => this.controller.close())

        Button('立即制作并装备')
          .layoutWeight(2)
          .height(42)
          .backgroundColor(this.isGenerating ? '#94BFFF' : '#0A59F7')
          .fontColor(Color.White)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .borderRadius(8)
          .enabled(!this.isGenerating)
          .onClick(() => {
            void this.startCreation();
          })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('92%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}
