import 'package:shared_preferences/shared_preferences.dart';

enum AppLocale {
  zh('zh', '中文'),
  en('en', 'English');

  final String code;
  final String label;
  const AppLocale(this.code, this.label);

  static AppLocale fromCode(String? code) {
    if (code == 'en') return AppLocale.en;
    return AppLocale.zh;
  }
}

abstract class S {
  static S current = _SZh();

  static void setLocale(AppLocale locale) {
    current = locale == AppLocale.en ? _SEn() : _SZh();
  }

  static Future<AppLocale> loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    return AppLocale.fromCode(prefs.getString('app.locale'));
  }

  static Future<void> saveLocale(AppLocale locale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app.locale', locale.code);
  }

  // ── App ──
  String get appName;
  String get appNameShort;
  String get avatarWindowTitle;

  // ── Navigation ──
  String get tabChat;
  String get tabServer;
  String get tabMemory;
  String get tabMarket;
  String get tabSettings;

  // ── Right-click menu ──
  String get menuTakeNote;
  String get menuAiLens;
  String get menuSearchSimilar;
  String get menuSwitchWindow;

  // ── Chat ──
  String get chatConnectToStart;
  String get chatDisconnected;
  String get chatNewSession;
  String get chatRefresh;
  String get chatSendToStart;
  String get chatCopy;
  String get chatCopied;
  String get chatFailed;
  String get chatStreamInterrupted;
  String get chatGatewayNotReady;

  // ── Chat composer ──
  String get composerThinking;
  String get composerOff;
  String get composerLow;
  String get composerMedium;
  String get composerHigh;
  String get composerHint;
  String get composerConnectHint;
  String get composerStop;
  String get composerSend;

  // ── Server tab ──
  String get serverTitle;
  String get serverGatewayConnection;
  String get serverGateway;
  String get serverOpenClaw;
  String get serverHiClaw;
  String get serverOpenClawDesc;
  String get serverHiClawDesc;
  String get serverHost;
  String get serverPort;
  String get serverToken;
  String get serverTls;
  String get serverDisconnect;
  String get serverConnect;
  String get serverModelConfig;
  String get serverDefaultModel;
  String get serverNotSet;
  String get serverConfiguredModels;
  String get serverProviders;
  String get serverLoadingConfig;
  String get serverConnectToView;
  String get serverConfigureModels;
  String get serverInfo;
  String get serverAddress;
  String get serverNodeSession;
  String get serverUnknown;
  String get serverConnected;
  String get serverOffline;
  String get serverSkills;
  String get serverNotConnected;
  String get serverNoSkills;
  String get serverBuiltIn;
  String get serverInstalled;
  String get serverRemoveSkillTitle;
  String get serverRemoveSkillConfirm;
  String get serverInstallSkill;
  String get serverSkillId;
  String get serverSkillContent;
  String serverModelsCount(int n);
  String serverProvidersCount(int n);
  String serverSkillsTotal(int n);
  String serverRemoveSkillBody(String name);

  // ── Model config screen ──
  String get modelConfigTitle;
  String get modelSave;
  String get modelDefaultModel;
  String get modelSelectDefault;
  String get modelModels;
  String get modelAddModel;
  String get modelNoModels;
  String get modelRemove;

  // ── Settings tab ──
  String get settingsTitle;
  String get settingsAbout;
  String get settingsAvatar;
  String get settingsAvatarDesc;
  String get settingsShowFloating;
  String get settingsShowFloatingSub;
  String get settingsSpeakReplies;
  String get settingsSpeakRepliesSub;
  String get settingsLanguage;
  String get settingsLanguageSub;
  String get settingsKeyboard;
  String get settingsSendMessage;
  String get settingsNewLine;
  String get settingsCapabilities;
  String get settingsAppVersion;
  String get settingsPlatform;
  String get settingsOsVersion;
  String get settingsGatewayProtocol;
  String get capChat;
  String get capAvatar;
  String get capConfig;
  String get capSession;
  String get capDeviceAuth;
  String get capDeviceInfo;
  String capCamera(int count);
  String get capCameraDetecting;
  String get capCameraNone;
  String get capLocation;
  String get capSms;

  // ── Memory tab ──
  String get memoryTitle;
  String get memorySearchHint;
  String get memoryAll;
  String get memoryNoNotes;
  String get memoryNoNotesHint;
  String get memoryAnalyzing;
  String get memoryDeleteTitle;
  String get memoryDeleteConfirm;

  // ── Marketplace tab ──
  String get marketSkills;
  String get marketModels;
  String get marketThemes;
  String get marketSearchHint;
  String marketNoSkills(String query);
  String get marketTitle;
  String get marketSubtitle;
  String get marketDownloading;
  String get marketInstalling;
  String get marketInstallSuccess;
  String get marketNotConnected;
  String get marketModelTitle;
  String get marketModelPlaceholder;
  String get marketThemeTitle;
  String get marketThemePlaceholder;

  // ── Search similar ──
  String get searchTitle;
  String get searchInitializing;
  String get searchOpening;
  String get searchUploading;
  String get searchUploaded;
  String get searchResultsLoaded;
  String searchInitFailed(String e);
  String get searchManualHint;
  String searchUploadFailed(String e);
  String get searchRetry;

  // ── Avatar bubbles ──
  String get bubbleSearching;
  String get bubbleCapturing;
  String get bubbleCaptured;
  String bubbleSaved(String tags);
  String get bubbleCaptureFailed;
  String get bubbleReceived;
  String get bubbleAnalyzing;
  String bubbleDigested(String tags);
  String get bubbleCantEat;
  String get bubbleCantDigest;
  String get bubbleImageAttachment;

  // ── Common ──
  String get cancel;
  String get remove;
  String get install;
  String get done;
  String get delete;

  // ── Lens overlay ──
  String get lensCancel;
  String get lensUndo;
  String get lensConfirm;

  // ── Avatar overlay ──
  String get avatarAskHint;
  String get avatarAddAttachment;

  // ── Tray ──
  String get trayShow;
  String get trayExit;

  // ── Connection statuses ──
  String get statusOffline;
  String get statusConnecting;
  String get statusReconnecting;
  String get statusConnected;
  String get statusConnectedNodeOffline;
  String statusGatewayError(String e);
}

