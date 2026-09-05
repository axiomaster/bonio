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

  // Connection form (migrated from ServerTab)
  @State manualHost: string = '';
  @State manualPort: string = '10724';
  @State manualToken: string = '';
  @State manualTls: boolean = false;
  @State isConnected: boolean = false;
  @State statusText: string = 'Offline';
  @State isConnecting: boolean = false;

  @State locationMode: LocationMode = LocationMode.Off;
  @State voiceWakeMode: VoiceWakeMode = VoiceWakeMode.Off;
  @State cameraEnabled: boolean = false;
  @State screenRecordEnabled: boolean = false;
  @State screenAwarenessEnabled: boolean = false;
  @State contactsEnabled: boolean = false;
  @State calendarEnabled: boolean = false;
  @State serverName: string = '';
  @State remoteAddress: string = '';

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
      this.screenAwarenessEnabled = prefs.getScreenAwarenessEnabled();
      this.manualHost = prefs.getManualHost() || '';
      this.manualPort = prefs.getManualPort().toString() || '10724';
      this.manualToken = prefs.getGatewayToken() || '';
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

      // Magic Cue data sources: toggle state mirrors the actual grant. A user
      // who revokes in system Settings flips the switch off here on next view.
      const contactsStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.READ_CONTACTS");
      this.contactsEnabled = contactsStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      const calendarStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.READ_CALENDAR");
      this.calendarEnabled = calendarStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
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
      this.isConnected = this.runtime.isConnected;
      if (this.isConnecting && (this.isConnected || this.statusText.toLowerCase().includes('fail') || this.statusText.toLowerCase().includes('error'))) {
        this.isConnecting = false;
      }
    }
  }

  private doConnect() {
    if (!this.runtime) return;
    this.runtime.prefs.setManualHost(this.manualHost);
    this.runtime.prefs.setManualPort(parseInt(this.manualPort, 10));
    this.runtime.prefs.setGatewayToken(this.manualToken);
    this.runtime.prefs.setManualTls(this.manualTls);
    this.runtime.connectManual();
    this.isConnecting = true;
  }

  private doDisconnect() {
    if (!this.runtime) return;
    this.runtime.disconnect();
    this.isConnected = false;
    this.statusText = 'Disconnected';
    if (this.onDisconnect) this.onDisconnect();
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
        // Gateway Connection Section (migrated from ServerTab)
        ListItem() { this.SectionHeader("Gateway Connection") }
        ListItem() {
          Column() {
            Text(`Status: ${this.statusText}`)
              .fontSize(13)
              .fontColor(this.isConnected ? '#2ECC71' : '#333333')
              .width('100%')
              .margin({ bottom: 12 })

            TextInput({ placeholder: 'Gateway Host', text: this.manualHost })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .margin({ bottom: 10 })
              .backgroundColor('#F5F5F5')
              .fontColor('#333333')
              .placeholderColor('#999999')
              .onChange((value: string) => { this.manualHost = value; })

            TextInput({ placeholder: 'Port', text: this.manualPort })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .type(InputType.Number)
              .margin({ bottom: 10 })
              .backgroundColor('#F5F5F5')
              .fontColor('#333333')
              .placeholderColor('#999999')
              .onChange((value: string) => { this.manualPort = value; })

            TextInput({ placeholder: 'Token', text: this.manualToken })
              .width('100%')
              .height(44)
              .borderRadius(8)
              .type(InputType.Password)
              .margin({ bottom: 10 })
              .backgroundColor('#F5F5F5')
              .fontColor('#333333')
              .placeholderColor('#999999')
              .onChange((value: string) => { this.manualToken = value; })

            Row() {
              Text('Enable TLS')
                .fontSize(14)
                .fontColor('#333333')
                .fontWeight(FontWeight.Medium)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.manualTls })
                .selectedColor('#0A59F7')
                .onChange((isOn: boolean) => { this.manualTls = isOn; })
            }
            .width('100%')
            .height(40)
            .margin({ bottom: 12 })

            Button(this.isConnected ? 'Disconnect' : (this.isConnecting ? 'Connecting...' : 'Connect'))
              .width('100%')
              .height(44)
              .borderRadius(12)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .backgroundColor(this.isConnected ? '#E53935' : '#0A59F7')
              .fontColor(Color.White)
              .enabled(!this.isConnecting)
              .onClick(() => {
                if (this.isConnected) {
                  this.doDisconnect();
                } else {
                  this.doConnect();
                }
              })
          }
          .width('100%')
          .padding(16)
          .borderRadius(16)
          .backgroundColor(Color.White)
          .border({ width: 1, color: '#E0E0E0' })
        }

        // Node Info Section
        ListItem() { this.SectionHeader("Node Info") }
        ListItem() { this.InfoRow("Device", `${deviceInfo.marketName || deviceInfo.productModel}`) }
        ListItem() { this.InfoRow("Version", "1.0.0-dev") }
        ListItem() { this.InfoRow("Instance ID", this.runtime?.prefs.getInstanceId() || 'Unknown') }

        // Floating Window Section
        ListItem() { this.SectionHeader("Floating Window") }
        ListItem() {
          Row() {
            Text("Enable Avatar Overlay")
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
        ListItem() {
          this.ToggleRow("Screen Awareness", "Allow on-demand reading of the current page",
            this.screenAwarenessEnabled,
            async (enabled: boolean) => {
              if (enabled) {
                const granted = await this.requestPermission("ohos.permission.ONSCREEN_AWARENESS" as Permissions);
                this.screenAwarenessEnabled = granted;
                this.runtime?.setScreenAwarenessEnabled(granted);
              } else {
                this.screenAwarenessEnabled = false;
                this.runtime?.setScreenAwarenessEnabled(false);
              }
            })
        }
        ListItem() {
          this.ToggleRow("Contacts", "Magic Cue recommends contacts when the chat asks",
            this.contactsEnabled,
            async (enabled: boolean) => {
              if (enabled) {
                const granted = await this.requestPermission("ohos.permission.READ_CONTACTS" as Permissions);
                this.contactsEnabled = granted;
                this.runtime?.prefs.setContactsEnabled(granted);
              } else {
                this.contactsEnabled = false;
                this.runtime?.prefs.setContactsEnabled(false);
              }
              // Re-advertise node commands so the agent sees/forgets contacts.search.
              this.runtime?.refreshNodeCapabilities();
            })
        }
        ListItem() {
          this.ToggleRow("Calendar", "Magic Cue recommends calendar events when the chat asks",
            this.calendarEnabled,
            async (enabled: boolean) => {
              if (enabled) {
                const granted = await this.requestPermission("ohos.permission.READ_CALENDAR" as Permissions);
                this.calendarEnabled = granted;
                this.runtime?.prefs.setCalendarEnabled(granted);
              } else {
                this.calendarEnabled = false;
                this.runtime?.prefs.setCalendarEnabled(false);
              }
              // Re-advertise node commands so the agent sees/forgets calendar.events.
              this.runtime?.refreshNodeCapabilities();
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
      const shown = await FloatWindowManager.getInstance().showFloatWindow();
      if (!shown) {
        this.isFloatingWindowEnabled = false;
      }
    } else {
      await FloatWindowManager.getInstance().hideFloatWindow();
    }
  }
}