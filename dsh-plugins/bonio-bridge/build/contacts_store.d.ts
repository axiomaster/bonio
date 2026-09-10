export interface ContactRecord {
    id: number;
    name: string;
    phones: string[];
    company?: string;
    position?: string;
    nickname?: string;
    emails?: string[];
}
export declare function cleanContactQuery(query: string): string;
export declare function searchContacts(query: string, limit?: number): Promise<ContactRecord[]>;