// ═══════════════════════════════════════════════════════════════════════════════
// Chinese
// ═══════════════════════════════════════════════════════════════════════════════

class _SZh extends S {
  @override String get appName => '波妞 Desktop';
  @override String get appNameShort => '波妞';
  @override String get avatarWindowTitle => '波妞 Avatar';

  @override String get tabChat => '聊天';
  @override String get tabServer => '服务';
  @override String get tabMemory => '记忆';
  @override String get tabMarket => '市场';
  @override String get tabSettings => '设置';

  @override String get menuTakeNote => '记一记';
  @override String get menuAiLens => '圈一圈';
  @override String get menuSearchSimilar => '搜同款';
  @override String get menuSwitchWindow => '切换窗口';

  @override String get chatConnectToStart => '连接网关开始聊天';
  @override String get chatDisconnected => '已断开';
  @override String get chatNewSession => '新会话';
  @override String get chatRefresh => '刷新';
  @override String get chatSendToStart => '发送消息开始聊天';
  @override String get chatCopy => '复制';
  @override String get chatCopied => '已复制到剪贴板';
  @override String get chatFailed => '聊天失败';
  @override String get chatStreamInterrupted => '事件流中断，请尝试刷新。';
  @override String get chatGatewayNotReady => '网关未就绪，无法发送';

  @override String get composerThinking => '思考：';
  @override String get composerOff => '关';
  @override String get composerLow => '低';
  @override String get composerMedium => '中';
  @override String get composerHigh => '高';
  @override String get composerHint => '输入消息... (Enter 发送, Shift+Enter 换行)';
  @override String get composerConnectHint => '请先连接网关';
  @override String get composerStop => '停止';
  @override String get composerSend => '发送';

