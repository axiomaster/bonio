export interface IlinkInboundMessage {
    messageId: string;
    seq: string;
    fromUserId: string;
    toUserId: string;
    messageType: number;
    contextToken: string;
    content: string;
}
type Log = (message: string) => void;
type OnMessage = (msg: IlinkInboundMessage) => void;
export declare class IlinkHttpClient {
    private token;
    private baseUrl;
    private stateDir;
    private readonly onMessage;
    private readonly log;
    private running;
    private inflight;
    private cursor;
    private contextTokens;
    private pollTimer;
    private sessionExpiredPauseUntil;
    /**
     * Random per-instance UIN. hiclaw's ilink_http_client.cpp sends a random
     * 4-byte base64 value here; without it (and AuthorizationType) the server
     * rejects even freshly bound tokens with errcode=-14.
     */
    private readonly xWechatUin;
    constructor(token: string, baseUrl: string, stateDir: string, onMessage: OnMessage, log?: Log);
    private cursorFile;
    private loadCursor;
    private saveCursor;
    private contextTokensFile;
    private loadContextTokens;
    private saveContextTokens;
    private post;
    start(): void;
    stop(): void;
    private poll;
    private extractText;
    private generateClientId;
    sendMessage(toUserId: string, content: string): Promise<boolean>;
    private delay;
}
export {};
