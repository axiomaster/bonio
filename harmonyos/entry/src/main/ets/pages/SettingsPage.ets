import { router } from '@kit.ArkUI';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SecurePrefs } from '../common/SecurePrefs';
import { LocationMode, VoiceWakeMode, locationModeFromRaw, voiceWakeModeFromRaw } from '../models/CommonModels';

@Entry
@Component
export struct SettingsPage {
  private prefs = SecurePrefs.getInstance();
  
  @State locationMode: LocationMode = LocationMode.Off;
  @State voiceWakeMode: VoiceWakeMode = VoiceWakeMode.Off;
  @State manualTls: boolean = false;
  
  aboutToAppear() {
    this.prefs.init(getContext(this) as common.UIAbilityContext);
    this.locationMode = this.prefs.getLocationMode();
    this.voiceWakeMode = this.prefs.getVoiceWakeMode();
    this.manualTls = this.prefs.getManualTls();
  }

  async requestPermission(permission: Permissions): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const grantStatus = await atManager.requestPermissionsFromUser(context, [permission]);
      if (grantStatus.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
    } catch (e) {
      hilog.error(0x3D00, 'SettingsPage', `Permission request failed: ${e}`);
    }
    return false;
  }

  build() {
    Column() {
      // Header
      Row() {
        Text("< Back")
          .fontSize(16)
          .fontColor('#0A59F7')
          .margin({ right: 10 })
          .onClick(() => {
            router.back();
          })
        Text("Settings")
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .padding(20)

      List({ space: 20, initialIndex: 0 }) {
        ListItem() {
          Column() {
            Text("Permissions & Handlers")
              .fontSize(14)
              .fontColor(Color.Gray)
              .margin({ bottom: 10, left: 15 })
              .width('100%')
              .textAlign(TextAlign.Start)
              
            Column() {
              this.ToggleItem("Location Mode", "Enable GPS location querying", this.locationMode !== LocationMode.Off, async (enabled: boolean) => {
                if (enabled) {
                  const granted = await this.requestPermission("ohos.permission.APPROXIMATELY_LOCATION");
                  if (granted) {
                    this.locationMode = LocationMode.WhileUsing;
                    this.prefs.setLocationMode(this.locationMode);
                  }
                } else {
                  this.locationMode = LocationMode.Off;
                  this.prefs.setLocationMode(this.locationMode);
                }
              })
              
              Divider().color('#e8e8e8').strokeWidth(1).margin({ top: 5, bottom: 5 })
              
              this.ToggleItem("Voice Wake Mode", "Allow wake words (Not fully ported yet)", this.voiceWakeMode !== VoiceWakeMode.Off, async (enabled: boolean) => {
                if (enabled) {
                  const granted = await this.requestPermission("ohos.permission.MICROPHONE");
                  if (granted) {
                    this.voiceWakeMode = VoiceWakeMode.Foreground;
                    this.prefs.setVoiceWakeMode(this.voiceWakeMode);
                  }
                } else {
                  this.voiceWakeMode = VoiceWakeMode.Off;
                  this.prefs.setVoiceWakeMode(this.voiceWakeMode);
                }
              })
            }
            .backgroundColor(Color.White)
            .borderRadius(16)
            .padding({ top: 5, bottom: 5, left: 15, right: 15 })
            .width('90%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
        
        ListItem() {
          Column() {
            Text("Connection")
              .fontSize(14)
              .fontColor(Color.Gray)
              .margin({ bottom: 10, left: 15 })
              .width('100%')
              .textAlign(TextAlign.Start)
              
            Column() {
              this.ToggleItem("Manual TLS", "Requires wss:// and fingerprint", this.manualTls, (enabled: boolean) => {
                  this.manualTls = enabled;
                  this.prefs.setManualTls(this.manualTls);
              })
            }
            .backgroundColor(Color.White)
            .borderRadius(16)
            .padding({ top: 5, bottom: 5, left: 15, right: 15 })
            .width('90%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#f1f3f5')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#f1f3f5')
  }

  @Builder ToggleItem(title: string, subtitle: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Column() {
        Text(title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.Black)
        if (subtitle) {
          Text(subtitle).fontSize(12).fontColor(Color.Gray).margin({ top: 4 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor('#0A59F7')
        .switchPointColor('#FFFFFF')
        .onChange(onChange)
    }
    .width('100%')
    .height(60)
    .alignItems(VerticalAlign.Center)
  }
}