  @override String get serverTitle => '服务';
  @override String get serverGatewayConnection => '网关连接';
  @override String get serverGateway => '网关';
  @override String get serverOpenClaw => 'OpenClaw';
  @override String get serverHiClaw => 'HiClaw';
  @override String get serverOpenClawDesc => '连接远程 OpenClaw 云服务';
  @override String get serverHiClawDesc => '连接本地 HiClaw 实例';
  @override String get serverHost => '主机';
  @override String get serverPort => '端口';
  @override String get serverToken => '令牌 (可选)';
  @override String get serverTls => 'TLS';
  @override String get serverDisconnect => '断开';
  @override String get serverConnect => '连接';
  @override String get serverModelConfig => '模型配置';
  @override String get serverDefaultModel => '默认模型';
  @override String get serverNotSet => '(未设置)';
  @override String get serverConfiguredModels => '已配置模型';
  @override String get serverProviders => '提供商';
  @override String get serverLoadingConfig => '正在加载配置...';
  @override String get serverConnectToView => '连接后查看配置';
  @override String get serverConfigureModels => '配置模型';
  @override String get serverInfo => '服务信息';
  @override String get serverAddress => '地址';
  @override String get serverNodeSession => 'Node 会话';
  @override String get serverUnknown => '未知';
  @override String get serverConnected => '已连接';
  @override String get serverOffline => '离线';
  @override String get serverSkills => '技能';
  @override String get serverNotConnected => '未连接到服务器';
  @override String get serverNoSkills => '未发现技能';
  @override String get serverBuiltIn => '内置';
  @override String get serverInstalled => '已安装';
  @override String get serverRemoveSkillTitle => '移除技能';
  @override String get serverRemoveSkillConfirm => '此操作不可撤销。';
  @override String get serverInstallSkill => '安装技能';
  @override String get serverSkillId => '技能 ID';
  @override String get serverSkillContent => 'SKILL.md 内容';
  @override String serverModelsCount(int n) => '$n 个模型';
  @override String serverProvidersCount(int n) => '$n 个提供商';
  @override String serverSkillsTotal(int n) => '共 $n 个';
  @override String serverRemoveSkillBody(String name) => '确定要移除 "$name" 吗？此操作不可撤销。';

  @override String get modelConfigTitle => '模型配置';
  @override String get modelSave => '保存';
  @override String get modelDefaultModel => '默认模型';
  @override String get modelSelectDefault => '选择默认模型';
  @override String get modelModels => '模型';
  @override String get modelAddModel => '添加模型';
  @override String get modelNoModels => '尚未配置模型，点击上方添加。';
  @override String get modelRemove => '移除模型';

  @override String get settingsTitle => '设置';
  @override String get settingsAbout => '关于';
  @override String get settingsAvatar => '形象';
  @override String get settingsAvatarDesc => '独立桌面窗口（主窗口最小化时仍可见），响应 avatar.command 事件，可拖拽移动。';
  @override String get settingsShowFloating => '显示悬浮形象窗口';
  @override String get settingsShowFloatingSub => '连接后打开置顶的宠物窗口';
  @override String get settingsSpeakReplies => '朗读助手回复';
  @override String get settingsSpeakRepliesSub => '每轮对话结束后朗读回复内容';
  @override String get settingsLanguage => '语言';
  @override String get settingsLanguageSub => '切换界面显示语言';
  @override String get settingsKeyboard => '键盘快捷键';
  @override String get settingsSendMessage => '发送消息';
  @override String get settingsNewLine => '换行';
  @override String get settingsCapabilities => '桌面能力';
  @override String get settingsAppVersion => '应用版本';
  @override String get settingsPlatform => '平台';
  @override String get settingsOsVersion => '系统版本';
  @override String get settingsGatewayProtocol => '网关协议';
  @override String get capChat => '聊天';
  @override String get capAvatar => '形象（网关事件）';
  @override String get capConfig => '配置管理';
  @override String get capSession => '会话管理';
  @override String get capDeviceAuth => 'Ed25519 设备认证';
  @override String get capDeviceInfo => '设备信息（Node）';
  @override String capCamera(int count) => '摄像头（检测到 $count 个）';
  @override String get capCameraDetecting => '摄像头（检测中...）';
  @override String get capCameraNone => '摄像头（未检测到）';
  @override String get capLocation => '定位';
  @override String get capSms => '短信';

  @override String get memoryTitle => '记忆';
  @override String get memorySearchHint => '搜索笔记...';
  @override String get memoryAll => '全部';
  @override String get memoryNoNotes => '还没有笔记';
  @override String get memoryNoNotesHint => '右键波妞选择"记一记"来保存内容，\n或者拖拽文件/图片/文字到波妞身上。';
  @override String get memoryAnalyzing => '分析中...';
  @override String get memoryDeleteTitle => '删除笔记';
  @override String get memoryDeleteConfirm => '确定要删除这条笔记吗？此操作不可撤销。';

