/**
 * AvatarCreatorDialog
 * Interactive studio dialog for creating custom pixel avatar skins from photos.
 * Features:
 * 1. Image upload with smart background cutout
 * 2. Real-time pixelation engine (HD / Classic / 8-bit)
 * 3. Interactive action binding stage with live animated preview (Idle, Run, Wave, Jump, etc.)
 * 4. Procedural 8x9 SpriteSheet compilation (72 frames) & one-click live equip.
 */

import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CustomSkinManager, SkinItem } from '../common/CustomSkinManager';
import {
  PixelArtEngine,
  PixelStyleConfig,
  DEFAULT_PIXEL_STYLE,
  PixelArtResult,
  FRAME_WIDTH,
  FRAME_HEIGHT
} from '../common/PixelArtEngine';
import {
  ActionBindingEngine,
  ACTION_LIST,
  ActionInfo
} from '../common/ActionBindingEngine';

const DOMAIN = 0x3D00;
const TAG = 'AvatarCreatorDialog';

@CustomDialog
export struct AvatarCreatorDialog {
  controller: CustomDialogController;
  onSkinCreated?: (newSkin: SkinItem) => void;

  // Step control: 1: Pick & Crop, 2: Pixelate & Action Binding Stage, 3: Saving
  @State currentStep: number = 1;

  // User input
  @State selectedImageUri: string = '';
  @State characterName: string = '小鱼';
  @State victoryQuote: string = '太棒啦！小鱼搞定任务啦！';

  // Pixel style options
  @State selectedGridSize: number = 48; // 32, 48, 64
  @State enableOutline: boolean = true;
  @State removeBg: boolean = true;

  // Processing state
  @State isProcessingPixel: boolean = false;
  @State isBuildingSheet: boolean = false;
  @State progressText: string = '';
  @State errorMsg: string = '';

  // Processed pixel art
  @State pixelMapPreview: image.PixelMap | undefined = undefined;
  private currentPixelResult: PixelArtResult | null = null;
  private actionEngine: ActionBindingEngine | null = null;

  // Live action preview state
  @State selectedActionKey: string = 'idle';
  @State currentFrameIndex: number = 0;
  @State activeFrameMap: image.PixelMap | undefined = undefined;
  private actionPixelMaps: image.PixelMap[] = [];
  private animTimer: number = -1;

  aboutToDisappear(): void {
    this.stopAnimation();
    this.releasePixelMaps();
  }

