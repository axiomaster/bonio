import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SecurePrefs } from '../common/SecurePrefs';
import { DeviceIdentityStore } from '../common/DeviceIdentityStore';
import { GatewayEndpoint, LocationMode, VoiceWakeMode } from '../models/CommonModels';
import { GatewaySession, InvokeRequest, InvokeResult } from '../gateway/GatewaySession';
import { ConnectionManager } from './ConnectionManager';
import { GatewayEventHandler } from './GatewayEventHandler';
import {
  InvokeDispatcher,
  CameraHandler,
  LocationHandler,
  ScreenHandler,
  SmsHandler,
  A2UIHandler,
  DebugHandler,
  AppUpdateHandler,
  ContactsHandler,
  CalendarHandler
} from './InvokeDispatcher';
import { CanvasController } from './CanvasController';
import { DummyCameraHandler, DummyScreenHandler } from './DummyHandlers';
import { DebugHandlerImpl } from './handlers/DebugHandlerImpl';
import { SmsHandlerImpl } from './handlers/SmsHandlerImpl';
import { LocationHandlerImpl } from './handlers/LocationHandlerImpl';
import { CameraHandlerImpl } from './handlers/CameraHandlerImpl';
import { ScreenHandlerImpl } from './handlers/ScreenHandlerImpl';
import { A2UIHandlerImpl } from './handlers/A2UIHandlerImpl';
import { ContactsHandlerImpl } from './handlers/ContactsHandlerImpl';
import { CalendarHandlerImpl } from './handlers/CalendarHandlerImpl';
import { ChatController } from './chat/ChatController';
import { VoiceWakeManager } from '../voice/VoiceWakeManager';
import { FeatureManager } from '../intent/FeatureManager';
import { Intent } from '../intent/IntentRouter';
import { HealthScheduler } from '../intent/HealthScheduler';
import { AvatarStep, paramsOf, stepOf, sequencePayload } from '../intent/AvatarCommand';
import { TalkModeManager } from '../voice/TalkModeManager';
import { WakeWords } from '../common/WakeWords';
import { MemoryService } from './MemoryService';
import { CompanionMemoryController } from './CompanionMemoryController';
import { MagicCueController, MagicCue } from './MagicCueController';

export class NodeRuntime {
  private static readonly DOMAIN = 0x3D00;
  public prefs: SecurePrefs;
  private identityStore: DeviceIdentityStore;
  private connectionManager: ConnectionManager;
  private gatewayEventHandler: GatewayEventHandler;
  private invokeDispatcher: InvokeDispatcher;

  public operatorSession: GatewaySession;
  public nodeSession: GatewaySession;

  private connectedEndpoint: GatewayEndpoint | undefined = undefined;
  private operatorConnected: boolean = false;
  private nodeConnected: boolean = false;
  private operatorStatusText: string = "Offline";
  private nodeStatusText: string = "Offline";

  // Reactive State Placeholders (To be connected to @State / @Provide in UI later)
  public isConnected: boolean = false;
  public statusText: string = "Offline";
  public serverName: string | undefined = undefined;
  public remoteAddress: string | undefined = undefined;
  public mainSessionKey: string = "main";
  public isForeground: boolean = true;
  
  public voiceWakeManager: VoiceWakeManager;
  public talkModeManager: TalkModeManager;
  
  public chatController: ChatController;
  public memoryService: MemoryService;
  public companionMemoryController: CompanionMemoryController;
  public magicCueController: MagicCueController;
  public onChatUpdate: (() => void) | undefined = undefined;

  // Phase 4: on-device feature coordination (intent / health / notifications).
  public featureManager: FeatureManager;
  public healthScheduler: HealthScheduler;
  /** Sink for avatar.command payloads produced by features (set by FloatWindowPage). */
  public avatarCommandSink: ((payloadJson: string) => void) | undefined = undefined;
  
  // Real Handlers
  public canvas = new CanvasController();
  private cameraHandler: CameraHandler;
  private locationHandler: LocationHandlerImpl;
  private screenHandler: ScreenHandler;
  private smsHandler: SmsHandlerImpl;
  private a2uiHandler: A2UIHandlerImpl;
  private debugHandler: DebugHandlerImpl;
  private contactsHandler: ContactsHandler;
  private calendarHandler: CalendarHandler;
  private dummyAppUpdate = new DummyAppUpdate();

  private lastAutoA2uiUrl: string | undefined = undefined;

