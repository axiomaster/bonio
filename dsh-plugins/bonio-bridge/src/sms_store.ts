import path from 'node:path';

export interface SmsRecord {
  msgId?: number;
  senderNumber: string;
  startTime: number;
  content: string;
}

export interface TelecomBillInfo {
  carrier: string;
  sender: string;
  time: number;
  totalBill?: number;
  amountDue?: number;
  balance?: number;
  isPastDue: boolean;
  billingCycle?: string;
  phoneNumber?: string;
  rawContent: string;
  summary: string;
}

const SMS_DB_PATH = '/data/app/el2/100/database/com.ohos.telephonydataability/rdb/sms_mms.db';

let sqliteModule: any = null;

async function getSqlite(): Promise<any> {
  if (sqliteModule) return sqliteModule;
  try {
    // node:sqlite is available in Node 22+
    sqliteModule = await import('node:sqlite');
    return sqliteModule;
  } catch (err) {
    console.warn('[sms_store] node:sqlite import failed:', err);
    return null;
  }
}

function getReadonlyDb(): any | null {
  try {
    const mod = sqliteModule;
    if (!mod || !mod.DatabaseSync) return null;
    return new mod.DatabaseSync(SMS_DB_PATH, { open: true, readOnly: true });
  } catch (e) {
    console.warn('[sms_store] failed to open sms database:', e);
    return null;
  }
}

export async function searchSms(options: { query?: string; sender?: string; limit?: number }): Promise<SmsRecord[]> {
  await getSqlite();
  const db = getReadonlyDb();
  if (!db) return [];

  const limit = Math.max(1, Math.min(options.limit ?? 10, 50));
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (options.sender && options.sender.trim()) {
    conditions.push('sender_number = ?');
    params.push(options.sender.trim());
  }

  if (options.query && options.query.trim()) {
    conditions.push('msg_content LIKE ?');
    params.push(`%${options.query.trim()}%`);
  }

  const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const sql = `SELECT msg_id, sender_number, start_time, msg_content FROM sms_mms_info ${whereClause} ORDER BY start_time DESC LIMIT ${limit}`;

  try {
    const stmt = db.prepare(sql);
    const rows = stmt.all(...params) as Array<Record<string, any>>;
    db.close?.();
    return rows.map((r) => ({
      msgId: Number(r.msg_id) || undefined,
      senderNumber: String(r.sender_number || ''),
      startTime: Number(r.start_time) || 0,
      content: String(r.msg_content || ''),
    }));
  } catch (e) {
    console.warn('[sms_store] searchSms query failed:', e);
    try { db.close?.(); } catch (_) {}
    return [];
  }
}

export async function getLatestTelecomBill(): Promise<TelecomBillInfo | null> {
  await getSqlite();
  const db = getReadonlyDb();
  if (!db) return null;

  const sql = `
    SELECT sender_number, start_time, msg_content 
    FROM sms_mms_info 
    WHERE sender_number IN ('10000', '10086', '10010') 
       OR msg_content LIKE '%账单%' 
       OR msg_content LIKE '%欠费%' 
       OR msg_content LIKE '%话费%' 
       OR msg_content LIKE '%应付%'
       OR msg_content LIKE '%余额%'
    ORDER BY start_time DESC 
    LIMIT 10
  `;

  try {
    const stmt = db.prepare(sql);
    const rows = stmt.all() as Array<Record<string, any>>;
    db.close?.();

    for (const r of rows) {
      const sender = String(r.sender_number || '').trim();
      const content = String(r.msg_content || '').trim();
      const time = Number(r.start_time) || 0;

      let carrier = '未知运营商';
      if (sender === '10000' || content.includes('中国电信') || content.includes('电信')) {
        carrier = '中国电信';
      } else if (sender === '10086' || content.includes('中国移动') || content.includes('移动')) {
        carrier = '中国移动';
      } else if (sender === '10010' || content.includes('中国联通') || content.includes('联通')) {
        carrier = '中国联通';
      }

      // Check if it's a bill/balance/overdue message
      const isBill = /(账单|欠费|话费|应付|余额|停机)/.test(content);
      if (!isBill) continue;

      let amountDue: number | undefined;
      const mDue = content.match(/实际应付(?:\s*)([\d\.]+)元/);
      if (mDue) amountDue = parseFloat(mDue[1]);

      let totalBill: number | undefined;
      const mTotal = content.match(/账单合计(?:\s*)([\d\.]+)元/);
      if (mTotal) totalBill = parseFloat(mTotal[1]);

      let balance: number | undefined;
      const mBal = content.match(/(?:当前)?余额(?:\s*)([\d\.-]+)元/);
      if (mBal) balance = parseFloat(mBal[1]);

      let billingCycle: string | undefined;
      const mCycle = content.match(/账单周期为?([^\s，,。\r\n]+)/);
      if (mCycle) billingCycle = mCycle[1];

      let phoneNumber: string | undefined;
      const mPhone = content.match(/号码为?([0-9*xX]{7,13})/);
      if (mPhone) phoneNumber = mPhone[1];

      const isPastDue = (typeof amountDue === 'number' && amountDue > 0) ||
        (typeof balance === 'number' && balance < 0) ||
        content.includes('欠费') ||
        content.includes('停机');

      const parts: string[] = [carrier];
      if (billingCycle) parts.push(`周期${billingCycle}`);
      if (phoneNumber) parts.push(`号码${phoneNumber}`);
      if (typeof totalBill === 'number') parts.push(`账单合计${totalBill}元`);
      if (typeof amountDue === 'number') parts.push(`实际应付${amountDue}元`);
      if (typeof balance === 'number') parts.push(`当前余额${balance}元`);
      if (isPastDue) parts.push('当前状态：待缴费/欠费');

      return {
        carrier,
        sender,
        time,
        totalBill,
        amountDue,
        balance,
        isPastDue,
        billingCycle,
        phoneNumber,
        rawContent: content,
        summary: parts.join('，'),
      };
    }
    return null;
  } catch (e) {
    console.warn('[sms_store] getLatestTelecomBill failed:', e);
    try { db.close?.(); } catch (_) {}
    return null;
  }
}
