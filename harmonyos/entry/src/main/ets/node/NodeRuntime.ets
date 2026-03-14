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
  AppUpdateHandler
} from './InvokeDispatcher';
import { CanvasController } from './CanvasController';
import { DummyCameraHandler, DummyScreenHandler } from './DummyHandlers';
import { DebugHandlerImpl } from './handlers/DebugHandlerImpl';
import { SmsHandlerImpl } from './handlers/SmsHandlerImpl';
import { LocationHandlerImpl } from './handlers/LocationHandlerImpl';
import { CameraHandlerImpl } from './handlers/CameraHandlerImpl';
import { ScreenHandlerImpl } from './handlers/ScreenHandlerImpl';
import { A2UIHandlerImpl } from './handlers/A2UIHandlerImpl';
import { ChatController } from './chat/ChatController';
import { VoiceWakeManager } from '../voice/VoiceWakeManager';
import { TalkModeManager } from '../voice/TalkModeManager';
import { WakeWords } from '../common/WakeWords';

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
  public onChatUpdate: (() => void) | undefined = undefined;
  
  // Real Handlers
  public canvas = new CanvasController();
  private cameraHandler: CameraHandler;
  private locationHandler: LocationHandlerImpl;
  private screenHandler: ScreenHandler;
  private smsHandler: SmsHandlerImpl;
  private a2uiHandler: A2UIHandlerImpl;
  private debugHandler: DebugHandlerImpl;
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
    this.screenHandler = new ScreenHandlerImpl(context);

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

    this.invokeDispatcher = new InvokeDispatcher(
      this.canvas,
      this.cameraHandler,
      this.locationHandler,
      this.screenHandler,
      this.smsHandler,
      this.a2uiHandler,
      this.debugHandler,
      this.dummyAppUpdate,
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
        this.chatController.applyMainSessionKey(mainKey || "main");
      },
      (message) => {
        this.operatorConnected = false;
        this.operatorStatusText = message;
        this.serverName = undefined;
        this.remoteAddress = undefined;
        this.mainSessionKey = "main";
        this.updateStatus();
        this.chatController.onDisconnected(message);
      },
      (event, payload) => {
        this.gatewayEventHandler.handleEvent(event, payload);
        this.chatController.handleGatewayEvent(event, payload);
      }
    );

    this.chatController = new ChatController(this.operatorSession, true, () => {
      if (this.onChatUpdate) this.onChatUpdate();
    });

    this.voiceWakeManager = new VoiceWakeManager(async (command) => {
      hilog.info(NodeRuntime.DOMAIN, 'NodeRuntime', 'Voice wake command: %{public}s', command);
      await this.chatController.sendMessage(command, 'low', []);
    });

    this.talkModeManager = new TalkModeManager(
      this.operatorSession,
      () => this.isConnected
    );

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

