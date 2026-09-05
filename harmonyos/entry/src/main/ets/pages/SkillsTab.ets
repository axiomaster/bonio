import { NodeRuntime } from '../node/NodeRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x3D00;

class SkillEntry {
  id: string = '';
  name: string = '';
  description: string = '';
  enabled: boolean = true;
  builtin: boolean = false;
}

class EmptyParams {
}

class SkillIdParams {
  id: string = '';
}

class QrKeyParams {
  qrcode_key: string = '';
}

class WechatSetupParams {
  token: string = '';
  base_url: string = '';
}

class WechatVerifyParams {
  qrcode_key: string = '';
  verify_code: string = '';
}

@Component
export struct SkillsTab {
  runtime: NodeRuntime | undefined = undefined;

  @State avatarSkin: string = 'cat';
  @State skills: SkillEntry[] = [];
  @State isLoading: boolean = false;
  @State errorText: string = '';
  @State isConnected: boolean = false;
  @State statusText: string = 'Offline';

  // WeChat iLink binding state
  @State wechatEnabled: boolean = false;
  @State wechatMode: string = '';
  @State wechatLoading: boolean = false;
  @State wechatError: string = '';
  @State qrKey: string = '';
  @State qrImg: string = '';
  @State scanStatus: string = '';   // '' | waiting | scaned | confirmed | expired | need_verifycode | binded_redirect
  @State verifyCode: string = '';

  private wechatPolling: boolean = false;

  private statusTimer: number = -1;

  aboutToAppear() {
    this.avatarSkin = this.runtime?.prefs.getAvatarSkin() || 'cat';
    this.refreshStatus();
    this.statusTimer = setInterval(() => { this.refreshStatus(); }, 1000);
    void this.loadSkills();
    void this.loadChannelConfig();
  }

  aboutToDisappear() {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
    this.wechatPolling = false;
  }

  private refreshStatus() {
    if (this.runtime) {
      this.isConnected = this.runtime.isConnected;
      this.statusText = this.runtime.statusText;
    }
  }

