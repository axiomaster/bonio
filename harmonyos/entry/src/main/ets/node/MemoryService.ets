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
  coverImage: string = '';
  originalImage: string = '';
  originalImageMimeType: string = '';
}

export class SaveBonioMemory {
  title: string = '';
  content: string = '';
  source: string = '';
  tags: string[] = [];
  sourceApp: string = '';
  pageTitle: string = '';
  pageLink: string = '';
  coverImage: string = '';
  originalImage: string = '';
  originalImageMimeType: string = '';
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
  memory.coverImage = stringValue(raw['coverImage']);
  memory.originalImage = stringValue(raw['originalImage']);
  memory.originalImageMimeType = stringValue(raw['originalImageMimeType']);
  const rawTags = raw['tags'];
  if (Array.isArray(rawTags)) {
    memory.tags = rawTags.filter((tag: Object): boolean => typeof tag === 'string') as string[];
  }
  return memory;
}

/** Read and manage structured memories persisted by the local DSH bridge. */
export class MemoryService {
  private session: GatewaySession;
  private changeListeners: Array<() => void> = [];

  constructor(session: GatewaySession) {
    this.session = session;
  }

  addChangeListener(listener: () => void): void {
    if (!this.changeListeners.includes(listener)) this.changeListeners.push(listener);
  }

  removeChangeListener(listener: () => void): void {
    this.changeListeners = this.changeListeners.filter((candidate: () => void): boolean => candidate !== listener);
  }

  private notifyChanged(): void {
    this.changeListeners.forEach((listener: () => void) => listener());
  }

  async save(memory: SaveBonioMemory): Promise<void> {
    await this.session.request('memo.save', memory);
    this.notifyChanged();
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
    this.notifyChanged();
  }
}