  constructor(context: common.Context) {
    this.prefs = SecurePrefs.getInstance();
    this.prefs.init(context);
    this.identityStore = new DeviceIdentityStore(context);
    
    this.debugHandler = new DebugHandlerImpl(context, this.identityStore);
    this.smsHandler = new SmsHandlerImpl(context);
    this.locationHandler = new LocationHandlerImpl(context);
    this.cameraHandler = new CameraHandlerImpl(context);
    this.screenHandler = new ScreenHandlerImpl(
      context,
      () => this.prefs.getScreenAwarenessEnabled(),
      (source: string, payloadJson: string, coverImageBase64?: string, originalImageBase64?: string,
        originalImageMimeType?: string) => {
        // Explicit trigger captures are enqueued after the handler returns so
        // the completion listener and screenshot cover share one input.
        if (source === 'trigger') return;
        this.companionMemoryController.enqueue(source, payloadJson, coverImageBase64, originalImageBase64, originalImageMimeType);
      },
    );

    this.connectionManager = new ConnectionManager(
      this.prefs,
      () => this.prefs.getCameraEnabled(),
      () => this.prefs.getLocationMode(),
      () => this.prefs.getVoiceWakeMode(),
      () => false, // smsAvailable
      () => true,  // hasRecordAudioPermission
      () => this.prefs.getManualTls()
    );

    this.a2uiHandler = new A2UIHandlerImpl(
      this.canvas,
      () => this.nodeSession?.getCanvasHostUrl(),
      () => this.operatorSession?.getCanvasHostUrl()
    );

    this.contactsHandler = new ContactsHandlerImpl(context);
    this.calendarHandler = new CalendarHandlerImpl(context);

    this.invokeDispatcher = new InvokeDispatcher(
      this.canvas,
      this.cameraHandler,
      this.locationHandler,
      this.screenHandler,
      this.smsHandler,
      this.a2uiHandler,
      this.debugHandler,
      this.dummyAppUpdate,
      this.contactsHandler,
      this.calendarHandler,
      () => this.isForeground,
      () => this.prefs.getCameraEnabled(),
      () => this.prefs.getLocationMode() !== LocationMode.Off
    );

    this.operatorSession = new GatewaySession(
      this.identityStore,
      this.prefs,
      (name, remote, mainKey) => {
        this.operatorConnected = true;
        this.operatorStatusText = "Connected";
        this.serverName = name;
        this.remoteAddress = remote;
        this.applyMainSessionKey(mainKey);
        this.updateStatus();
        this.gatewayEventHandler.refreshWakeWordsFromGateway();
        this.chatController.onGatewayConnected(mainKey);
        this.companionMemoryController.onConnected();
      },
      (message) => {
        this.operatorConnected = false;
        this.operatorStatusText = message;
        this.serverName = undefined;
        this.remoteAddress = undefined;
        this.mainSessionKey = "main";
        this.updateStatus();
        this.chatController.onDisconnected(message);
        this.companionMemoryController.onDisconnected();
      },
      (event, payload) => {
        this.gatewayEventHandler.handleEvent(event, payload);
        this.chatController.handleGatewayEvent(event, payload);
        this.talkModeManager.handleGatewayEvent(event, payload);
        this.companionMemoryController.handleGatewayEvent(event, payload);
        this.magicCueController.handleGatewayEvent(event, payload);
      }
    );

    this.chatController = new ChatController(this.operatorSession, true, () => {
      if (this.onChatUpdate) this.onChatUpdate();
    });
    this.memoryService = new MemoryService(this.operatorSession);
    this.companionMemoryController = new CompanionMemoryController(
      this.operatorSession,
      this.memoryService,
      () => this.isConnected,
    );
    this.magicCueController = new MagicCueController(
      this.operatorSession,
      () => this.isConnected,
    );
    this.screenHandler.startScreenAwareness();

    this.voiceWakeManager = new VoiceWakeManager(async (command) => {
      hilog.info(NodeRuntime.DOMAIN, 'NodeRuntime', 'Voice wake command: %{public}s', command);
      await this.chatController.sendMessage(command, 'low', []);
    });

    this.talkModeManager = new TalkModeManager(
      this.operatorSession,
      () => this.isConnected
    );

    // Phase 4: on-device features (intent routing / health / notifications).
    this.featureManager = new FeatureManager();
    this.featureManager.onChatRequest = (text: string) => {
      void this.chatController.sendMessage(text, 'low', []);
    };
    this.featureManager.onNonChatIntent = (intent: Intent, text: string) => {
      hilog.info(NodeRuntime.DOMAIN, 'NodeRuntime', 'non-chat intent: %{public}s text=%{public}s', intent, text);
      if (intent === Intent.ScreenCapture || intent === Intent.Summarize) {
        this.handleCaptureIntent(intent, text);
      }
    };
    this.featureManager.onAvatarCommand = (payloadJson: string) => {
      if (this.avatarCommandSink) this.avatarCommandSink(payloadJson);
    };

    // Phase 4: health scheduler (screen-time nags) — driven by foreground state.
    this.healthScheduler = new HealthScheduler(
      this.featureManager,
      this.prefs,
      () => this.isForeground,
    );
    this.healthScheduler.start();

    this.voiceWakeManager.onStateChange = () => {
      this.updateStatus();
    };
    this.talkModeManager.onStateChange = () => {
      this.updateStatus();
    };

    this.nodeSession = new GatewaySession(
      this.identityStore,
      this.prefs,
      (name, remote, mainKey) => {
        this.nodeConnected = true;
        this.nodeStatusText = "Connected";
        this.updateStatus();
        this.maybeNavigateToA2uiOnConnect();
      },
      (msg) => {
        this.nodeConnected = false;
        this.nodeStatusText = msg;
        this.updateStatus();
        this.showLocalCanvasOnDisconnect();
      },
      (event, payload) => {
        this.gatewayEventHandler.handleEvent(event, payload);
        this.chatController.handleGatewayEvent(event, payload);
      },
      async (req: InvokeRequest) => {
        return await this.invokeDispatcher.handleInvoke(req.command, req.paramsJson);
      }
    );

    this.gatewayEventHandler = new GatewayEventHandler(
      this.prefs,
      this.operatorSession,
      () => this.isConnected
    );

    this.gatewayEventHandler.onWakeWordsChanged = (words) => {
      this.voiceWakeManager.setTriggerWords(words);
    };
  }

