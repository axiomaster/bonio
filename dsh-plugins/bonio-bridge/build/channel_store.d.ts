export interface ChannelConfig {
    enabled: boolean;
    mode: string;
    wecomBotId: string;
}
export interface WechatBinding {
    enabled: boolean;
    mode: string;
    token: string;
    baseUrl: string;
    allowFrom: string[];
}
/** Resolve the on-device bonio home (~/.bonio lives under it). */
export declare function bonioHome(): string;
export declare function getChannelConfig(): Promise<ChannelConfig>;
export declare function getWechatBinding(): Promise<WechatBinding>;
export declare function setWechatBinding(binding: {
    token: string;
    baseUrl?: string;
    allowFrom?: string[];
}): Promise<{
    saved: boolean;
}>;
export declare function disableWechat(): Promise<{
    saved: boolean;
}>;
export declare function fetchWechatQrCode(): Promise<{
    qrcode_key: string;
    qrcode_img: string;
}>;
export declare function pollWechatQrStatus(qrcodeKey: string, verifyCode?: string): Promise<{
    status: string;
    bot_token?: string;
    ilink_user_id?: string;
    baseurl?: string;
}>;
