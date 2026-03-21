import { NodeRuntime } from '../node/NodeRuntime';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SecurePrefs } from '../common/SecurePrefs';
import { LocationMode, VoiceWakeMode } from '../models/CommonModels';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FloatWindowManager } from '../common/FloatWindowManager';

const DOMAIN = 0x3D00;

@Component
export struct SettingsTab {
  runtime: NodeRuntime | undefined = undefined;
  onDisconnect: (() => void) | undefined = undefined;

  @State isFloatingWindowEnabled: boolean = false;

  @State locationMode: LocationMode = LocationMode.Off;
  @State voiceWakeMode: VoiceWakeMode = VoiceWakeMode.Off;
  @State cameraEnabled: boolean = false;
  @State screenRecordEnabled: boolean = false;
  @State manualTls: boolean = false;
  @State serverName: string = '';
  @State remoteAddress: string = '';
  @State statusText: string = '';

  private statusTimer: number = -1;

  aboutToAppear() {
    this.syncWithPrefs();
    this.syncWithSystemPermissions();
    this.refreshStatus();
    this.statusTimer = setInterval(() => { this.refreshStatus(); }, 1000);
  }

  private syncWithPrefs() {
    const prefs = this.runtime?.prefs;
    if (prefs) {
      this.locationMode = prefs.getLocationMode();
      this.voiceWakeMode = prefs.getVoiceWakeMode();
      this.cameraEnabled = prefs.getCameraEnabled();
      this.screenRecordEnabled = prefs.getScreenRecordEnabled();
      this.manualTls = prefs.getManualTls();
    }
  }

  private async syncWithSystemPermissions() {
    const atManager = abilityAccessCtrl.createAtManager();
    const tokenID = (getContext(this) as common.UIAbilityContext).applicationInfo.accessTokenId;
    
    try {
      const locStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.APPROXIMATELY_LOCATION");
      if (locStatus === abilityAccessCtrl.GrantStatus.PERMISSION_DENIED && this.locationMode !== LocationMode.Off) {
        this.locationMode = LocationMode.Off;
        this.runtime?.prefs.setLocationMode(LocationMode.Off);
      }

      const micStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.MICROPHONE");
      if (micStatus === abilityAccessCtrl.GrantStatus.PERMISSION_DENIED && this.voiceWakeMode !== VoiceWakeMode.Off) {
        this.voiceWakeMode = VoiceWakeMode.Off;
        this.runtime?.prefs.setVoiceWakeMode(VoiceWakeMode.Off);
      }

      const camStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.CAMERA");
      if (camStatus === abilityAccessCtrl.GrantStatus.PERMISSION_DENIED && this.cameraEnabled) {
        this.cameraEnabled = false;
        this.runtime?.prefs.setCameraEnabled(false);
      }
    } catch (e) {
      hilog.error(0x3D00, 'SettingsTab', `syncWithSystemPermissions failed: ${e}`);
    }
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  private refreshStatus() {
    if (this.runtime) {
      this.serverName = this.runtime.serverName || '';
      this.remoteAddress = this.runtime.remoteAddress || `${this.runtime.prefs.getManualHost()}:${this.runtime.prefs.getManualPort()}`;
      this.statusText = this.runtime.statusText;
    }
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
      hilog.error(0x3D00, 'SettingsTab', `Permission request failed: ${e}`);
    }
    return false;
  }

