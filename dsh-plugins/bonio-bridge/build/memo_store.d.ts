export interface BonioMemo {
    id: string;
    title: string;
    content: string;
    source: string;
    createdAt: number;
    tags?: string[];
    sourceApp?: string;
    pageTitle?: string;
    pageLink?: string;
    /** Base64-encoded JPEG cover, populated when the memo is read. */
    coverImage?: string;
    /** Base64-encoded full-resolution screenshot, loaded for memory detail. */
    originalImage?: string;
    originalImageMimeType?: string;
}
export interface SaveMemoInput {
    title: string;
    content: string;
    source?: string;
    tags?: string[];
    sourceApp?: string;
    pageTitle?: string;
    pageLink?: string;
    /** Base64-encoded JPEG cover from an explicit MSDP capture. */
    coverImage?: string;
    /** Full-resolution screenshot used for visual extraction and detail view. */
    originalImage?: string;
    originalImageMimeType?: string;
}
export declare function saveMemo(input: SaveMemoInput): Promise<BonioMemo>;
export declare function listMemos(limit?: number, query?: string): Promise<BonioMemo[]>;
export declare function getMemo(id: string): Promise<BonioMemo | null>;
export declare function deleteMemo(id: string): Promise<boolean>;
