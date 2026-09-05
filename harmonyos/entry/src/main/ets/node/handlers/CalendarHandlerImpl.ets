import { InvokeResult, InvokeError } from '../../gateway/GatewaySession';
import { CalendarHandler } from '../InvokeDispatcher';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import calendarManager from '@ohos.calendarManager';

/** One calendar event, flattened for the DSH agent. */
interface EventHit {
  title: string;
  startTs: number;
  endTs: number;
  allDay: boolean;
  location?: string;
}

interface EventsPayload {
  events: EventHit[];
  total: number;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Calendar lookup for Magic Cue. Reads events in a window (default today ±7
 * days; a title query searches all events and is client-side bounded to
 * ±90 days). Uses READ_CALENDAR.
 */
export class CalendarHandlerImpl implements CalendarHandler {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async handleCalendarEvents(paramsJson: string | undefined): Promise<InvokeResult> {
    let fromTs: number | undefined;
    let toTs: number | undefined;
    let titleQuery: string | undefined;
    let limit = 10;
    if (paramsJson) {
      try {
        const params = JSON.parse(paramsJson) as Record<string, Object>;
        if (typeof params['fromTs'] === 'number') fromTs = params['fromTs'] as number;
        if (typeof params['toTs'] === 'number') toTs = params['toTs'] as number;
        if (typeof params['titleQuery'] === 'string') titleQuery = (params['titleQuery'] as string).trim();
        if (typeof params['limit'] === 'number') limit = params['limit'] as number;
      } catch (_) {
        return this.makeError('INVALID_REQUEST', 'calendar.events params must be valid JSON');
      }
    }

    const now = Date.now();
    const query = titleQuery || '';
    const effectiveFrom = fromTs ?? now - 7 * DAY_MS;
    const effectiveTo = toTs ?? now + 7 * DAY_MS;

    try {
      const manager = calendarManager.getCalendarManager(this.context);
      const calendar = await manager.getCalendar();
      // getEvents accepts a single EventFilter; title and time filters cannot
      // be combined, so title queries fetch all matches and are bounded below.
      const events = query
        ? await calendar.getEvents(calendarManager.EventFilter.filterByTitle(query))
        : await calendar.getEvents(calendarManager.EventFilter.filterByTime(effectiveFrom, effectiveTo));

      const windowFrom = query ? now - 90 * DAY_MS : effectiveFrom;
      const windowTo = query ? now + 90 * DAY_MS : effectiveTo;
      const hits: EventHit[] = [];
      for (const e of events) {
        if (e.startTime > windowTo || e.endTime < windowFrom) continue;
        const hit: EventHit = {
          title: e.title ?? '未命名日程',
          startTs: e.startTime,
          endTs: e.endTime,
          allDay: e.isAllDay ?? false,
        };
        const location = e.location?.location;
        if (location) hit.location = location;
        hits.push(hit);
        if (hits.length >= Math.max(1, Math.min(limit, 20))) break;
      }

      hits.sort((a, b) => a.startTs - b.startTs);
      const payload: EventsPayload = { events: hits, total: hits.length };
      return { ok: true, payloadJson: JSON.stringify(payload) };
    } catch (e) {
      const businessError = e as BusinessError;
      const message = businessError.code === 201
        ? '日历权限未授予 (READ_CALENDAR)'
        : businessError.message || (e as Error).message || String(e);
      return this.makeError('CALENDAR_QUERY_FAILED', message);
    }
  }

  private makeError(code: string, message: string): InvokeResult {
    const err: InvokeError = { code, message };
    return { ok: false, error: err };
  }
}