  private async loadSkills() {
    if (!this.runtime?.isConnected) {
      this.errorText = '请先连接 Bonio 服务';
      this.skills = [];
      return;
    }
    this.isLoading = true;
    this.errorText = '';
    try {
      const response = await this.runtime.operatorSession.request('skills.list', new EmptyParams());
      const payload = (response.payload as Record<string, Object>) || {};
      const rawList = payload['skills'];
      const entries: SkillEntry[] = [];
      if (Array.isArray(rawList)) {
        rawList.forEach((item: Object) => {
          const raw = item as Record<string, Object>;
          const entry = new SkillEntry();
          entry.id = typeof raw['id'] === 'string' ? raw['id'] as string : '';
          entry.name = typeof raw['name'] === 'string' ? raw['name'] as string : '';
          entry.description = typeof raw['description'] === 'string' ? raw['description'] as string : '';
          entry.enabled = typeof raw['enabled'] === 'boolean' ? raw['enabled'] as boolean : true;
          entry.builtin = typeof raw['builtin'] === 'boolean' ? raw['builtin'] as boolean : false;
          if (entry.id) entries.push(entry);
        });
      }
      this.skills = entries;
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '技能列表加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  private async toggleSkill(entry: SkillEntry) {
    if (!this.runtime?.isConnected) return;
    const targetEnabled = !entry.enabled;
    try {
      const method = targetEnabled ? 'skills.enable' : 'skills.disable';
      const skillParams = new SkillIdParams();
      skillParams.id = entry.id;
      await this.runtime.operatorSession.request(method, skillParams);
      entry.enabled = targetEnabled;
      void this.loadSkills();
    } catch (error) {
      this.errorText = error instanceof Error ? error.message : '技能状态切换失败';
      void this.loadSkills();
    }
  }

  private selectAvatarSkin(skin: string): void {
    const normalized = skin === 'kun' ? 'kun' : 'cat';
    this.avatarSkin = normalized;
    this.runtime?.prefs.setAvatarSkin(normalized);
    AppStorage.setOrCreate<string>('avatarSkin', normalized);
  }

  // ── WeChat iLink QR binding ──
  private async loadChannelConfig() {
    if (!this.runtime?.isConnected) return;
    try {
      const response = await this.runtime.operatorSession.request('channel.config', new EmptyParams());
      const payload = (response.payload as Record<string, Object>) || {};
      this.wechatEnabled = payload['enabled'] === true;
      this.wechatMode = typeof payload['mode'] === 'string' ? payload['mode'] as string : '';
      if (this.wechatEnabled) {
        this.qrKey = '';
        this.qrImg = '';
        this.scanStatus = '';
      }
    } catch (error) {
      hilog.warn(DOMAIN, 'SkillsTab', 'loadChannelConfig failed: ' + (error instanceof Error ? error.message : String(error)));
    }
  }

  private async startWechatBinding() {
    if (!this.runtime?.isConnected) return;
    this.wechatPolling = false;
    this.wechatLoading = true;
    this.wechatError = '';
    this.qrKey = '';
    this.qrImg = '';
    this.scanStatus = 'waiting';
    this.verifyCode = '';
    try {
      const response = await this.runtime.operatorSession.request('channel.wechat.qrcode', new EmptyParams());
      const payload = (response.payload as Record<string, Object>) || {};
      const key = typeof payload['qrcode_key'] === 'string' ? payload['qrcode_key'] as string : '';
      const img = typeof payload['qrcode_img'] === 'string' ? payload['qrcode_img'] as string : '';
      if (!key) {
        this.wechatError = '获取二维码失败：缺少 qrcode_key';
        this.scanStatus = '';
        this.wechatLoading = false;
        return;
      }
      this.qrKey = key;
      this.qrImg = img;
      this.wechatLoading = false;
      this.wechatPolling = true;
      void this.pollQrStatus();
    } catch (error) {
      this.wechatError = error instanceof Error ? error.message : '获取二维码失败';
      this.scanStatus = '';
      this.wechatLoading = false;
    }
  }

  private async pollQrStatus() {
    // Serial long-poll: the server holds the request up to ~30s per poll.
    while (this.wechatPolling && this.qrKey) {
      const params = new QrKeyParams();
      params.qrcode_key = this.qrKey;
      try {
        const response = await this.runtime?.operatorSession.request('channel.wechat.status', params);
        if (!this.wechatPolling || !response) return;
        const payload = (response.payload as Record<string, Object>) || {};
        const status = typeof payload['status'] === 'string' ? payload['status'] as string : 'wait';
        const token = typeof payload['bot_token'] === 'string' ? payload['bot_token'] as string : '';
        const baseUrl = typeof payload['baseurl'] === 'string' ? payload['baseurl'] as string : '';

        if (status === 'confirmed' || status === 'binded_redirect') {
          this.wechatPolling = false;
          this.scanStatus = 'confirmed';
          if (token) {
            await this.setupWechat(token, baseUrl);
          } else {
            this.wechatEnabled = true;
            this.wechatMode = 'weixin';
            this.qrKey = '';
            this.qrImg = '';
          }
          return;
        } else if (status === 'scaned') {
          this.scanStatus = 'scaned';
        } else if (status === 'need_verifycode') {
          this.scanStatus = 'need_verifycode';
          this.wechatPolling = false;
          return;
        } else if (status === 'verify_code_blocked' || status === 'expired') {
          this.wechatPolling = false;
          this.scanStatus = 'expired';
          this.wechatError = '二维码已过期，请重新获取';
          this.qrKey = '';
          this.qrImg = '';
          return;
        } else {
          this.scanStatus = 'waiting';
        }
      } catch (error) {
        hilog.warn(DOMAIN, 'SkillsTab', 'pollQrStatus failed: ' + (error instanceof Error ? error.message : String(error)));
        if (this.wechatPolling) {
          // transient failure: keep polling after a short delay
          await new Promise<void>(resolve => setTimeout(resolve, 3000));
        }
      }
    }
  }

  private async setupWechat(token: string, baseUrl: string) {
    if (!this.runtime?.isConnected) return;
    try {
      const params = new WechatSetupParams();
      params.token = token;
      if (baseUrl) params.base_url = baseUrl;
      await this.runtime.operatorSession.request('channel.wechat.setup', params);
      this.wechatEnabled = true;
      this.wechatMode = 'weixin';
      this.qrKey = '';
      this.qrImg = '';
      this.wechatError = '';
    } catch (error) {
      this.wechatError = error instanceof Error ? error.message : '微信绑定保存失败';
      this.scanStatus = 'confirmed';
    }
  }

  private async submitVerifyCode() {
    const code = this.verifyCode.trim();
    if (!code || !this.qrKey) return;
    this.wechatPolling = true;
    this.scanStatus = 'waiting';
    const params = new WechatVerifyParams();
    params.qrcode_key = this.qrKey;
    params.verify_code = code;
    try {
      const response = await this.runtime?.operatorSession.request('channel.wechat.status', params);
      if (!response) return;
      const payload = (response.payload as Record<string, Object>) || {};
      const status = typeof payload['status'] === 'string' ? payload['status'] as string : 'wait';
      if (status === 'scaned' || status === 'confirmed' || status === 'binded_redirect') {
        this.verifyCode = '';
        if (status === 'confirmed' || status === 'binded_redirect') {
          const token = typeof payload['bot_token'] === 'string' ? payload['bot_token'] as string : '';
          const baseUrl = typeof payload['baseurl'] === 'string' ? payload['baseurl'] as string : '';
          this.wechatPolling = false;
          this.scanStatus = 'confirmed';
          if (token) await this.setupWechat(token, baseUrl);
        } else {
          this.wechatPolling = true;
          void this.pollQrStatus();
        }
      } else if (status === 'need_verifycode') {
        this.wechatError = '验证码不正确，请重新输入';
        this.scanStatus = 'need_verifycode';
        this.wechatPolling = false;
      } else if (status === 'verify_code_blocked' || status === 'expired') {
        this.wechatPolling = false;
        this.scanStatus = 'expired';
        this.wechatError = '验证码错误次数过多或二维码过期，请重新获取';
        this.qrKey = '';
        this.qrImg = '';
      } else {
        this.scanStatus = 'waiting';
        this.wechatPolling = true;
        void this.pollQrStatus();
      }
    } catch (error) {
      this.wechatError = error instanceof Error ? error.message : '验证码提交失败';
    }
  }

  private async disableWechat() {
    if (!this.runtime?.isConnected) return;
    this.wechatPolling = false;
    try {
      await this.runtime.operatorSession.request('channel.wechat.disable', new EmptyParams());
      this.wechatEnabled = false;
      this.wechatMode = '';
      this.qrKey = '';
      this.qrImg = '';
      this.scanStatus = '';
      this.wechatError = '';
    } catch (error) {
      this.wechatError = error instanceof Error ? error.message : '解绑失败';
    }
  }

  private scanStatusText(): string {
    if (this.scanStatus === 'scaned') return '已扫码，请在手机上确认登录';
    if (this.scanStatus === 'confirmed') return '绑定成功';
    if (this.scanStatus === 'expired') return '二维码已过期';
    if (this.scanStatus === 'need_verifycode') return '请在手机上查看验证码';
    return '请使用微信扫描二维码';
  }

  @Builder SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontColor('#0A59F7')
      .fontWeight(FontWeight.Medium)
      .width('100%')
      .padding({ left: 16, top: 20, bottom: 6 })
  }