  public get voiceWakeStatusText(): string {
    return this.voiceWakeManager.statusText;
  }

  public get voiceWakeIsListening(): boolean {
    return this.voiceWakeManager.isListening;
  }

  public get talkModeStatusText(): string {
    return this.talkModeManager.statusText;
  }

  public get talkModeIsListening(): boolean {
    return this.talkModeManager.isListening;
  }

  public get talkModeIsSpeaking(): boolean {
    return this.talkModeManager.isSpeaking;
  }

  private applyMainSessionKey(candidate: string | undefined) {
    const trimmed = candidate?.trim();
    if (!trimmed) return;
    if (this.mainSessionKey === trimmed) return;
    this.mainSessionKey = trimmed;
    this.chatController?.applyMainSessionKey(trimmed);
    this.talkModeManager?.setMainSessionKey(trimmed);
  }

  private updateStatus() {
    this.isConnected = this.operatorConnected;
    if (this.operatorConnected && this.nodeConnected) {
      this.statusText = "Connected";
    } else if (this.operatorConnected && !this.nodeConnected) {
      this.statusText = "Connected (node offline)";
    } else if (!this.operatorConnected && this.nodeConnected) {
      this.statusText = "Connected (operator offline)";
    } else if (this.operatorStatusText !== "Offline") {
      this.statusText = this.operatorStatusText;
    } else {
      this.statusText = this.nodeStatusText;
    }
    if (this.onChatUpdate) this.onChatUpdate(); // Reuse chat update for general state changes for now
  }

  private maybeNavigateToA2uiOnConnect() {
    const a2uiUrl = this.a2uiHandler.resolveA2uiHostUrl();
    if (!a2uiUrl) return;
    const current = this.canvas.getCurrentUrl()?.trim() || "";
    if (current === "" || current === this.lastAutoA2uiUrl) {
      this.lastAutoA2uiUrl = a2uiUrl;
      this.canvas.navigate(a2uiUrl);
    }
  }

  private showLocalCanvasOnDisconnect() {
    this.lastAutoA2uiUrl = undefined;
    this.canvas.navigate("");
  }

  /** Called by avatar double tap: trigger a foreground SmartEdge recognition. */
  public async captureAvatarMemory(): Promise<string> {
    if (!this.isConnected) {
      throw new Error('DSH is not connected');
    }

    const capture = await this.screenHandler.handleSmartEdgeTrigger();
    if (!capture.ok || !capture.payloadJson) {
      throw new Error(`${capture.error?.code || 'SCREEN_AWARENESS_FAILED'}: ${capture.error?.message || 'SmartEdge trigger failed'}`);
    }

    const outcome = await this.companionMemoryController.enqueueAndWait(
      'trigger', capture.payloadJson, capture.coverImageBase64, capture.originalImageBase64, capture.originalImageMimeType);
    if (!outcome.saved) {
      throw new Error(`MEMORY_NOT_SAVED: ${outcome.reason || '当前页面未生成记忆'}`);
    }
    this.prefs.setAvatarLastMemoryAt(Date.now());
    hilog.info(NodeRuntime.DOMAIN, 'NodeRuntime', 'SmartEdge trigger saved to companion memory: %{public}s', outcome.title);
    return outcome.title;
  }

