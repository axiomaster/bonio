import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { ContactsHandler } from '../InvokeDispatcher';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import contact from '@ohos.contact';

/** One matched contact, flattened for the DSH agent. */
interface ContactHit {
  name: string;
  phones: string[];
  org?: string;
  emails?: string[];
}

interface ContactsPayload {
  contacts: ContactHit[];
  total: number;
}

/**
 * Address-book lookup for Magic Cue. Pulls the full contact list once and
 * matches locally (name / pinyin prefix / substring), which is fine at
 * personal-address-book scale.
 */
export class ContactsHandlerImpl implements ContactsHandler {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async handleContactsSearch(paramsJson: string | undefined): Promise<InvokeResult> {
    let query = '';
    let limit = 5;
    if (paramsJson) {
      try {
        const params = JSON.parse(paramsJson) as Record<string, Object>;
        if (typeof params['query'] === 'string') query = (params['query'] as string).trim();
        if (typeof params['limit'] === 'number') limit = params['limit'] as number;
      } catch (_) {
        return this.makeError('INVALID_REQUEST', 'contacts.search params must be valid JSON');
      }
    }
    if (!query) {
      return this.makeError('INVALID_REQUEST', 'contacts.search requires a query string');
    }

    try {
      const all = await contact.queryContacts(this.context);
      let needle = query.trim().toLowerCase();
      // Strip common query suffixes (e.g. "刘兴临的电话号码" -> "刘兴临")
      const stripped = needle.replace(/(的)?(手机号码|电话号码|手机号|电话号|手机|电话|号码|联系方式|邮箱|微信)$/g, '').trim();
      if (stripped.length > 0) {
        needle = stripped;
      }

      const hitMap = new Map<string, ContactHit>();
      for (const c of all) {
        const name = (c.name?.fullName ?? '').trim();
        const given = (c.name?.givenName ?? '').trim();
        const family = (c.name?.familyName ?? '').trim();
        const givenPhonetic = (c.name?.givenNamePhonetic ?? '').toLowerCase();
        const familyPhonetic = (c.name?.familyNamePhonetic ?? '').toLowerCase();
        const haystack = `${name} ${given} ${family}`.toLowerCase();
        const phonetic = `${givenPhonetic} ${familyPhonetic}`;
        const matches = haystack.includes(needle)
          || (name.length > 0 && name.toLowerCase().startsWith(needle))
          || (given.length > 0 && given.toLowerCase().startsWith(needle))
          || (needle.length >= 2 && phonetic.includes(needle));
        if (!matches) continue;

        const contactName = name || (family + given) || '未命名';
        let hit = hitMap.get(contactName);
        if (!hit) {
          hit = { name: contactName, phones: [] };
          hitMap.set(contactName, hit);
        }

        for (const p of c.phoneNumbers ?? []) {
          if (p.phoneNumber && !hit.phones.includes(p.phoneNumber)) {
            hit.phones.push(p.phoneNumber);
          }
        }
        for (const e of c.emails ?? []) {
          if (e.email) {
            if (!hit.emails) hit.emails = [];
            if (!hit.emails.includes(e.email)) hit.emails.push(e.email);
          }
        }
        if (!hit.org && c.organization?.name) {
          hit.org = c.organization.name;
        }
      }

      const hits: ContactHit[] = [];
      const maxHits = Math.max(1, Math.min(limit, 20));
      hitMap.forEach((hit: ContactHit) => {
        if (hits.length < maxHits) {
          hits.push(hit);
        }
      });

      const payload: ContactsPayload = { contacts: hits, total: hits.length };
      return { ok: true, payloadJson: JSON.stringify(payload) };
    } catch (e) {
      const raw = e as Record<string, Object>;
      const code = typeof raw['code'] === 'number' ? raw['code'] as number : -1;
      const msgRaw = typeof raw['message'] === 'string'
        ? raw['message'] as string
        : (e instanceof Error ? (e as Error).message : JSON.stringify(raw));
      const message = code === 201
        ? '通讯录权限未授予 (READ_CONTACTS)'
        : (msgRaw && msgRaw !== 'null' && msgRaw !== '{}' ? msgRaw : '通讯录查询失败 (code=' + code + ')');
      return this.makeError('CONTACTS_QUERY_FAILED', message);
    }
  }

  private makeError(code: string, message: string): InvokeResult {
    const err: InvokeError = { code, message };
    return { ok: false, error: err };
  }
}
