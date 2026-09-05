export interface InjectOptions {
    /** Text to type into the focused chat input. */
    text: string;
    /** Chat input center in physical px, captured before the keyboard opens. */
    inputX?: number;
    inputY?: number;
    /** Learned send-button center; when absent it is discovered once via dumpLayout. */
    sendX?: number;
    sendY?: number;
    /** false = focus+type only, never tap send. */
    send?: boolean;
}
export interface InjectResult {
    ok: boolean;
    stage: 'find-input' | 'click-input' | 'type' | 'find-send' | 'click-send';
    /** Input point actually used; NEW when discovered this call (caller caches). */
    inputPoint?: {
        x: number;
        y: number;
        learned?: boolean;
    };
    /** Send point actually used; NEW when discovered this call (caller caches). */
    sendPoint?: {
        x: number;
        y: number;
        learned?: boolean;
    };
    error?: string;
}
export declare function injectAndSend(options: InjectOptions): Promise<InjectResult>;
/** Launch an app by bundle (+ ability). Calendar: com.huawei.hmos.calendar/MainAbility. */
export declare function openApp(bundle: string, ability?: string): Promise<{
    ok: boolean;
    error?: string;
}>;