  @override String get marketSkills => '技能';
  @override String get marketModels => '模型';
  @override String get marketThemes => '主题';
  @override String get marketSearchHint => '在 ClawHub 搜索技能...';
  @override String marketNoSkills(String query) => '未找到 "$query" 相关技能';
  @override String get marketTitle => 'ClawHub 市场';
  @override String get marketSubtitle => '探索并安装社区技能来扩展波妞的能力';
  @override String get marketDownloading => '下载中...';
  @override String get marketInstalling => '安装中...';
  @override String get marketInstallSuccess => '安装成功！';
  @override String get marketNotConnected => '未连接到服务器';
  @override String get marketModelTitle => '模型与提供商市场';
  @override String get marketModelPlaceholder => '模型市场即将上线...';
  @override String get marketThemeTitle => '主题市场';
  @override String get marketThemePlaceholder => '主题市场即将上线...';

  @override String get searchTitle => '搜同款';
  @override String get searchInitializing => '正在初始化搜索...';
  @override String get searchOpening => '正在打开淘宝搜图...';
  @override String get searchUploading => '正在上传图片...';
  @override String get searchUploaded => '已上传图片，等待搜索结果...';
  @override String get searchResultsLoaded => '搜索结果已加载';
  @override String searchInitFailed(String e) => '初始化失败: $e';
  @override String get searchManualHint => '自动上传未成功，请手动点击相机图标上传图片';
  @override String searchUploadFailed(String e) => '上传失败: $e';
  @override String get searchRetry => '重新搜索';

  @override String get bubbleSearching => '搜同款中...';
  @override String get bubbleCapturing => '捕捉中...';
  @override String get bubbleCaptured => '捕捉成功！分析中...';
  @override String bubbleSaved(String tags) => '已存入 $tags 喵！';
  @override String get bubbleCaptureFailed => '捕捉失败了喵...';
  @override String get bubbleReceived => '收到投喂喵~';
  @override String get bubbleAnalyzing => '已存入！分析中...';
  @override String bubbleDigested(String tags) => '已消化 $tags 喵！';
  @override String get bubbleCantEat => '这个吃不了喵...';
  @override String get bubbleCantDigest => '消化不了喵...';
  @override String get bubbleImageAttachment => '[图片附件]';

  @override String get cancel => '取消';
  @override String get remove => '移除';
  @override String get install => '安装';
  @override String get done => '完成';
  @override String get delete => '删除';

  @override String get lensCancel => '取消';
  @override String get lensUndo => '撤回';
  @override String get lensConfirm => '确认';

  @override String get avatarAskHint => '问点什么...';
  @override String get avatarAddAttachment => '添加附件';

  @override String get trayShow => '显示';
  @override String get trayExit => '退出';

  @override String get statusOffline => '离线';
  @override String get statusConnecting => '连接中...';
  @override String get statusReconnecting => '重连中...';
  @override String get statusConnected => '已连接';
  @override String get statusConnectedNodeOffline => '已连接（node 离线）';
  @override String statusGatewayError(String e) => '网关错误: $e';
}

// ═══════════════════════════════════════════════════════════════════════════════
// English
// ═══════════════════════════════════════════════════════════════════════════════

class _SEn extends S {
  @override String get appName => 'Bonio Desktop';
  @override String get appNameShort => 'Bonio';
  @override String get avatarWindowTitle => 'Bonio Avatar';

  @override String get tabChat => 'Chat';
  @override String get tabServer => 'Server';
  @override String get tabMemory => 'Memory';
  @override String get tabMarket => 'Market';
  @override String get tabSettings => 'Settings';

  @override String get menuTakeNote => 'Take Note';
  @override String get menuAiLens => 'AI Lens';
  @override String get menuSearchSimilar => 'Search Similar';
  @override String get menuSwitchWindow => 'Switch Window';

  @override String get chatConnectToStart => 'Connect to a gateway to start chatting';
  @override String get chatDisconnected => 'Disconnected';
  @override String get chatNewSession => 'New session';
  @override String get chatRefresh => 'Refresh';
  @override String get chatSendToStart => 'Send a message to start';
  @override String get chatCopy => 'Copy';
  @override String get chatCopied => 'Copied to clipboard';
  @override String get chatFailed => 'Chat failed';
  @override String get chatStreamInterrupted => 'Event stream interrupted; try refreshing.';
  @override String get chatGatewayNotReady => 'Gateway not ready; cannot send';

