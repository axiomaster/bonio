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
    constructor(token: string, baseUrl: string, stateDir: string, onMessage: OnMessage, log?: Log);
    private cursorFile;
    private loadCursor;
    private saveCursor;
    private post;
    start(): void;
    stop(): void;
    private poll;
    private extractText;
    sendMessage(toUserId: string, content: string): Promise<boolean>;
}
export {};