  /**
   * Magic Cue: analyze the current screen for an in-chat information request
   * and return the recommended capsules. Returns [] when nothing to show.
   */
  public async captureAvatarCues(): Promise<MagicCue[]> {
    if (!this.isConnected) {
      throw new Error('DSH is not connected');
    }
    const capture = await this.screenHandler.handleSmartEdgeTrigger();
    if (!capture.ok || !capture.payloadJson) {
      throw new Error(`${capture.error?.code || 'SCREEN_AWARENESS_FAILED'}: ${capture.error?.message || 'SmartEdge trigger failed'}`);
    }
    const bundleName = capture.bundleName ?? '';
    const title = capture.appName ?? '';
    return await this.magicCueController.run(capture.payloadJson, bundleName, title);
  }

  /**
   * Magic Cue: write a capsule's answer into the chat input and send it.
   * Uses cached input/send points (learned once by the bridge) so later
   * injections are a fixed tap sequence instead of re-discovering layout.
   */
  public async injectCue(text: string): Promise<void> {
    if (!this.isConnected) {
      throw new Error('DSH is not connected');
    }
    const params = new CueInjectParams();
    params.text = text;
    const input = this.parsePoint(this.prefs.getMagicCueInputPoint());
    if (input) {
      params.inputX = input[0];
      params.inputY = input[1];
    }
    const send = this.parsePoint(this.prefs.getMagicCueSendPoint());
    if (send) {
      params.sendX = send[0];
      params.sendY = send[1];
    }
    const response = await this.operatorSession.request('cue.inject', params, 15000);
    if (!response.ok) {
      throw new Error(response.error?.message || 'CUE_INJECT_FAILED');
    }
    this.cacheCuePoints(response.payload);
  }

  /** Magic Cue: launch an app (e.g. the system calendar). */
  public async openCueApp(bundle: string, ability?: string): Promise<void> {
    if (!this.isConnected) {
      throw new Error('DSH is not connected');
    }
    const params = new CueOpenParams();
    params.bundle = bundle;
    params.ability = ability;
    const response = await this.operatorSession.request('cue.open', params, 15000);
    if (!response.ok) {
      throw new Error(response.error?.message || 'CUE_OPEN_FAILED');
    }
  }

  private parsePoint(raw: string): number[] | undefined {
    const parts = raw.split(',');
    if (parts.length !== 2) return undefined;
    const x = Number(parts[0]);
    const y = Number(parts[1]);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return undefined;
    return [x, y];
  }

  private cacheCuePoints(payload: Object | undefined): void {
    if (!payload) return;
    const p = payload as Record<string, Object>;
    const input = p['inputPoint'] as Record<string, Object> | undefined;
    const send = p['sendPoint'] as Record<string, Object> | undefined;
    if (input && input['learned'] === true) {
      this.prefs.setMagicCueInputPoint(`${input['x']},${input['y']}`);
    }
    if (send && send['learned'] === true) {
      this.prefs.setMagicCueSendPoint(`${send['x']},${send['y']}`);
    }
  }

  /** Save a user-approved summary of the currently visible page as a structured DSH memory. */
  public async captureCurrentScreenMemory(): Promise<void> {
    if (!this.isConnected) {
      throw new Error('DSH is not connected');
    }

    const capture = await this.screenHandler.handleScreenContext(JSON.stringify({ maxTextLength: 12000 }));
    if (!capture.ok || !capture.payloadJson) {
      throw new Error(`${capture.error?.code || 'SCREEN_AWARENESS_FAILED'}: ${capture.error?.message || 'SmartEdge screen capture failed'}`);
    }

    this.companionMemoryController.enqueue('screen_context', capture.payloadJson);
    this.prefs.setAvatarLastMemoryAt(Date.now());
    hilog.info(NodeRuntime.DOMAIN, 'NodeRuntime', 'Screen context queued in companion memory session');
  }