  private stopAnimation(): void {
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer);
      this.animTimer = -1;
    }
  }

  private releasePixelMaps(): void {
    for (const pm of this.actionPixelMaps) {
      try { pm.release(); } catch (_) {}
    }
    this.actionPixelMaps = [];
  }

  /**
   * Safe gallery picker.
   */
  private async pickPhoto(): Promise<void> {
    try {
      this.errorMsg = '';
      const photoSelectOptions = new picker.PhotoSelectOptions();
      photoSelectOptions.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new picker.PhotoViewPicker();
      const res = await photoPicker.select(photoSelectOptions);
      if (res && res.photoUris && res.photoUris.length > 0) {
        this.selectedImageUri = res.photoUris[0];
        await this.runPixelation();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Photo picker error: %{public}s', String(err));
      this.errorMsg = '选取相册图片失败，请重试';
    }
  }

  /**
   * Run real pixelation on the selected image.
   */
  private async runPixelation(): Promise<void> {
    if (!this.selectedImageUri) return;
    this.isProcessingPixel = true;
    this.errorMsg = '';
    this.progressText = '正在点阵采样、色彩量化与描边处理...';

    try {
      const config: PixelStyleConfig = {
        gridSize: this.selectedGridSize,
        colorLevels: this.selectedGridSize === 64 ? 12 : (this.selectedGridSize === 48 ? 8 : 5),
        enableOutline: this.enableOutline,
        removeBg: this.removeBg,
        bgTolerance: 40
      };

      const result = await PixelArtEngine.processImage(this.selectedImageUri, config);
      this.currentPixelResult = result;
      this.pixelMapPreview = result.basePixelMap;

      // Initialize action binding engine
      this.actionEngine = new ActionBindingEngine(result.rgbaBuffer);
      this.currentStep = 2;

      // Start previewing default action (idle)
      await this.switchAction('idle');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Pixelation failed: %{public}s', String(err));
      this.errorMsg = '像素化失败: ' + String(err);
    } finally {
      this.isProcessingPixel = false;
    }
  }

  /**
   * Switch live preview action (e.g. idle -> run -> jump -> wave).
   */
  private async switchAction(actionKey: string): Promise<void> {
    if (!this.actionEngine) return;
    this.selectedActionKey = actionKey;
    this.stopAnimation();
    this.releasePixelMaps();

    try {
      this.actionPixelMaps = await this.actionEngine.getActionPixelMaps(actionKey);
      if (this.actionPixelMaps.length > 0) {
        this.currentFrameIndex = 0;
        this.activeFrameMap = this.actionPixelMaps[0];

        const actInfo = ACTION_LIST.find(a => a.key === actionKey) || ACTION_LIST[0];
        const intervalMs = Math.round(1000 / actInfo.fps);

        this.animTimer = setInterval(() => {
          if (this.actionPixelMaps.length === 0) return;
          this.currentFrameIndex = (this.currentFrameIndex + 1) % this.actionPixelMaps.length;
          this.activeFrameMap = this.actionPixelMaps[this.currentFrameIndex];
        }, intervalMs);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Action preview failed: %{public}s', String(err));
    }
  }

  /**
   * Compile full 8x9 SpriteSheet and save to sandbox.
   */
  private async bakeAndEquip(): Promise<void> {
    if (!this.actionEngine || !this.currentPixelResult) {
      this.errorMsg = '请先选取照片并完成像素化';
      return;
    }
    if (!this.characterName.trim()) {
      this.errorMsg = '请输入皮肤名称';
      return;
    }

    this.isBuildingSheet = true;
    this.errorMsg = '';
    this.progressText = '正在合成 8x9 动作矩阵 (72 帧高清精灵表)...';

    try {
      // 1. Synthesize full 8x9 SpriteSheet PNG buffer
      const sheetBuffer = await this.actionEngine.buildFullSpriteSheet();

      // 2. Pack preview thumbnail (base frame)
      const packer = image.createImagePacker();
      const previewData = await packer.packing(this.currentPixelResult.basePixelMap, {
        format: 'image/png',
        quality: 100
      });

      // 3. Save to CustomSkinManager
      const context = getContext(this) as common.UIAbilityContext;
      CustomSkinManager.getInstance().init(context);

      const newSkin = await CustomSkinManager.getInstance().saveCustomSkin(
        this.characterName.trim(),
        `高密度像素角色 (${this.selectedGridSize}px)`,
        sheetBuffer,
        this.victoryQuote.trim() || '太棒啦！搞定任务！',
        previewData
      );

      hilog.info(DOMAIN, TAG, 'Custom skin successfully created & saved: %{public}s', newSkin.id);

      if (this.onSkinCreated) {
        this.onSkinCreated(newSkin);
      }
      this.controller.close();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Bake and save failed: %{public}s', String(err));
      this.errorMsg = '保存皮肤失败: ' + String(err);
    } finally {
      this.isBuildingSheet = false;
    }
  }

  build() {
    Column({ space: 12 }) {
      // Title bar
      Row() {
        Text('🎨 Avatar 像素工坊')
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

      if (this.currentStep === 1) {
        // Step 1: Uploading
        Column({ space: 14 }) {
          Text('上传任意真人、小孩全身照、二次元或萌宠照片，自动进行点阵化与 10 种状态动作绑定')
            .fontSize(12)
            .fontColor('#86909C')
            .width('100%')

          Column({ space: 8 }) {
            Image(('sys.media.ohos_ic_public_add'))
              .width(44)
              .height(44)
              .fillColor('#0A59F7')
            Text('从相册选择全身或立绘照片')
              .fontSize(15)
              .fontColor('#1D2129')
              .fontWeight(FontWeight.Medium)
            Text('支持人像生活照、动漫角色、游戏立绘')
              .fontSize(12)
              .fontColor('#86909C')
          }
          .width('100%')
          .height(160)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('#F7F8FA')
          .borderRadius(14)
          .border({ width: 1.5, color: '#0A59F7', style: BorderStyle.Dashed })
          .onClick(() => {
            void this.pickPhoto();
          })

          if (this.isProcessingPixel) {
            Row({ space: 8 }) {
              LoadingProgress().width(20).height(20).color('#0A59F7')
              Text(this.progressText).fontSize(12).fontColor('#0A59F7')
            }
          }
        }
        .width('100%')
      } else {
        // Step 2: Pixel Tuning & Action Binding Studio
        Scroll() {
          Column({ space: 14 }) {
            // Stage Card: Live Animated Action Stage
            Column() {
              Row() {
                Text('动作绑定舞台 (实时动作试玩)')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#4E5969')
                Blank()
                Text('点击更换图片')
                  .fontSize(11)
                  .fontColor('#0A59F7')
                  .onClick(() => {
                    void this.pickPhoto();
                  })
              }
              .width('100%')
              .margin({ bottom: 8 })

              // Character Pedestal Stage
              Stack({ alignContent: Alignment.Bottom }) {
                // Circular shadow pedestal
                Circle({ width: 110, height: 26 })
                  .fill('#E5E6EB')
                  .margin({ bottom: 6 })

                if (this.activeFrameMap) {
                  Image(this.activeFrameMap)
                    .width(130)
                    .height(140)
                    .objectFit(ImageFit.Contain)
                    .interpolation(ImageInterpolation.None)
                } else if (this.pixelMapPreview) {
                  Image(this.pixelMapPreview)
                    .width(130)
                    .height(140)
                    .objectFit(ImageFit.Contain)
                    .interpolation(ImageInterpolation.None)
                }
              }
              .width('100%')
              .height(150)
              .backgroundColor('#F7F8FA')
              .borderRadius(12)

              // Action Switcher Chips
              Text('动作绑定测试 (点击切换实时动作):')
                .fontSize(11)
                .fontColor('#86909C')
                .margin({ top: 8, bottom: 4 })
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(ACTION_LIST, (act: ActionInfo) => {
                  Text(act.name)
                    .fontSize(11)
                    .fontWeight(this.selectedActionKey === act.key ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.selectedActionKey === act.key ? Color.White : '#1D2129')
                    .backgroundColor(this.selectedActionKey === act.key ? '#0A59F7' : '#EFF0F3')
                    .borderRadius(14)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .margin({ right: 6, bottom: 6 })
                    .onClick(() => {
                      void this.switchAction(act.key);
                    })
                }, (act: ActionInfo) => act.key)
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(12)
            .border({ width: 1, color: '#E5E6EB' })

            // Pixel Style Selector
            Row({ space: 8 }) {
              Text('像素精度:')
                .fontSize(12)
                .fontColor('#4E5969')
                .fontWeight(FontWeight.Medium)

              Button('经典 48px')
                .fontSize(11)
                .height(28)
                .backgroundColor(this.selectedGridSize === 48 ? '#0A59F7' : '#F2F3F5')
                .fontColor(this.selectedGridSize === 48 ? Color.White : '#4E5969')
                .onClick(() => {
                  this.selectedGridSize = 48;
                  void this.runPixelation();
                })

              Button('高清 64px')
                .fontSize(11)
                .height(28)
                .backgroundColor(this.selectedGridSize === 64 ? '#0A59F7' : '#F2F3F5')
                .fontColor(this.selectedGridSize === 64 ? Color.White : '#4E5969')
                .onClick(() => {
                  this.selectedGridSize = 64;
                  void this.runPixelation();
                })

              Button('8-Bit 32px')
                .fontSize(11)
                .height(28)
                .backgroundColor(this.selectedGridSize === 32 ? '#0A59F7' : '#F2F3F5')
                .fontColor(this.selectedGridSize === 32 ? Color.White : '#4E5969')
                .onClick(() => {
                  this.selectedGridSize = 32;
                  void this.runPixelation();
                })
            }
            .width('100%')

            // Detail Toggles: Smart Background Cutout & Dark Outline
            Row({ space: 16 }) {
              Row({ space: 6 }) {
                Text('智能去背景')
                  .fontSize(12)
                  .fontColor('#4E5969')
                Toggle({ type: ToggleType.Switch, isOn: this.removeBg })
                  .selectedColor('#0A59F7')
                  .height(20)
                  .onChange((v: boolean) => {
                    this.removeBg = v;
                    void this.runPixelation();
                  })
              }

              Row({ space: 6 }) {
                Text('像素描边')
                  .fontSize(12)
                  .fontColor('#4E5969')
                Toggle({ type: ToggleType.Switch, isOn: this.enableOutline })
                  .selectedColor('#0A59F7')
                  .height(20)
                  .onChange((v: boolean) => {
                    this.enableOutline = v;
                    void this.runPixelation();
                  })
              }
            }
            .width('100%')

            // Name and Quote input
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text('角色名称')
                  .fontSize(11)
                  .fontColor('#4E5969')
                TextInput({ text: this.characterName, placeholder: '例如：小鱼' })
                  .height(36)
                  .fontSize(13)
                  .backgroundColor('#F2F3F5')
                  .borderRadius(6)
                  .onChange((v: string) => { this.characterName = v; })
              }
              .layoutWeight(1)

              Column({ space: 4 }) {
                Text('完成台词')
                  .fontSize(11)
                  .fontColor('#4E5969')
                TextInput({ text: this.victoryQuote, placeholder: '完成任务喊话' })
                  .height(36)
                  .fontSize(13)
                  .backgroundColor('#F2F3F5')
                  .borderRadius(6)
                  .onChange((v: string) => { this.victoryQuote = v; })
              }
              .layoutWeight(2)
            }
            .width('100%')

            if (this.isBuildingSheet) {
              Row({ space: 8 }) {
                LoadingProgress().width(20).height(20).color('#0A59F7')
                Text(this.progressText).fontSize(12).fontColor('#0A59F7')
              }
              .justifyContent(FlexAlign.Center)
              .width('100%')
            }
          }
        }
        .constraintSize({ maxHeight: '68%' })
      }

      if (this.errorMsg) {
        Text(this.errorMsg)
          .fontSize(11)
          .fontColor('#F53F3F')
          .width('100%')
      }

      // Actions bottom bar
      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(40)
          .backgroundColor('#F2F3F5')
          .fontColor('#4E5969')
          .fontSize(13)
          .borderRadius(8)
          .onClick(() => this.controller.close())

        if (this.currentStep === 2) {
          Button('立即烘焙并装备')
            .layoutWeight(2)
            .height(40)
            .backgroundColor(this.isBuildingSheet ? '#94BFFF' : '#0A59F7')
            .fontColor(Color.White)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .borderRadius(8)
            .enabled(!this.isBuildingSheet && !this.isProcessingPixel)
            .onClick(() => {
              void this.bakeAndEquip();
            })
        }
      }
      .width('100%')
      .padding({ top: 4 })
    }
    .width('94%')
    .padding(16)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }
}