  build() {
    Column() {
      List({ space: 0 }) {
        // Node Info Section
        ListItem() { this.SectionHeader("Node Info") }
        ListItem() { this.InfoRow("Device", `${deviceInfo.marketName || deviceInfo.productModel}`) }
        ListItem() { this.InfoRow("Version", "1.0.0-dev") }
        ListItem() { this.InfoRow("Instance ID", this.runtime?.prefs.getInstanceId() || 'Unknown') }

        // Floating Window Section
        ListItem() { this.SectionHeader("Floating Window") }
        ListItem() {
          Row() {
            Text("Floating Window Permission")
              .fontSize(14)
              .fontColor('#333333')
            Blank()
            Button("Grant")
              .type(ButtonType.Capsule)
              .backgroundColor('#0A59F7')
              .fontColor(Color.White)
              .fontSize(12)
              .height(28)
              .onClick(() => {
                this.requestFloatWindowPermission();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
        ListItem() {
          Row() {
            Text("Enable Cat Overlay")
              .fontSize(14)
              .fontColor('#333333')
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.isFloatingWindowEnabled })
              .selectedColor('#0A59F7')
              .onChange((isOn: boolean) => {
                this.toggleFloatingWindow(isOn);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }

        // Permissions Section
        ListItem() { this.SectionHeader("Permissions") }
        ListItem() {
          this.ToggleRow("Location", "GPS location sharing",
            this.locationMode !== LocationMode.Off,
            async (enabled: boolean) => {
              if (enabled) {
                const granted = await this.requestPermission("ohos.permission.APPROXIMATELY_LOCATION");
                if (granted) {
                  this.locationMode = LocationMode.WhileUsing;
                  this.runtime?.prefs.setLocationMode(this.locationMode);
                }
              } else {
                this.locationMode = LocationMode.Off;
                this.runtime?.prefs.setLocationMode(this.locationMode);
              }
            })
        }
        ListItem() {
          this.ToggleRow("Voice Wake", "Wake word listening",
            this.voiceWakeMode !== VoiceWakeMode.Off,
            async (enabled: boolean) => {
              if (enabled) {
                const granted = await this.requestPermission("ohos.permission.MICROPHONE");
                if (granted) {
                  this.voiceWakeMode = VoiceWakeMode.Foreground;
                  this.runtime?.prefs.setVoiceWakeMode(this.voiceWakeMode);
                } else {
                  this.voiceWakeMode = VoiceWakeMode.Off;
                }
              } else {
                this.voiceWakeMode = VoiceWakeMode.Off;
                this.runtime?.prefs.setVoiceWakeMode(this.voiceWakeMode);
              }
            })
        }
        ListItem() {
          this.ToggleRow("Camera Access", "Allow remote photo/video",
            this.cameraEnabled,
            async (enabled: boolean) => {
              if (enabled) {
                const granted = await this.requestPermission("ohos.permission.CAMERA");
                if (granted) {
                  this.cameraEnabled = true;
                  this.runtime?.prefs.setCameraEnabled(true);
                } else {
                  this.cameraEnabled = false;
                }
              } else {
                this.cameraEnabled = false;
                this.runtime?.prefs.setCameraEnabled(false);
              }
            })
        }
        ListItem() {
          this.ToggleRow("Screen Recording", "Allow remote screen view",
            this.screenRecordEnabled,
            async (enabled: boolean) => {
              if (enabled) {
                // Screen recording often requires multiple permissions or special dialogs
                const granted = await this.requestPermission("ohos.permission.MICROPHONE");
                if (granted) {
                  this.screenRecordEnabled = true;
                  this.runtime?.prefs.setScreenRecordEnabled(true);
                }
              } else {
                this.screenRecordEnabled = false;
                this.runtime?.prefs.setScreenRecordEnabled(false);
              }
            })
        }

        // Display Section
        ListItem() { this.SectionHeader("Connection") }
        ListItem() {
          this.ToggleRow("Require TLS", "Pin certificate on first connect",
            this.manualTls,
            (enabled: boolean) => {
              this.manualTls = enabled;
              this.runtime?.prefs.setManualTls(this.manualTls);
            })
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FAFAFA')
    }
    .width('100%')
    .height('100%')
  }

  @Builder SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#0A59F7')
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 16, top: 20, bottom: 6 })
  }

  @Builder InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor('#333333')
        .width(100)
      Text(value)
        .fontSize(15)
        .fontColor('#666666')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
  }

  @Builder ToggleRow(title: string, subtitle: string, isOn: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Column() {
        Text(title).fontSize(15).fontColor('#333333')
        Text(subtitle).fontSize(12).fontColor('#999999').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor('#0A59F7')
        .onChange(onChange)
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
  }

  private async toggleFloatingWindow(isOn: boolean) {
    this.isFloatingWindowEnabled = isOn;
    if (isOn) {
      await FloatWindowManager.getInstance().showFloatWindow();
    } else {
      await FloatWindowManager.getInstance().hideFloatWindow();
    }
  }

  private requestFloatWindowPermission() {
    const context = getContext(this) as common.UIAbilityContext;
    try {
      context.startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
          pushParams: context.abilityInfo.bundleName
        }
      });
      hilog.info(DOMAIN, 'SettingsTab', 'Navigating to system settings for float window permission');
    } catch (err) {
      hilog.error(DOMAIN, 'SettingsTab', 'Failed to jump to settings: %{public}s', JSON.stringify(err));
    }
  }
}
