interface RunChatDriver {
    runChat(params: {
        text: string;
        sessionKey?: string;
        runId?: string;
    }): Promise<{
        runId: string;
        error?: string;
    }>;
}
export declare class WechatChannel {
    private readonly driver;
    private ilink;
    private activeToken;
    private activeBaseUrl;
    private allowFrom;
    /** runId -> WeChat sender awaiting a reply. */
    private pendingReplies;
    private dedupCache;
    constructor(driver: RunChatDriver);
    /** (Re)start or stop the poller according to the persisted hiclaw.json binding. */
    syncFromConfig(): Promise<void>;
    private handleInbound;
    /**
     * Called from the bridge sink for every chat final. Wechat runs route the
     * final assistant text back to the waiting WeChat sender.
     */
    handleChatFinal(runId: string, payload: Record<string, unknown>): void;
    stop(): void;
}
export {};