  /**
   * Handle a ScreenCapture / Summarize voice intent.
   *
   * NOTE (privileged API): full-screen capture requires a system-signed app
   * with the `ohos.permission.CAPTURE_SCREEN` privileged permission and the
   * screen capture extension ability. In the current (unsigned) environment
   * we only log and show an avatar bubble; the privileged capture flow below
   * must be completed in the isolated build environment that holds those
   * permissions (see docs/design/arch/20260826-dsh-refactor-impl.md §11).
   */
  private async handleCaptureIntent(intent: Intent, text: string): Promise<void> {
    // Avatar feedback: let the user know the request was understood.
    if (this.featureManager.onAvatarCommand) {
      const steps: AvatarStep[] = [
        stepOf('setState', paramsOf(['state'], ['thinking']), 0),
        stepOf('setBubble', paramsOf(['text'], [intent === Intent.ScreenCapture ? '截图中…' : '总结中…']), 0),
      ];
      this.featureManager.onAvatarCommand(sequencePayload(steps));
    }

    // ── PRIVILEGED API: full-screen capture ────────────────────────────────
    // In the isolated environment (system-signed), capture the screen here,
    // e.g. via the screen capture extension ability (media.AVScreenCapture +
    // privileged CAPTURE_SCREEN) or the accessibility-based screenshot API.
    // Expected flow:
    //   1. startCapture -> bitmap/base64 image
    //   2. ScreenCapture: feed the image to the agent (chat.send with
    //      attachment) for "记一下/截图" actions
    //   3. Summarize: feed the image to the agent with a summarize prompt
    hilog.info(NodeRuntime.DOMAIN, 'NodeRuntime',
      'capture intent %{public}s requires privileged CAPTURE_SCREEN (TODO in isolated env), text=%{public}s', intent, text);
  }

  public connectManual() {
    const host = this.prefs.getManualHost().trim();
    const port = this.prefs.getManualPort();
    hilog.info(0x3D00, 'NodeRuntime', "connectManual: host=%{public}s, port=%{public}d", host, port);
    if (!host || port <= 0 || port > 65535 || !Number.isFinite(port)) {
      this.statusText = "Failed: invalid manual host/port";
      return;
    }
    
    // Use an unauthenticated manual endpoint logic for now during Stage 1 Porting
    const endpoint: GatewayEndpoint = {
      stableId: `manual|${host.toLowerCase()}|${port}`,
      name: `${host}:${port}`,
      host: host,
      port: port,
      tlsEnabled: this.prefs.getManualTls()
    };
    const token = this.prefs.getGatewayToken();
    hilog.info(0x3D00, 'NodeRuntime', "connectManual: initiating connect to endpoint, token=***");
    this.connect(endpoint, token);
  }

  public connect(endpoint: GatewayEndpoint, manualToken: string | undefined = undefined) {
    hilog.info(0x3D00, 'NodeRuntime', "connect: endpoint=%{public}s:%{public}d", endpoint.host, endpoint.port);
    this.connectedEndpoint = endpoint;
    this.operatorStatusText = "Connecting…";
    this.nodeStatusText = "Connecting…";
    this.updateStatus();

    const token = manualToken || this.prefs.getGatewayToken();
    const password = token; // Treat the manual token as the gateway password for the operator session

    const nodeOpts = this.connectionManager.buildNodeConnectOptions();
    const operatorOpts = this.connectionManager.buildOperatorConnectOptions();

    hilog.info(0x3D00, 'NodeRuntime', "connect: calling operatorSession.connect and nodeSession.connect");
    this.operatorSession.connect(endpoint, token, password, operatorOpts);
    setTimeout(() => {
      this.nodeSession.connect(endpoint, token, password, nodeOpts);
    }, 500);
  }

  public disconnect() {
    this.connectedEndpoint = undefined;
    this.operatorSession.disconnect();
    this.nodeSession.disconnect();
  }

  public setScreenAwarenessEnabled(enabled: boolean): void {
    this.prefs.setScreenAwarenessEnabled(enabled);
    this.screenHandler.setScreenAwarenessEnabled(enabled);
  }

  public setForeground(value: boolean) {
    this.isForeground = value;
  }
}

function makeDummyResult(): InvokeResult {
  const res: InvokeResult = { ok: false };
  return res;
}

class DummyAppUpdate implements AppUpdateHandler {
  async handleUpdate(paramsJson: string | undefined): Promise<InvokeResult> { return makeDummyResult(); }
}

class CueInjectParams {
  text: string = '';
  inputX?: number;
  inputY?: number;
  sendX?: number;
  sendY?: number;
}

class CueOpenParams {
  bundle: string = '';
  ability?: string;
}
