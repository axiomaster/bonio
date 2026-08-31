import { GatewaySession } from '../gateway/GatewaySession';

export class BonioMemory {
  id: string = '';
  title: string = '';
  content: string = '';
  source: string = '';
  createdAt: number = 0;
  tags: string[] = [];
  sourceApp: string = '';
  pageTitle: string = '';
  pageLink: string = '';
}

class MemoListParams {
  limit: number = 200;
}

class MemoIdParams {
  id: string = '';
}

function stringValue(value: Object | undefined): string {
  return typeof value === 'string' ? value : '';
}

function numberValue(value: Object | undefined): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function toMemory(value: Object): BonioMemory {
  const raw = value as Record<string, Object>;
  const memory = new BonioMemory();
  memory.id = stringValue(raw['id']);
  memory.title = stringValue(raw['title']);
  memory.content = stringValue(raw['content']);
  memory.source = stringValue(raw['source']);
  memory.createdAt = numberValue(raw['createdAt']);
  memory.sourceApp = stringValue(raw['sourceApp']);
  memory.pageTitle = stringValue(raw['pageTitle']);
  memory.pageLink = stringValue(raw['pageLink']);
  const rawTags = raw['tags'];
  if (Array.isArray(rawTags)) {
    memory.tags = rawTags.filter((tag: Object): boolean => typeof tag === 'string') as string[];
  }
  return memory;
}

/** Read and manage structured memories persisted by the local DSH bridge. */
export class MemoryService {
  private session: GatewaySession;

  constructor(session: GatewaySession) {
    this.session = session;
  }

  async list(): Promise<BonioMemory[]> {
    const params = new MemoListParams();
    const response = await this.session.request('memo.list', params);
    const payload = response.payload as Record<string, Object> ||
      (response.payloadJSON ? JSON.parse(response.payloadJSON) as Record<string, Object> : undefined);
    const rawMemos = payload?.['memos'];
    if (!Array.isArray(rawMemos)) return [];
    return rawMemos
      .filter((item: Object): boolean => item !== null && typeof item === 'object')
      .map((item: Object): BonioMemory => toMemory(item));
  }

  async get(id: string): Promise<BonioMemory | undefined> {
    const params = new MemoIdParams();
    params.id = id;
    const response = await this.session.request('memo.get', params);
    const payload = response.payload as Record<string, Object> ||
      (response.payloadJSON ? JSON.parse(response.payloadJSON) as Record<string, Object> : undefined);
    const rawMemo = payload?.['memo'];
    return rawMemo && typeof rawMemo === 'object' ? toMemory(rawMemo) : undefined;
  }

  async delete(id: string): Promise<void> {
    const params = new MemoIdParams();
    params.id = id;
    await this.session.request('memo.delete', params);
  }
}
