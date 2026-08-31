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
}
export interface SaveMemoInput {
    title: string;
    content: string;
    source?: string;
    tags?: string[];
    sourceApp?: string;
    pageTitle?: string;
    pageLink?: string;
}
export declare function saveMemo(input: SaveMemoInput): Promise<BonioMemo>;
export declare function listMemos(limit?: number): Promise<BonioMemo[]>;
export declare function getMemo(id: string): Promise<BonioMemo | null>;
export declare function deleteMemo(id: string): Promise<boolean>;