  @Builder AvatarSkinRow() {
    Row() {
      Column() {
        Text('Skin Style')
          .fontSize(15)
          .fontColor('#333333')
          .fontWeight(FontWeight.Medium)
        Text(this.avatarSkin === 'kun' ? 'Pixel-art Kun avatar' : 'Lottie cat avatar')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Select([
        { value: 'Cat (Lottie)' },
        { value: 'Kun (Pixel)' }
      ])
        .selected(this.avatarSkin === 'kun' ? 1 : 0)
        .value(this.avatarSkin === 'kun' ? 'Kun (Pixel)' : 'Cat (Lottie)')
        .font({ size: 14, weight: FontWeight.Medium })
        .fontColor('#333333')
        .selectedOptionFont({ size: 14, weight: FontWeight.Medium })
        .selectedOptionFontColor('#0A59F7')
        .selectedOptionBgColor('#E8F0FE')
        .optionFont({ size: 14 })
        .optionFontColor('#333333')
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
        .height(36)
        .onSelect((index: number) => {
          this.selectAvatarSkin(index === 1 ? 'kun' : 'cat');
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }

  @Builder SkillRow(entry: SkillEntry) {
    Row() {
      Column() {
        Row() {
          Text(entry.name).fontSize(15).fontColor('#333333').fontWeight(FontWeight.Medium)
          if (entry.builtin) {
            Text('内置')
              .fontSize(10)
              .fontColor('#0A59F7')
              .backgroundColor('#E8F0FE')
              .borderRadius(4)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .margin({ left: 8 })
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(entry.description)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 3 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: entry.enabled })
        .selectedColor('#0A59F7')
        .onChange(() => {
          this.toggleSkill(entry);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
  }

  @Builder WechatRow() {
    Column() {
      // Already bound
      if (this.wechatEnabled && this.scanStatus !== 'waiting' && this.scanStatus !== 'scaned' && this.scanStatus !== 'need_verifycode') {
        Row() {
          Column() {
            Text('微信 iLink 已绑定')
              .fontSize(15)
              .fontColor('#2ECC71')
              .fontWeight(FontWeight.Medium)
            Text(this.wechatMode === 'weixin' ? '个人微信消息将通过 iLink 桥接到 agent' : 'Mode: ' + this.wechatMode)
              .fontSize(12)
              .fontColor('#999999')
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('解绑')
            .fontSize(13)
            .fontColor('#E53935')
            .backgroundColor('#FDECEA')
            .borderRadius(8)
            .height(32)
            .onClick(() => { void this.disableWechat(); })
        }
        .width('100%')
        .padding(16)
      } else {
        // Not bound / scanning
        Row() {
          Column() {
            Text('微信 iLink')
              .fontSize(15)
              .fontColor('#333333')
              .fontWeight(FontWeight.Medium)
            Text('扫码绑定个人微信，消息将桥接到 agent')
              .fontSize(12)
              .fontColor('#999999')
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (!this.qrKey) {
            Button(this.wechatLoading ? '获取中...' : '扫码绑定')
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor('#07C160')
              .borderRadius(8)
              .height(34)
              .enabled(!this.wechatLoading)
              .onClick(() => { void this.startWechatBinding(); })
          }
        }
        .width('100%')
        .padding(16)

        // QR code display
        if (this.qrKey) {
          Column() {
            Row() {
              LoadingProgress().width(20).height(20).color('#07C160')
              Text(this.scanStatusText())
                .fontSize(13)
                .fontColor('#333333')
                .margin({ left: 8 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 8, bottom: 8 })

            QRCode(this.qrImg)
              .width(200)
              .height(200)
              .color('#000000')
              .backgroundColor(Color.White)

            if (this.scanStatus === 'need_verifycode') {
              Row() {
                TextInput({ placeholder: '输入手机上的验证码', text: this.verifyCode })
                  .width(140)
                  .height(36)
                  .borderRadius(8)
                  .backgroundColor('#F5F5F5')
                  .onChange((value: string) => { this.verifyCode = value; })
                Button('确认')
                  .fontSize(13)
                  .fontColor(Color.White)
                  .backgroundColor('#07C160')
                  .borderRadius(8)
                  .height(36)
                  .margin({ left: 8 })
                  .onClick(() => { void this.submitVerifyCode(); })
              }
              .margin({ top: 12 })
            }

            Button('取消')
              .fontSize(13)
              .fontColor('#666666')
              .backgroundColor('#F0F0F0')
              .borderRadius(8)
              .height(32)
              .margin({ top: 12 })
              .onClick(() => {
                this.wechatPolling = false;
                this.qrKey = '';
                this.qrImg = '';
                this.scanStatus = '';
                this.verifyCode = '';
              })
          }
          .width('100%')
          .padding({ top: 4, bottom: 16 })
        }
      }

      if (this.wechatError) {
        Text(this.wechatError)
          .fontSize(12)
          .fontColor('#E53935')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 16, right: 16, bottom: 12 })
      }
    }
    .width('100%')
    .backgroundColor(Color.White)
  }

  build() {
    Column() {
      // Header
      Text('SKILLS')
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0A59F7')
        .width('100%')
        .margin({ bottom: 4 })
      Text('Avatar & Skills')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#333333')
        .width('100%')
        .margin({ bottom: 4 })
      Text('Choose your avatar skin, manage backend skills and bind WeChat.')
        .fontSize(13)
        .fontColor('#999999')
        .width('100%')
        .margin({ bottom: 12 })

      List({ space: 8 }) {
        // Avatar Skin Section
        ListItem() { this.SectionHeader('Avatar Skin') }
        ListItem() {
          this.AvatarSkinRow()
        }

        // WeChat iLink Section
        ListItem() { this.SectionHeader('WeChat iLink') }
        ListItem() {
          this.WechatRow()
        }

        // Skills Section
        ListItem() { this.SectionHeader('Backend Skills (DSH)') }
        if (this.isLoading) {
          ListItem() {
            Row() {
              LoadingProgress().width(28).height(28).color('#0A59F7')
              Text('Loading skills...').fontSize(14).fontColor('#999999').margin({ left: 12 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 24, bottom: 24 })
          }
        } else if (this.errorText) {
          ListItem() {
            Column() {
              Text(this.errorText)
                .fontSize(14)
                .fontColor('#E53935')
                .textAlign(TextAlign.Center)
                .width('100%')
              if (!this.isConnected) {
                Text('请前往 Settings 页签连接 Bonio 服务后查看后端技能。')
                  .fontSize(12)
                  .fontColor('#999999')
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .margin({ top: 8 })
              } else {
                Button('Retry')
                  .fontSize(14)
                  .fontColor(Color.White)
                  .backgroundColor('#0A59F7')
                  .borderRadius(8)
                  .margin({ top: 12 })
                  .onClick(() => { void this.loadSkills(); })
              }
            }
            .width('100%')
            .padding({ top: 24, bottom: 24 })
            .backgroundColor(Color.White)
          }
        } else if (this.skills.length === 0) {
          ListItem() {
            Text('No skills found on the backend.')
              .fontSize(14)
              .fontColor('#999999')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 24, bottom: 24 })
              .backgroundColor(Color.White)
          }
        } else {
          ForEach(this.skills, (skill: SkillEntry) => {
            ListItem() {
              this.SkillRow(skill)
            }
          }, (skill: SkillEntry) => skill.id)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FAFAFA')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FAFAFA')
  }
}