  @override String get composerThinking => 'Thinking: ';
  @override String get composerOff => 'off';
  @override String get composerLow => 'low';
  @override String get composerMedium => 'medium';
  @override String get composerHigh => 'high';
  @override String get composerHint => 'Type a message... (Enter to send, Shift+Enter for newline)';
  @override String get composerConnectHint => 'Connect to send messages';
  @override String get composerStop => 'Stop';
  @override String get composerSend => 'Send';

  @override String get serverTitle => 'Server';
  @override String get serverGatewayConnection => 'Gateway Connection';
  @override String get serverGateway => 'Gateway';
  @override String get serverOpenClaw => 'OpenClaw';
  @override String get serverHiClaw => 'HiClaw';
  @override String get serverOpenClawDesc => 'Connect to remote OpenClaw cloud service';
  @override String get serverHiClawDesc => 'Connect to local HiClaw instance';
  @override String get serverHost => 'Host';
  @override String get serverPort => 'Port';
  @override String get serverToken => 'Token (optional)';
  @override String get serverTls => 'TLS';
  @override String get serverDisconnect => 'Disconnect';
  @override String get serverConnect => 'Connect';
  @override String get serverModelConfig => 'Model Configuration';
  @override String get serverDefaultModel => 'Default Model';
  @override String get serverNotSet => '(not set)';
  @override String get serverConfiguredModels => 'Configured Models';
  @override String get serverProviders => 'Providers';
  @override String get serverLoadingConfig => 'Loading configuration...';
  @override String get serverConnectToView => 'Connect to view configuration';
  @override String get serverConfigureModels => 'Configure Models';
  @override String get serverInfo => 'Server Info';
  @override String get serverAddress => 'Address';
  @override String get serverNodeSession => 'Node Session';
  @override String get serverUnknown => 'Unknown';
  @override String get serverConnected => 'Connected';
  @override String get serverOffline => 'Offline';
  @override String get serverSkills => 'Skills';
  @override String get serverNotConnected => 'Not connected to server';
  @override String get serverNoSkills => 'No skills found';
  @override String get serverBuiltIn => 'Built-in';
  @override String get serverInstalled => 'Installed';
  @override String get serverRemoveSkillTitle => 'Remove Skill';
  @override String get serverRemoveSkillConfirm => 'This cannot be undone.';
  @override String get serverInstallSkill => 'Install Skill';
  @override String get serverSkillId => 'Skill ID';
  @override String get serverSkillContent => 'SKILL.md Content';
  @override String serverModelsCount(int n) => '$n model(s)';
  @override String serverProvidersCount(int n) => '$n provider(s)';
  @override String serverSkillsTotal(int n) => '$n total';
  @override String serverRemoveSkillBody(String name) => 'Remove "$name"? This cannot be undone.';

  @override String get modelConfigTitle => 'Model Configuration';
  @override String get modelSave => 'Save';
  @override String get modelDefaultModel => 'Default Model';
  @override String get modelSelectDefault => 'Select default model';
  @override String get modelModels => 'Models';
  @override String get modelAddModel => 'Add Model';
  @override String get modelNoModels => 'No models configured. Add one to get started.';
  @override String get modelRemove => 'Remove model';

  @override String get settingsTitle => 'Settings';
  @override String get settingsAbout => 'About';
  @override String get settingsAvatar => 'Avatar';
  @override String get settingsAvatarDesc => 'Separate desktop window (stays visible when the main window is minimized). Reacts to avatar.command; drag to move.';
  @override String get settingsShowFloating => 'Show floating avatar window';
  @override String get settingsShowFloatingSub => 'When connected, opens an always-on-top pet window';
  @override String get settingsSpeakReplies => 'Speak assistant replies';
  @override String get settingsSpeakRepliesSub => 'Read the assistant message aloud when a turn completes';
  @override String get settingsLanguage => 'Language';
  @override String get settingsLanguageSub => 'Switch display language';
  @override String get settingsKeyboard => 'Keyboard Shortcuts';
  @override String get settingsSendMessage => 'Send Message';
  @override String get settingsNewLine => 'New Line';
  @override String get settingsCapabilities => 'Desktop Capabilities';
  @override String get settingsAppVersion => 'App Version';
  @override String get settingsPlatform => 'Platform';
  @override String get settingsOsVersion => 'OS Version';
  @override String get settingsGatewayProtocol => 'Gateway Protocol';
  @override String get capChat => 'Chat';
  @override String get capAvatar => 'Avatar (gateway events)';
  @override String get capConfig => 'Config Management';
  @override String get capSession => 'Session Management';
  @override String get capDeviceAuth => 'Ed25519 Device Auth';
  @override String get capDeviceInfo => 'Device Info (Node)';
  @override String capCamera(int count) => 'Camera ($count detected)';
  @override String get capCameraDetecting => 'Camera (detecting...)';
  @override String get capCameraNone => 'Camera (none detected)';
  @override String get capLocation => 'Location';
  @override String get capSms => 'SMS';

