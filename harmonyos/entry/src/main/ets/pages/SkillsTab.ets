import { NodeRuntime } from '../node/NodeRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common, abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { SecurePrefs } from '../common/SecurePrefs';
import { CustomSkinManager, SkinItem } from '../common/CustomSkinManager';
import { AvatarCreatorDialog } from './AvatarCreatorDialog';

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

class ModelItem {
  id: string = '';
  name: string = '';
  provider: string = '';
  apiKey?: string;
  baseUrl?: string;

  constructor(id: string, name: string, provider: string, apiKey?: string, baseUrl?: string) {
    this.id = id;
    this.name = name;
    this.provider = provider;
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
  }
}

class ConfigSetParams {
  default_model: string = '';
  models?: Object[];
}

@Component
struct SettingToggleRow {
  title: string = '';
  subtitle: string = '';
  @Prop @Watch('onPropChange') isOn: boolean = false;
  @State private currentIsOn: boolean = false;
  onChange: (isOn: boolean) => Promise<boolean> | void = (_isOn: boolean) => {};

  aboutToAppear() {
    this.currentIsOn = this.isOn;
  }

  private onPropChange() {
    this.currentIsOn = this.isOn;
  }

  build() {
    Row() {
      Column() {
        Text(this.title).fontSize(15).fontColor('#333333').fontWeight(FontWeight.Medium)
        Text(this.subtitle).fontSize(12).fontColor('#999999').margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.currentIsOn })
        .selectedColor('#0A59F7')
        .onChange(async (value: boolean) => {
          if (value !== this.currentIsOn) {
            this.currentIsOn = value;
            const res = this.onChange(value);
            if (res instanceof Promise) {
              const accepted = await res;
              if (accepted !== value) {
                this.currentIsOn = accepted;
              }
            }
          }
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(Color.White)
  }
}

@Component
export struct SkillsTab {
  runtime: NodeRuntime | undefined = undefined;

  @State avatarSkin: string = 'cat';
  @State allSkins: SkinItem[] = [];
  @State skills: SkillEntry[] = [];
  @State isLoading: boolean = false;

  private creatorDialogController: CustomDialogController = new CustomDialogController({
    builder: AvatarCreatorDialog({
      onSkinCreated: (newSkin: SkinItem) => {
        this.loadAvailableSkins();
        this.selectAvatarSkin(newSkin.id);
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: true
  });
  @State errorText: string = '';
  @State isConnected: boolean = false;
  @State statusText: string = 'Offline';

  // Model config state
  @State defaultModel: string = 'glm-4.7';
  @State modelsList: ModelItem[] = [];
  @State isAddingModel: boolean = false;
  @State newModelId: string = '';
  @State newModelProvider: string = 'openai';
  @State newModelApiKey: string = '';
  @State newModelBaseUrl: string = '';

  // System Data Permissions state
  @State contactsEnabled: boolean = false;
  @State smsEnabled: boolean = false;
  @State notificationEnabled: boolean = true;
  @State calendarEnabled: boolean = false;
  @State memoEnabled: boolean = true;
  @State galleryEnabled: boolean = false;
  @State filesEnabled: boolean = false;

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

  async aboutToAppear() {
    if (!this.runtime) {
      this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
    }
    const context = getContext(this) as common.UIAbilityContext;
    try {
      await SecurePrefs.getInstance().init(context);
    } catch (_) {}

    this.loadAvailableSkins();
    this.avatarSkin = this.runtime?.prefs.getAvatarSkin() || SecurePrefs.getInstance().getAvatarSkin() || 'cat';
    this.refreshStatus();
    this.statusTimer = setInterval(() => {
      if (!this.runtime) {
        this.runtime = AppStorage.get<NodeRuntime>('nodeRuntime');
      }
      this.refreshStatus();
    }, 1000);
    void this.loadSkills();
    void this.loadChannelConfig();
    void this.loadModelConfig();
    await this.syncSystemDataPermissions();
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

  private loadAvailableSkins(): void {
    const manager = CustomSkinManager.getInstance();
    const context = getContext(this) as common.UIAbilityContext;
    manager.init(context);
    this.allSkins = manager.getAllSkins();
  }

  private selectAvatarSkin(skin: string): void {
    const valid = (skin === 'kun' || skin === 'mario' || skin === 'messi' || skin.startsWith('custom_')) ? skin : 'cat';
    this.avatarSkin = valid;
    this.runtime?.prefs.setAvatarSkin(valid);
    AppStorage.setOrCreate<string>('avatarSkin', valid);
  }

  private async loadModelConfig(): Promise<void> {
    this.defaultModel = (this.runtime?.prefs || SecurePrefs.getInstance()).getDefaultModel();
    const customModelsStr = (this.runtime?.prefs || SecurePrefs.getInstance()).getCustomModels();

    const presets: ModelItem[] = [
      new ModelItem('glm-4.7', 'GLM-4.7', 'glm'),
      new ModelItem('deepseek-v3', 'DeepSeek-V3', 'deepseek'),
      new ModelItem('deepseek-r1', 'DeepSeek-R1', 'deepseek'),
      new ModelItem('gpt-4o', 'GPT-4o', 'openai'),
      new ModelItem('claude-3-5-sonnet', 'Claude 3.5 Sonnet', 'anthropic'),
      new ModelItem('qwen-2.5-72b', 'Qwen 2.5', 'dashscope')
    ];

    try {
      const parsed = JSON.parse(customModelsStr) as ModelItem[];
      if (Array.isArray(parsed)) {
        parsed.forEach((m: ModelItem) => {
          if (m.id && !presets.some((p: ModelItem): boolean => p.id === m.id)) {
            presets.push(m);
          }
        });
      }
    } catch (_) {}

    this.modelsList = presets;

    if (this.runtime?.isConnected) {
      try {
        const res = await this.runtime.operatorSession.request('config.get', new EmptyParams());
        const payload = (res.payload as Record<string, Object>) || {};
        const serverDefault = payload['default_model'];
        if (typeof serverDefault === 'string' && serverDefault.length > 0) {
          this.defaultModel = serverDefault;
          (this.runtime.prefs || SecurePrefs.getInstance()).setDefaultModel(serverDefault);
        }
        const serverModels = payload['models'];
        if (Array.isArray(serverModels)) {
          serverModels.forEach((sm: Object) => {
            const raw = sm as Record<string, Object>;
            const mid = typeof raw['id'] === 'string' ? raw['id'] as string : '';
            const prov = typeof raw['provider'] === 'string' ? raw['provider'] as string : '';
            if (mid && !this.modelsList.some((p: ModelItem): boolean => p.id === mid)) {
              this.modelsList.push(new ModelItem(mid, mid, prov));
            }
          });
        }
      } catch (err) {
        hilog.warn(DOMAIN, 'SkillsTab', 'Failed to fetch config.get: %{public}s', JSON.stringify(err));
      }
    }
  }

  private async selectDefaultModel(modelId: string): Promise<void> {
    this.defaultModel = modelId;
    (this.runtime?.prefs || SecurePrefs.getInstance()).setDefaultModel(modelId);
    if (this.runtime?.isConnected) {
      try {
        const params = new ConfigSetParams();
        params.default_model = modelId;
        await this.runtime.operatorSession.request('config.set', params);
      } catch (err) {
        hilog.warn(DOMAIN, 'SkillsTab', 'Failed to set default model: %{public}s', JSON.stringify(err));
      }
    }
  }

  private async addCustomModel(): Promise<void> {
    const id = this.newModelId.trim();
    if (!id) return;
    const provider = this.newModelProvider.trim() || 'openai';
    const apiKey = this.newModelApiKey.trim();
    const baseUrl = this.newModelBaseUrl.trim();
    const newItem = new ModelItem(id, id, provider, apiKey, baseUrl);

    const updated = this.modelsList.filter((m: ModelItem): boolean => m.id !== id);
    updated.push(newItem);
    this.modelsList = updated;

    const customOnly = this.modelsList.filter((m: ModelItem): boolean =>
      !['glm-4.7', 'deepseek-v3', 'deepseek-r1', 'gpt-4o', 'claude-3-5-sonnet', 'qwen-2.5-72b'].includes(m.id)
    );
    (this.runtime?.prefs || SecurePrefs.getInstance()).setCustomModels(JSON.stringify(customOnly));

    await this.selectDefaultModel(id);
    this.isAddingModel = false;
    this.newModelId = '';
    this.newModelApiKey = '';
    this.newModelBaseUrl = '';
  }

  private getModelSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [];
    for (let i = 0; i < this.modelsList.length; i++) {
      opts.push({ value: this.modelsList[i].name || this.modelsList[i].id });
    }
    return opts;
  }

  private getCurrentModelIndex(): number {
    for (let i = 0; i < this.modelsList.length; i++) {
      if (this.modelsList[i].id === this.defaultModel) return i;
    }
    return 0;
  }

  private getCurrentModelDisplay(): string {
    for (let i = 0; i < this.modelsList.length; i++) {
      if (this.modelsList[i].id === this.defaultModel) {
        return this.modelsList[i].name || this.modelsList[i].id;
      }
    }
    return this.defaultModel || 'glm-4.7';
  }

  private async syncSystemDataPermissions(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    const prefs = this.runtime?.prefs || SecurePrefs.getInstance();
    try {
      await prefs.init(context);
    } catch (_) {}

    try {
      this.notificationEnabled = prefs.getNotificationEnabled();
      this.memoEnabled = prefs.getMemoEnabled();
      this.smsEnabled = prefs.getSmsReadEnabled();
      this.filesEnabled = prefs.getFilesEnabled();

      const atManager = abilityAccessCtrl.createAtManager();
      const tokenID = context.applicationInfo.accessTokenId;

      // 1. Contacts
      const contactsStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.READ_CONTACTS");
      const contactsGranted = (contactsStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      this.contactsEnabled = prefs.getContactsEnabled() && contactsGranted;
      if (!contactsGranted && prefs.getContactsEnabled()) {
        prefs.setContactsEnabled(false);
      }

      // 2. Calendar
      const calendarStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.READ_CALENDAR");
      const calendarGranted = (calendarStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      this.calendarEnabled = prefs.getCalendarEnabled() && calendarGranted;
      if (!calendarGranted && prefs.getCalendarEnabled()) {
        prefs.setCalendarEnabled(false);
      }

      // 3. Gallery
      const galleryStatus = await atManager.checkAccessToken(tokenID, "ohos.permission.READ_IMAGEVIDEO");
      const galleryGranted = (galleryStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      this.galleryEnabled = prefs.getGalleryEnabled() && galleryGranted;
      if (!galleryGranted && prefs.getGalleryEnabled()) {
        prefs.setGalleryEnabled(false);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'SkillsTab', `syncSystemDataPermissions failed: ${e}`);
    }
  }

  async requestPermission(permission: Permissions): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const context = getContext(this) as common.UIAbilityContext;
    try {
      const grantStatus = await atManager.requestPermissionsFromUser(context, [permission]);
      if (grantStatus.authResults.length > 0 && grantStatus.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
    } catch (e) {
      hilog.error(DOMAIN, 'SkillsTab', `Permission request failed: ${e}`);
    }
    return false;
  }

  private async handlePermissionToggle(
    permission: Permissions,
    isOn: boolean,
    onResult: (granted: boolean) => void
  ): Promise<boolean> {
    if (isOn) {
      const granted = await this.requestPermission(permission);
      onResult(granted);
      this.runtime?.refreshNodeCapabilities();
      return granted;
    } else {
      onResult(false);
      this.runtime?.refreshNodeCapabilities();
      return false;
    }
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
    Column({ space: 12 }) {
      // 1. Current skin selector & Creator button
      Row() {
        Column() {
          Text('当前皮肤')
            .fontSize(15)
            .fontColor('#1D2129')
            .fontWeight(FontWeight.Medium)
          Text(this.getSkinSubtitle())
            .fontSize(12)
            .fontColor('#86909C')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('🎨 制作皮肤')
          .height(34)
          .fontSize(13)
          .fontColor(Color.White)
          .backgroundColor('#0A59F7')
          .borderRadius(17)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            this.creatorDialogController.open();
          })
      }
      .width('100%')

      // 2. Skin Gallery (horizontal scroll of available cards)
      Scroll() {
        Row({ space: 10 }) {
          ForEach(this.allSkins, (skin: SkinItem) => {
            Column({ space: 6 }) {
              Row() {
                Text(skin.name.split(' ')[0])
                  .fontSize(13)
                  .fontWeight(this.avatarSkin === skin.id ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.avatarSkin === skin.id ? '#0A59F7' : '#1D2129')
                if (!skin.isBuiltin) {
                  Text('自制')
                    .fontSize(9)
                    .fontColor('#FF7D00')
                    .backgroundColor('#FFF7E8')
                    .borderRadius(3)
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    .margin({ left: 4 })
                }
              }

              Text(skin.subtitle)
                .fontSize(10)
                .fontColor('#86909C')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width(110)
            .padding(10)
            .borderRadius(10)
            .backgroundColor(this.avatarSkin === skin.id ? '#E8F0FE' : '#F7F8FA')
            .border({ width: 1.5, color: this.avatarSkin === skin.id ? '#0A59F7' : 'transparent' })
            .onClick(() => {
              this.selectAvatarSkin(skin.id);
            })
          }, (skin: SkinItem) => `${skin.id}-${skin.name}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }

  private getSkinSubtitle(): string {
    const current = this.allSkins.find(s => s.id === this.avatarSkin);
    if (current) return current.subtitle;
    switch (this.avatarSkin) {
      case 'kun': return '经典高密度像素鸡伴侣';
      case 'mario': return '任天堂经典水管工 HD像素';
      case 'messi': return '阿根廷10号队长 HD像素';
      default: return 'Lottie 矢量动效猫咪';
    }
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

  @Builder ModelConfigCard() {
    Column() {
      Row() {
        Column() {
          Text('默认大模型')
            .fontSize(15)
            .fontColor('#333333')
            .fontWeight(FontWeight.Medium)
          Text('当前智能体使用的模型')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 3 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.modelsList.length > 0) {
          Select(this.getModelSelectOptions())
            .selected(this.getCurrentModelIndex())
            .value(this.getCurrentModelDisplay())
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
              if (index >= 0 && index < this.modelsList.length) {
                void this.selectDefaultModel(this.modelsList[index].id);
              }
            })
        }
      }
      .width('100%')

      Row() {
        Text(this.isAddingModel ? '收起' : '+ 添加自定义模型')
          .fontSize(13)
          .fontColor('#0A59F7')
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.isAddingModel = !this.isAddingModel;
          })
      }
      .width('100%')
      .margin({ top: 12 })

      if (this.isAddingModel) {
        Column() {
          TextInput({ placeholder: 'Model ID (例如 qwen-max)', text: this.newModelId })
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
            .margin({ top: 8, bottom: 8 })
            .onChange((val: string) => { this.newModelId = val; })

          TextInput({ placeholder: 'Provider (例如 openai / dashscope)', text: this.newModelProvider })
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
            .margin({ bottom: 8 })
            .onChange((val: string) => { this.newModelProvider = val; })

          TextInput({ placeholder: 'API Key (可选)', text: this.newModelApiKey })
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(8)
            .type(InputType.Password)
            .backgroundColor('#F5F5F5')
            .margin({ bottom: 8 })
            .onChange((val: string) => { this.newModelApiKey = val; })

          TextInput({ placeholder: 'Base URL (可选)', text: this.newModelBaseUrl })
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(8)
            .backgroundColor('#F5F5F5')
            .margin({ bottom: 10 })
            .onChange((val: string) => { this.newModelBaseUrl = val; })

          Button('保存并使用此模型')
            .width('100%')
            .height(36)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .backgroundColor('#0A59F7')
            .fontColor(Color.White)
            .borderRadius(8)
            .onClick(() => {
              void this.addCustomModel();
            })
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Color.White)
  }

  build() {
    Column() {
      List({ space: 8 }) {
        // 1. Avatar Skin Section
        ListItem() { this.SectionHeader('Avatar 皮肤') }
        ListItem() {
          this.AvatarSkinRow()
        }

        // 2. LLM Model Section
        ListItem() { this.SectionHeader('大模型') }
        ListItem() {
          this.ModelConfigCard()
        }

        // 3. WeChat iLink Section
        ListItem() { this.SectionHeader('WeChat 连接') }
        ListItem() {
          this.WechatRow()
        }

        // 4. Skills Section
        ListItem() { this.SectionHeader('Skills 技能') }
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

        // 5. System Data Permissions Section
        ListItem() { this.SectionHeader('系统数据授权访问范围') }
        ListItem() {
          SettingToggleRow({
            title: '通讯录',
            subtitle: '允许智能体读取联系人信息',
            isOn: this.contactsEnabled,
            onChange: async (isOn: boolean): Promise<boolean> => {
              return await this.handlePermissionToggle("ohos.permission.READ_CONTACTS" as Permissions, isOn, (granted: boolean) => {
                this.contactsEnabled = granted;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setContactsEnabled(granted);
              });
            }
          })
        }
        ListItem() {
          SettingToggleRow({
            title: '短信',
            subtitle: '允许智能体读取和检索短信内容',
            isOn: this.smsEnabled,
            onChange: async (isOn: boolean): Promise<boolean> => {
              if (isOn) {
                // 优先向系统请求权限弹窗；系统限制时通过 DSH root 数据库直接读取
                const granted = await this.requestPermission("ohos.permission.READ_MESSAGES" as Permissions);
                this.smsEnabled = true;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setSmsReadEnabled(true);
                this.runtime?.refreshNodeCapabilities();
                return true;
              } else {
                this.smsEnabled = false;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setSmsReadEnabled(false);
                this.runtime?.refreshNodeCapabilities();
                return false;
              }
            }
          })
        }
        ListItem() {
          SettingToggleRow({
            title: '通知',
            subtitle: '允许智能体感知各应用即时通知',
            isOn: this.notificationEnabled,
            onChange: (isOn: boolean) => {
              this.notificationEnabled = isOn;
              (this.runtime?.prefs || SecurePrefs.getInstance()).setNotificationEnabled(isOn);
              this.runtime?.refreshNodeCapabilities();
            }
          })
        }
        ListItem() {
          SettingToggleRow({
            title: '日历',
            subtitle: '允许智能体读取日程与日历',
            isOn: this.calendarEnabled,
            onChange: async (isOn: boolean): Promise<boolean> => {
              return await this.handlePermissionToggle("ohos.permission.READ_CALENDAR" as Permissions, isOn, (granted: boolean) => {
                this.calendarEnabled = granted;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setCalendarEnabled(granted);
              });
            }
          })
        }
        ListItem() {
          SettingToggleRow({
            title: '备忘录',
            subtitle: '允许智能体读取和记录便签备忘',
            isOn: this.memoEnabled,
            onChange: (isOn: boolean) => {
              this.memoEnabled = isOn;
              (this.runtime?.prefs || SecurePrefs.getInstance()).setMemoEnabled(isOn);
              this.runtime?.refreshNodeCapabilities();
            }
          })
        }
        ListItem() {
          SettingToggleRow({
            title: '图库',
            subtitle: '允许智能体读取相册与图片媒体',
            isOn: this.galleryEnabled,
            onChange: async (isOn: boolean): Promise<boolean> => {
              return await this.handlePermissionToggle("ohos.permission.READ_IMAGEVIDEO" as Permissions, isOn, (granted: boolean) => {
                this.galleryEnabled = granted;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setGalleryEnabled(granted);
              });
            }
          })
        }
        ListItem() {
          SettingToggleRow({
            title: '文管',
            subtitle: '允许智能体访问文档与本地文件',
            isOn: this.filesEnabled,
            onChange: async (isOn: boolean): Promise<boolean> => {
              if (isOn) {
                const granted = await this.requestPermission("ohos.permission.READ_WRITE_DOCUMENTS_DIRECTORY" as Permissions);
                this.filesEnabled = true;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setFilesEnabled(true);
                this.runtime?.refreshNodeCapabilities();
                return true;
              } else {
                this.filesEnabled = false;
                (this.runtime?.prefs || SecurePrefs.getInstance()).setFilesEnabled(false);
                this.runtime?.refreshNodeCapabilities();
                return false;
              }
            }
          })
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