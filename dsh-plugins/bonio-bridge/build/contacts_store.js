const CONTACTS_DB_PATH = '/data/app/el2/100/database/com.ohos.contactsdataability/rdb/contacts.db';
let sqliteModule = null;
async function getSqlite() {
    if (sqliteModule)
        return sqliteModule;
    try {
        sqliteModule = await import('node:sqlite');
        return sqliteModule;
    }
    catch (err) {
        console.warn('[contacts_store] node:sqlite import failed:', err);
        return null;
    }
}
function getReadonlyDb() {
    try {
        const mod = sqliteModule;
        if (!mod || !mod.DatabaseSync)
            return null;
        return new mod.DatabaseSync(CONTACTS_DB_PATH, { open: true, readOnly: true });
    }
    catch (e) {
        console.warn('[contacts_store] failed to open contacts database:', e);
        return null;
    }
}
export function cleanContactQuery(query) {
    let s = (query || '').trim()
        .replace(/(是多少|是几|多少|是谁|是啥|是哪位|发一下|发下|告诉我|发给我|请发|有吗|有没|有么|吗)[？?！!。.]*$/g, '')
        .trim();
    s = s.replace(/(的)?(手机号码|电话号码|手机号|电话号|手机|电话|号码|联系方式|邮箱|微信)$/g, '').trim();
    s = s.replace(/^(请问|帮我查一下|帮我查下|帮我查|查一下|查下|查询|找一下|找下|找|看看|看下|问下|发一下|发下|发我|发给我|把)/g, '').trim();
    return s;
}
export async function searchContacts(query, limit = 5) {
    await getSqlite();
    const db = getReadonlyDb();
    if (!db)
        return [];
    const needle = cleanContactQuery(query);
    if (!needle)
        return [];
    const pattern = `%${needle}%`;
    const prefix = `${needle}%`;
    const maxLimit = Math.max(1, Math.min(limit, 20));
    const sql = `
    SELECT r.id, r.display_name, r.company, r.position, r.extra2 as nickname,
           GROUP_CONCAT(DISTINCT CASE WHEN d.type_id = 5 THEN d.detail_info END) as phones,
           GROUP_CONCAT(DISTINCT CASE WHEN d.type_id = 1 THEN d.detail_info END) as emails
    FROM raw_contact r
    LEFT JOIN contact_data d ON r.id = d.raw_contact_id
    WHERE r.is_deleted = 0 
      AND (r.display_name LIKE ? OR (r.extra2 IS NOT NULL AND r.extra2 LIKE ?) OR (d.type_id IN (5,6) AND d.detail_info LIKE ?))
    GROUP BY r.id
    ORDER BY CASE 
      WHEN r.display_name = ? OR r.extra2 = ? THEN 0 
      WHEN r.display_name LIKE ? OR r.extra2 LIKE ? THEN 1 
      ELSE 2 
    END
    LIMIT ?
  `;
    try {
        const stmt = db.prepare(sql);
        const rows = stmt.all(pattern, pattern, pattern, needle, needle, prefix, prefix, maxLimit);
        return rows.map((r) => {
            const phones = typeof r.phones === 'string' && r.phones ? r.phones.split(',').map((p) => p.trim()).filter(Boolean) : [];
            const emails = typeof r.emails === 'string' && r.emails ? r.emails.split(',').map((e) => e.trim()).filter(Boolean) : [];
            const item = {
                id: Number(r.id),
                name: String(r.display_name || '未命名'),
                phones,
            };
            if (r.company)
                item.company = String(r.company);
            if (r.position)
                item.position = String(r.position);
            if (r.nickname)
                item.nickname = String(r.nickname);
            if (emails.length > 0)
                item.emails = emails;
            return item;
        });
    }
    catch (e) {
        console.warn('[contacts_store] searchContacts failed:', e);
        return [];
    }
    finally {
        try {
            db.close?.();
        }
        catch (_) { }
    }
}
