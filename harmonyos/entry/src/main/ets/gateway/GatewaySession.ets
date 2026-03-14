import { webSocket } from '@kit.NetworkKit';
import { RawWebSocket } from './RawWebSocket';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GatewayEndpoint, GatewayConnectOptions, GatewayClientInfo, GatewayTlsParams } from '../models/CommonModels';
import { DeviceIdentityStore, DeviceIdentity } from '../common/DeviceIdentityStore';
import { SecurePrefs } from '../common/SecurePrefs';

export interface InvokeRequest {
  id: string;
  nodeId: string;
  command: string;
  paramsJson?: string;
  timeoutMs?: number;
}

export interface InvokeError {
  code: string;
  message: string;
}

export interface InvokeResult {
  ok: boolean;
  payloadJson?: string;
  error?: InvokeError;
}

class RpcResponse {
  id: string = '';
  ok: boolean = false;
  payload?: Object;
  payloadJSON?: string;
  error?: InvokeError;
}

interface ConnectClientInfo {
  id: string;
  displayName?: string;
  version: string;
  platform: string;
  mode: string;
  instanceId?: string;
  deviceFamily?: string;
  modelIdentifier?: string;
}

interface ConnectAuth {
  token?: string;
  password?: string;
}

interface ConnectDevice {
  id: string;
  publicKey: string;
  signature: string;
  signedAt: number;
  nonce: string;
}

interface ConnectParams {
  minProtocol: number;
  maxProtocol: number;
  client?: ConnectClientInfo;
  role: string;
  scopes: string[];
  caps: string[];
  commands: string[];
  permissions: Record<string, boolean>;
  auth?: ConnectAuth;
  device?: ConnectDevice;
  locale: string;
}

export class InvokePayload {
  id: string = '';
  nodeId: string = '';
  command: string = '';
  paramsJSON?: string;
  params?: Object;
  timeoutMs?: number;
}

class InvokeResultParams {
  id: string = '';
  nodeId: string = '';
  ok: boolean = false;
  payload?: Object;
  error?: InvokeError;
}

class RpcFrame {
  type: string = 'req';
  id: string = '';
  method: string = '';
  params: Record<string, Object> = {};
}

class NodeEventParams {
  event: string = '';
  payload: Object | undefined = undefined;
}
class PendingRpcItem {
  resolve?: (res: RpcResponse) => void;
  reject?: (err: Error) => void;
  timeout: number = -1;
}

export class GatewaySession {
  private static readonly DOMAIN = 0x3D00;
  private static readonly TAG = 'GatewaySession';

  private ws: RawWebSocket | undefined = undefined;
  private identityStore: DeviceIdentityStore;
  private prefs: SecurePrefs;
  
  private onConnected: (serverName: string | undefined, remoteAddress: string | undefined, mainSessionKey: string | undefined) => void;
  private onDisconnected: (message: string) => void;
  private onEvent: (event: string, payloadJson: string | undefined) => void;
  private onInvoke?: (req: InvokeRequest) => Promise<InvokeResult>;

  private desiredEndpoint: GatewayEndpoint | undefined = undefined;
  private desiredOptions: GatewayConnectOptions | undefined = undefined;
  private authToken: string | undefined = undefined;
  private password: string | undefined = undefined;
  
  private isConnecting: boolean = false;
  private reconnectTimer: number = -1;


  private pendingRpc = new Map<string, PendingRpcItem>();

  private canvasHostUrl: string | undefined = undefined;
  private mainSessionKey: string | undefined = undefined;

  public getCanvasHostUrl(): string | undefined {
    return this.canvasHostUrl;
  }

  private role: string = '';