  @override String get memoryTitle => 'Memory';
  @override String get memorySearchHint => 'Search notes...';
  @override String get memoryAll => 'All';
  @override String get memoryNoNotes => 'No notes yet';
  @override String get memoryNoNotesHint => 'Right-click Bonio and select "Take Note" to save content,\nor drag files/images/text onto Bonio.';
  @override String get memoryAnalyzing => 'Analyzing...';
  @override String get memoryDeleteTitle => 'Delete Note';
  @override String get memoryDeleteConfirm => 'Are you sure you want to delete this note? This cannot be undone.';

  @override String get marketSkills => 'Skills';
  @override String get marketModels => 'Models';
  @override String get marketThemes => 'Themes';
  @override String get marketSearchHint => 'Search skills on ClawHub...';
  @override String marketNoSkills(String query) => 'No skills found for "$query"';
  @override String get marketTitle => 'ClawHub Marketplace';
  @override String get marketSubtitle => 'Discover and install community skills to extend Bonio';
  @override String get marketDownloading => 'Downloading...';
  @override String get marketInstalling => 'Installing...';
  @override String get marketInstallSuccess => 'Installed successfully!';
  @override String get marketNotConnected => 'Not connected to server';
  @override String get marketModelTitle => 'Model & Provider Marketplace';
  @override String get marketModelPlaceholder => 'Model marketplace coming soon...';
  @override String get marketThemeTitle => 'Theme Marketplace';
  @override String get marketThemePlaceholder => 'Theme marketplace coming soon...';

  @override String get searchTitle => 'Search Similar';
  @override String get searchInitializing => 'Initializing search...';
  @override String get searchOpening => 'Opening Taobao image search...';
  @override String get searchUploading => 'Uploading image...';
  @override String get searchUploaded => 'Image uploaded, waiting for results...';
  @override String get searchResultsLoaded => 'Search results loaded';
  @override String searchInitFailed(String e) => 'Initialization failed: $e';
  @override String get searchManualHint => 'Auto-upload failed. Please click the camera icon to upload manually.';
  @override String searchUploadFailed(String e) => 'Upload failed: $e';
  @override String get searchRetry => 'Retry search';

  @override String get bubbleSearching => 'Searching...';
  @override String get bubbleCapturing => 'Capturing...';
  @override String get bubbleCaptured => 'Captured! Analyzing...';
  @override String bubbleSaved(String tags) => 'Saved $tags!';
  @override String get bubbleCaptureFailed => 'Capture failed...';
  @override String get bubbleReceived => 'Yum, received!';
  @override String get bubbleAnalyzing => 'Saved! Analyzing...';
  @override String bubbleDigested(String tags) => 'Digested $tags!';
  @override String get bubbleCantEat => "Can't eat this...";
  @override String get bubbleCantDigest => "Can't digest...";
  @override String get bubbleImageAttachment => '[Image attachment]';

  @override String get cancel => 'Cancel';
  @override String get remove => 'Remove';
  @override String get install => 'Install';
  @override String get done => 'Done';
  @override String get delete => 'Delete';

  @override String get lensCancel => 'Cancel';
  @override String get lensUndo => 'Undo';
  @override String get lensConfirm => 'Confirm';

  @override String get avatarAskHint => 'Ask something...';
  @override String get avatarAddAttachment => 'Add attachment';

  @override String get trayShow => 'Show';
  @override String get trayExit => 'Exit';

  @override String get statusOffline => 'Offline';
  @override String get statusConnecting => 'Connecting...';
  @override String get statusReconnecting => 'Reconnecting...';
  @override String get statusConnected => 'Connected';
  @override String get statusConnectedNodeOffline => 'Connected (node offline)';
  @override String statusGatewayError(String e) => 'Gateway error: $e';
}