  constructor(
    identityStore: DeviceIdentityStore,
    prefs: SecurePrefs,
    onConnected: (serverName: string | undefined, remoteAddress: string | undefined, mainSessionKey: string | undefined) => void,
    onDisconnected: (message: string) => void,
    onEvent: (event: string, payloadJson: string | undefined) => void,
    onInvoke?: (req: InvokeRequest) => Promise<InvokeResult>
  ) {
    this.identityStore = identityStore;
    this.prefs = prefs;
    this.onConnected = onConnected;
    this.onDisconnected = onDisconnected;
    this.onEvent = onEvent;
    this.onInvoke = onInvoke;
  }

  public connect(endpoint: GatewayEndpoint, token: string | undefined, password: string | undefined, options: GatewayConnectOptions): void {
    this.role = options.role;
    this.desiredEndpoint = endpoint;
    this.desiredOptions = options;
    this.authToken = token;
    this.password = password;
    
    this.startConnectLoop();
  }

  public disconnect(): void {
    this.desiredEndpoint = undefined;
    this.closeWebSocket();
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    this.onDisconnected('Offline');
  }

  private closeWebSocket(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = undefined;
    }
    this.isConnecting = false;
    this.failPendingRpc('Connection closed');
  }

  private async startConnectLoop(): Promise<void> {
    if (this.isConnecting || !this.desiredEndpoint) return;
    this.isConnecting = true;
    
    try {
      await this.doConnect();
    } catch (e) {
      console.error('GatewaySession', `Connect failed: ${e instanceof Error ? e.message : String(e)}`);
      this.scheduleReconnect();
    }
  }

  private async doConnect(): Promise<void> {
    const endpoint = this.desiredEndpoint!;
    const scheme = endpoint.tlsEnabled ? 'wss' : 'ws';
    let url = `${scheme}://${endpoint.host}:${endpoint.port}`;

    hilog.info(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] Connecting to %{public}s", this.role, url);
    console.info('GatewaySession', `[${this.role}] Connecting to ${url}`);
    
    this.closeWebSocket();
    this.ws = new RawWebSocket();

    // Set TLS parameters for fingerprint pinning
    if (endpoint.tlsEnabled) {
      const tlsParams: GatewayTlsParams = {
        required: true,
        expectedFingerprint: endpoint.tlsFingerprintSha256,
        allowTOFU: !endpoint.tlsFingerprintSha256, // Allow TOFU if no fingerprint is set
        stableId: endpoint.stableId
      };
      this.ws.setTlsParams(tlsParams, (fingerprint: string) => {
        // TOFU: Store the accepted fingerprint
        // This could be persisted to SecurePrefs for future connections
        hilog.info(GatewaySession.DOMAIN, GatewaySession.TAG,
          "[%{public}s] TLS fingerprint accepted via TOFU: %{public}s...",
          this.role, fingerprint.substring(0, 16));
      });
    }

    this.ws.on('open', (err: BusinessError | undefined, value: Object | undefined) => {
      console.info('GatewaySession', `[${this.role}] RAW WsOpen: err=${JSON.stringify(err)} value=${JSON.stringify(value)}`);
      this.onWsOpen();
    });
    this.ws.on('message', (err: BusinessError | undefined, value: string | ArrayBuffer | undefined) => {
      console.info('GatewaySession', `[${this.role}] RAW WsMessage: type1=${typeof err} type2=${typeof value}`);
      if (typeof value === 'string' || value instanceof ArrayBuffer) {
        this.onWsMessage(value);
      } else if (typeof err === 'string' || err instanceof ArrayBuffer) {
        this.onWsMessage(err);
      } else {
        console.error('GatewaySession', `[${this.role}] RAW WsMessage: Unknown payload format! err=${JSON.stringify(err)} value=${JSON.stringify(value)}`);
      }
    });
    this.ws.on('close', (err: BusinessError | undefined, value: webSocket.CloseResult | undefined) => {
      console.info('GatewaySession', `[${this.role}] RAW WsClose: err=${JSON.stringify(err)} value=${JSON.stringify(value)}`);
      this.onWsClose();
    });
    this.ws.on('error', (err: BusinessError) => {
      console.error('GatewaySession', `[${this.role}] RAW WsError: err=${JSON.stringify(err)}`);
      this.onWsError();
    });

    try {
      const httpScheme = endpoint.tlsEnabled ? 'https' : 'http';
      const origin = `${httpScheme}://${endpoint.host}:${endpoint.port}`;
      const nativeUA = this.desiredOptions?.userAgent || `OpenClawNode/1.0.0-dev (Android)`;
      
      hilog.info(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] Connecting with Origin=%{public}s, UA=%{public}s", this.role, origin, nativeUA);
      
      let options: webSocket.WebSocketRequestOptions = {
        header: {
          'Host': endpoint.host,
          'Origin': origin,
          'User-Agent': nativeUA,
          'X-Requested-With': 'ai.openclaw.harmonyos'
        }
      };
      await this.ws.connect(url, options);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] WebSocket connect failed: %{public}s (code: %{public}d)", this.role, error.message, error.code);
      console.error('GatewaySession', `[${this.role}] WebSocket connect failed: ${error.message} (code: ${error.code}).`);
    }
  }

  private onWsOpen(): void {
    console.info('GatewaySession', `[${this.role}] WebSocket opened, initiating handshake wait...`);
  }

  private onWsMessage(data: string | ArrayBuffer): void {
    if (typeof data === 'string') {
      console.info('GatewaySession', `[${this.role}] parsed WsMessage: ${data.substring(0, 100)}${data.length > 100 ? '...' : ''}`);
      this.handleMessage(data);
    } else if (data instanceof ArrayBuffer) {
       console.info('GatewaySession', `[${this.role}] parsed WsMessage: Received ArrayBuffer (${data.byteLength} bytes)`);
    }
  }

  private onWsClose(): void {
    this.closeWebSocket();
    this.onDisconnected('Connection closed');
    this.scheduleReconnect();
  }

  private onWsError(): void {
    this.closeWebSocket();
    this.onDisconnected('Connection error');
    this.scheduleReconnect();
  }

  private scheduleReconnect(): void {
    if (!this.desiredEndpoint) return;
    if (this.reconnectTimer !== -1) clearTimeout(this.reconnectTimer);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      this.startConnectLoop();
    }, 5000);
  }

  private async handleMessage(text: string): Promise<void> {
    console.info('GatewaySession', `Received message: ${text.substring(0, 100)}${text.length > 100 ? '...' : ''}`);
    try {
      const frame = JSON.parse(text) as Record<string, Object>;
      const type = frame.type as string;
      
      if (type === 'res') {
        const id = frame.id as string;
        const pending = this.pendingRpc.get(id);
        if (pending) {
          clearTimeout(pending.timeout);
          this.pendingRpc.delete(id);
          const res = new RpcResponse();
          res.id = id;
          res.ok = frame.ok as boolean;
          res.payload = frame.payload;
          res.payloadJSON = frame.payloadJSON as string;
          res.error = frame.error as InvokeError;
          const resolveCb = pending.resolve;
          const rejectCb = pending.reject;
          if (res.ok) {
            if (resolveCb) resolveCb(res);
          } else {
            if (rejectCb) rejectCb(new Error(res.error?.message || "RPC failed"));
          }
        }
      } else if (type === 'event') {
        const event = frame.event as string;
        const payload = frame.payload as Record<string, Object> || (frame.payloadJSON ? JSON.parse(frame.payloadJSON as string) as Record<string, Object> : undefined);
        
        if (event === 'connect.challenge') {
          console.info('GatewaySession', `Received connect.challenge, nonce: ${payload.nonce}`);
          await this.sendConnect(payload.nonce as string);
        } else if (event === 'node.invoke.request' && this.onInvoke) {
          const invokePayload = new InvokePayload();
          invokePayload.id = payload.id as string;
          invokePayload.nodeId = payload.nodeId as string;
          invokePayload.command = payload.command as string;
          invokePayload.paramsJSON = payload.paramsJSON as string;
          invokePayload.params = payload.params;
          invokePayload.timeoutMs = payload.timeoutMs as number;
          this.handleInvoke(invokePayload);
        } else {
          this.onEvent(event, JSON.stringify(payload));
        }
      }
    } catch (e) {
      console.error('GatewaySession', `Handle message failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  private async sendConnect(nonce: string): Promise<void> {
    console.info('GatewaySession', `Sending connect RPC with nonce: ${nonce}`);
    const identity = await this.identityStore.loadOrCreate();
    const options = this.desiredOptions!;
    
    const signedAtMs = Date.now();
    const payloadInfo = this.buildDeviceAuthPayload(identity.deviceId, options.client.id, options.client.mode, options.role, options.scopes, signedAtMs, this.authToken, nonce);
    const signature = await this.identityStore.signPayload(payloadInfo, identity);
    const publicKey = this.identityStore.publicKeyBase64Url(identity);

    let clientObj: ConnectClientInfo | undefined = undefined;
    if (options.client) {
      clientObj = {
        id: options.client.id,
        displayName: options.client.displayName,
        version: options.client.version,
        platform: options.client.platform,
        mode: options.client.mode,
        instanceId: options.client.instanceId,
        deviceFamily: options.client.deviceFamily,
        modelIdentifier: options.client.modelIdentifier
      };
    }

    let authObj: ConnectAuth | undefined = undefined;
    if (this.authToken) {
      authObj = { token: this.authToken };
    } else if (this.password) {
      authObj = { password: this.password };
    }

    let devObj: ConnectDevice | undefined = undefined;
    if (signature && publicKey) {
      devObj = {
        id: identity.deviceId,
        publicKey: publicKey,
        signature: signature,
        signedAt: signedAtMs,
        nonce: nonce
      };
    }

    const connectParams: ConnectParams = {
      role: options.role,
      client: clientObj,
      minProtocol: 1,
      maxProtocol: 3,
      scopes: options.scopes,
      caps: options.caps,
      commands: options.commands,
      permissions: options.permissions || {},
      auth: authObj,
      device: devObj,
      locale: 'zh-CN'
    };

    hilog.info(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] Sending connect RPC, role: %{public}s", this.role, options.role);
    // Review 3: Redact sensitive connectParams in debug logs
    const redactedParams = JSON.parse(JSON.stringify(connectParams)) as Record<string, Object>;
    if (redactedParams.auth) (redactedParams.auth as Record<string, string>).token = '***';
    if (redactedParams.auth) (redactedParams.auth as Record<string, string>).password = '***';
    if (redactedParams.device) (redactedParams.device as Record<string, string>).nonce = '***';
    if (redactedParams.device) (redactedParams.device as Record<string, string>).signature = '***';
    console.info('GatewaySession', `[${this.role}] ConnectParams (redacted): ${JSON.stringify(redactedParams)}`);

    try {
      const res = await this.request('connect', connectParams);
      if (res.ok) {
        hilog.info(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] Connect RPC successful", this.role);
        const payloadObj = res.payload as Record<string, Object> || (res.payloadJSON ? JSON.parse(res.payloadJSON as string) as Record<string, Object> : {});
        const serverObj = payloadObj.server as Record<string, string>;
        const snapshotObj = payloadObj.snapshot as Record<string, Object>;
        const sessionDefs = snapshotObj?.sessionDefaults as Record<string, string>;
        
        const serverName = serverObj?.host || undefined;
        this.canvasHostUrl = (payloadObj.canvasHostUrl as string) || undefined;
        this.mainSessionKey = sessionDefs?.mainSessionKey || 'main';
        
        this.onConnected(serverName, this.desiredEndpoint?.host || undefined, this.mainSessionKey);
        console.info('GatewaySession', `Successfully connected to ${serverName}`);
      } else {
        hilog.error(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] Connect RPC failed: %{public}s (code: %{public}d)", this.role, res.error?.message || "", res.error?.code || 0);
        console.error('GatewaySession', `Connect RPC failed: ${res.error?.message} (code: ${res.error?.code})`);
        this.closeWebSocket();
      }
    } catch (e) {
      hilog.error(GatewaySession.DOMAIN, GatewaySession.TAG, "[%{public}s] Connect request error: %{public}s", this.role, (e as Error).message);
      console.error('GatewaySession', `Connect request failed or timed out: ${e instanceof Error ? e.message : String(e)}`);
      this.closeWebSocket();
    }
  }

  private buildDeviceAuthPayload(deviceId: string, clientId: string, clientMode: string, role: string, scopes: string[], signedAtMs: number, token: string | undefined, nonce: string): string {
    const scopeString = scopes.join(',');
    const authToken = token || '';
    return ['v2', deviceId, clientId, clientMode, role, scopeString, signedAtMs.toString(), authToken, nonce].join('|');
  }

  private async handleInvoke(payload: InvokePayload): Promise<void> {
    let res: InvokeResult;
    const req: InvokeRequest = {
      id: payload.id,
      nodeId: payload.nodeId,
      command: payload.command,
      paramsJson: payload.paramsJSON || (payload.params ? JSON.stringify(payload.params) : undefined),
      timeoutMs: payload.timeoutMs
    };

    try {
      const invokeCb = this.onInvoke;
      if (invokeCb) {
        res = await invokeCb(req);
      } else {
        res = { ok: false, error: { code: 'NO_HANDLER', message: "No handler configured" } };
      }
      await this.sendInvokeResult(req.id, req.nodeId, res);
    } catch (err) {
      const e = err as Error;
      await this.sendInvokeResult(req.id, req.nodeId, { ok: false, error: { code: 'INTERNAL_ERROR', message: e.message } });
    }
  }

  private async sendInvokeResult(id: string, nodeId: string, result: InvokeResult): Promise<void> {
    const params = new InvokeResultParams();
    params.id = id;
    params.nodeId = nodeId;
    params.ok = result.ok;
    params.payload = result.payloadJson ? JSON.parse(result.payloadJson) as Object : undefined;
    params.error = result.error;
    
    try {
      await this.request('node.invoke.result', params);
    } catch (e) {
      console.error('GatewaySession', `Send invoke result failed: ${(e as Error).message}`);
    }
  }

  public async request(method: string, params: Object, timeoutMs: number = 15000): Promise<RpcResponse> {
    console.info('GatewaySession', `RPC Request: ${method}`);
    if (!this.ws) throw new Error('Not connected');
    
    const id = this.generateId();
    
    const frame = new RpcFrame();
    frame.id = id;
    frame.method = method;
    frame.params = params as Record<string, Object>;

    return new Promise<RpcResponse>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingRpc.delete(id);
        reject(new Error(`Request ${method} timed out`));
      }, timeoutMs);

      const rpcItem = new PendingRpcItem();
      rpcItem.resolve = resolve;
      rpcItem.reject = reject;
      rpcItem.timeout = timeout;
      this.pendingRpc.set(id, rpcItem);
      this.ws?.send(JSON.stringify(frame));
    });
  }

  public async sendNodeEvent(event: string, payloadJson: string | undefined): Promise<void> {
    const params = new NodeEventParams();
    params.event = event;
    params.payload = payloadJson ? JSON.parse(payloadJson) as Object : undefined;
    
    try {
      await this.request('node.event', params, 8000);
    } catch (e) {
      console.warn('GatewaySession', `node.event failed: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  private generateId(): string {
    return util.generateRandomUUID(true);
  }

  private failPendingRpc(message: string): void {
    const iter = this.pendingRpc.entries();
    let curr = iter.next();
    while (!curr.done) {
      const pending = curr.value[1];
      clearTimeout(pending.timeout);
      const rejectCb = pending.reject;
      if (rejectCb) {
        rejectCb(new Error(message));
      }
      curr = iter.next();
    }
    this.pendingRpc.clear();
  }
}
