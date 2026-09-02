import { randomUUID } from 'node:crypto';
import { installModelSelection } from '@deepseek-ai/dsh-agent';
import { createUserMessage } from '@deepseek-ai/dsh-llm';
import { SessionId } from '@deepseek-ai/dsh-session';
import fs from 'node:fs/promises';
import path from 'node:path';
import { listMemos, saveMemo } from './memo_store.js';
export const INVOKE_TIMEOUT_MS = 300_000;
export class AgentDriver {
    ctx;
    registry;
    sink;
    forwardInvoke;
    runs = new Map();
    /** sessionKey -> live agent (multi-turn continuity within one operator session). */
    agentsByKey = new Map();
    /** sessionKey -> durable dsh sessionId, persisted across dsh restarts. */
    sessionMapFile = () => {
        const home = process.env.DSH_HOME || process.env.HOME || '/data/local/home';
        const base = home !== '/root' ? home : '/data/local/home';
        return path.join(base, '.bonio', 'session-map.json');
    };
    async loadSessionMap() {
        try {
            const raw = await fs.readFile(this.sessionMapFile(), 'utf8');
            return JSON.parse(raw);
        }
        catch {
            return {};
        }
    }
    async saveSessionMap(map) {
        try {
            await fs.mkdir(path.dirname(this.sessionMapFile()), { recursive: true });
            await fs.writeFile(this.sessionMapFile(), JSON.stringify(map, null, 2));
        }
        catch (e) {
            console.log('[bonio-bridge] session-map save failed:', e instanceof Error ? e.message : String(e));
        }
    }
    constructor(ctx, registry, sink, forwardInvoke) {
        this.ctx = ctx;
        this.registry = registry;
        this.sink = sink;
        this.forwardInvoke = forwardInvoke;
    }
    /** Create (or reuse) the dsh agent bound to a hiclaw sessionKey. */
    async getOrCreateAgent(sessionKey, ephemeral = false) {
        if (!ephemeral && sessionKey && this.agentsByKey.has(sessionKey)) {
            return this.agentsByKey.get(sessionKey);
        }
        const agents = this.ctx.get('agents');
        const defaultModel = this.ctx.get('agentDefaultModel');
        if (!agents || !defaultModel)
            return null;
        const selection = defaultModel.currentSelection();
        console.log('[bonio-bridge] using model', `${selection.provider}/${selection.model}`);
        const setup = (agentCtx) => {
            installModelSelection(agentCtx, { current: selection, assembled: undefined });
        };
        // Resume a persisted session when this sessionKey has one.
        if (!ephemeral && sessionKey) {
            const map = await this.loadSessionMap();
            const persistedId = map[sessionKey];
            if (persistedId && typeof agents.resume === 'function') {
                try {
                    const { agent } = await agents.resume({
                        resumeSessionId: SessionId(persistedId),
                        agentOptions: { provider: selection.provider, model: selection.model },
                        setup,
                    });
                    this.agentsByKey.set(sessionKey, agent);
                    return agent;
                }
                catch (e) {
                    console.log('[bonio-bridge] resume failed for', sessionKey, ':', e instanceof Error ? e.message : String(e));
                }
            }
        }
        const agentId = `session-${randomUUID()}`;
        const { agent } = await agents.create({
            sessionId: SessionId(agentId),
            meta: { cwd: process.cwd() },
            agentOptions: { provider: selection.provider, model: selection.model },
            setup,
        });
        if (!ephemeral && sessionKey) {
            this.agentsByKey.set(sessionKey, agent);
            const map = await this.loadSessionMap();
            map[sessionKey] = agentId;
            await this.saveSessionMap(map);
        }
        return agent;
    }
    /** Build hiclaw messages from dsh session events. */
    messagesFromEvents(events) {
        const messages = [];
        for (const e of events) {
            let msg = null;
            if (e.type === 'user/message')
                msg = e.data;
            else if (e.type === 'assistant/message')
                msg = e.data?.message;
            if (!msg)
                continue;
            const content = (msg.content ?? []).map((b) => {
                const out = { type: b.type ?? 'text' };
                if (typeof b.text === 'string')
                    out.text = b.text;
                if (typeof b.mimeType === 'string')
                    out.mimeType = b.mimeType;
                if (typeof b.fileName === 'string')
                    out.fileName = b.fileName;
                if (b.image != null)
                    out.content = b.image;
                return out;
            });
            messages.push({ role: msg.role ?? 'user', content, timestamp: e.time ?? Date.now() });
        }
        return messages;
    }
    /** Read chat history for a sessionKey from the live agent or durable store. */
    async getHistory(sessionKey) {
        const agent = sessionKey && this.agentsByKey.get(sessionKey);
        if (agent) {
            return {
                messages: this.messagesFromEvents(agent.session?.events ?? []),
                sessionId: sessionKey,
                thinkingLevel: undefined,
            };
        }
        if (sessionKey) {
            const map = await this.loadSessionMap();
            const persistedId = map[sessionKey];
            if (persistedId) {
                try {
                    const persistence = this.ctx.get('sessionPersistence');
                    if (persistence && typeof persistence.load === 'function') {
                        const { events } = await persistence.load(persistedId);
                        return {
                            messages: this.messagesFromEvents(events ?? []),
                            sessionId: sessionKey,
                            thinkingLevel: undefined,
                        };
                    }
                }
                catch (e) {
                    console.log('[bonio-bridge] history load failed for', sessionKey, ':', e instanceof Error ? e.message : String(e));
                }
            }
        }
        return { messages: [], sessionId: sessionKey, thinkingLevel: undefined };
    }
    /** List active + persisted operator sessions. */
    async listSessions() {
        const sessions = [];
        const seen = new Set();
        for (const [key, agent] of this.agentsByKey) {
            const events = agent.session?.events ?? [];
            let displayName = key;
            let updatedAt = Date.now();
            for (let i = events.length - 1; i >= 0; i--) {
                const e = events[i];
                if (e.type === 'user/message') {
                    const texts = (e.data?.content ?? [])
                        .filter((b) => b.type === 'text' && typeof b.text === 'string')
                        .map((b) => b.text);
                    if (texts.length > 0) {
                        displayName = texts[0].slice(0, 30);
                        updatedAt = e.time ?? updatedAt;
                        break;
                    }
                }
            }
            sessions.push({ key, updatedAt, displayName });
            seen.add(key);
        }
        const map = await this.loadSessionMap();
        for (const [key, sessionId] of Object.entries(map)) {
            if (seen.has(key))
                continue;
            let displayName = key;
            let updatedAt = Date.now();
            try {
                const persistence = this.ctx.get('sessionPersistence');
                if (persistence && typeof persistence.load === 'function') {
                    const { events } = await persistence.load(sessionId);
                    for (let i = (events ?? []).length - 1; i >= 0; i--) {
                        const e = events[i];
                        if (e.type === 'user/message') {
                            const texts = (e.data?.content ?? [])
                                .filter((b) => b.type === 'text' && typeof b.text === 'string')
                                .map((b) => b.text);
                            if (texts.length > 0) {
                                displayName = texts[0].slice(0, 30);
                                updatedAt = e.time ?? updatedAt;
                                break;
                            }
                        }
                    }
                }
            }
            catch { /* skip */ }
            sessions.push({ key, updatedAt, displayName });
        }
        return { sessions };
    }
    async runChat(params) {
        const ctx = this.ctx;
        const agents = ctx.get('agents');
        const sessions = ctx.get('sessions');
        if (!agents || !sessions)
            return { runId: '', error: 'dsh agent services unavailable' };
        await ctx.get('loader')?.await?.();
        // bonio-app sends idempotencyKey as its own runId; reuse it so its
        // pendingRuns filter matches our agent/chat events immediately.
        const runId = params.runId || randomUUID();
        const controller = new AbortController();
        // Fire-and-forget: return the runId right away; agent events stream as
        // they happen and the chat final arrives when the run completes.
        void this._run(runId, params, controller);
        return { runId };
    }
    async _run(runId, params, controller) {
        const ctx = this.ctx;
        const sessions = ctx.get('sessions');
        try {
            if (!sessions) {
                throw new Error('dsh session service unavailable');
            }
            // Screen-awareness payloads are independently summarized and persisted
            // as memos. Reusing their DSH chat history makes raw UI trees grow until
            // they exceed the model context window.
            const agent = await this.getOrCreateAgent(params.sessionKey, params.sessionKey === 'system:companion-memory');
            if (!agent) {
                throw new Error('dsh agent services unavailable');
            }
            this.runs.set(runId, { agent, controller });
            const firstSeq = agent.session.seq;
            // bonio-app's handleAgentEvent REPLACES streamingAssistantText with
            // data.text, so send cumulative text, not per-chunk deltas.
            let cumulative = '';
            const onEvent = (subject, event) => {
                if (subject !== agent.session)
                    return;
                if (event.type === 'assistant/chunk') {
                    const chunk = event.data?.chunk;
                    const text = chunk && chunk.type === 'text-delta' ? (chunk.text ?? '') : '';
                    if (text) {
                        cumulative += text;
                        this.sink.agentDelta(runId, params.sessionKey, cumulative);
                    }
                }
            };
            const off = ctx.on('session/event', onEvent);
            await agent.whenIdle();
            const content = [{ type: 'text', text: params.text }];
            if (params.attachments && params.attachments.length > 0) {
                const attachmentStore = ctx.get('attachments');
                if (!attachmentStore)
                    throw new Error('image attachment service unavailable');
                for (const attachment of params.attachments) {
                    const mediaType = attachment.mimeType === 'image/png' || attachment.mimeType === 'image/webp' ||
                        attachment.mimeType === 'image/gif' ? attachment.mimeType : 'image/jpeg';
                    const data = Buffer.from(attachment.content, 'base64');
                    if (data.length === 0)
                        throw new Error('image attachment is empty');
                    const ref = await attachmentStore.saveImage({
                        data: new Uint8Array(data),
                        mediaType,
                        name: attachment.fileName || 'bonio-screen.jpg',
                    });
                    content.push({ type: 'image', attachment: ref });
                }
                console.log('[bonio-bridge] attached', params.attachments.length, 'image(s) to dsh message');
            }
            agent.followup(createUserMessage({
                content,
                source: { kind: 'user' },
            }));
            await agent.whenIdle();
            off?.();
            const events = agent.session.events ?? [];
            let text = '';
            let reason;
            const toolResults = [];
            for (const e of events) {
                if (e.seq < firstSeq)
                    continue;
                if (e.type === 'assistant/message') {
                    const joined = (e.data?.message?.content ?? [])
                        .filter((b) => b.type === 'text')
                        .map((b) => b.text)
                        .join('');
                    if (joined !== '')
                        text = joined;
                }
                if (e.type === 'turn/end')
                    reason = e.data?.reason;
                if (e.type === 'tool/result') {
                    const blocks = e.data?.message?.content ?? [];
                    for (const b of blocks) {
                        if (b.type === 'tool-result' && typeof b.content === 'string') {
                            try {
                                const parsed = JSON.parse(b.content);
                                const value = parsed?.value;
                                if (value && Array.isArray(value.memos)) {
                                    if (value.memos.length === 0)
                                        toolResults.push('没有保存的备忘。');
                                    else
                                        toolResults.push('共有 ' + value.memos.length + ' 条备忘:\n' + value.memos.map((m) => '- ' + (m.title || '') + ': ' + (m.content || '')).join('\n'));
                                }
                                else {
                                    toolResults.push(b.content);
                                }
                            }
                            catch {
                                toolResults.push(b.content);
                            }
                        }
                    }
                }
            }
            // DeepSeek may end the turn right after a tool call without a text reply.
            if (text === '' && toolResults.length > 0)
                text = toolResults.join('\n');
            await sessions.flush(agent.session);
            this.runs.delete(runId);
            const errorMessage = reason && reason.kind === 'error'
                ? (reason.error?.message ?? 'agent error')
                : undefined;
            this.sink.chatFinal(runId, params.sessionKey, errorMessage
                ? { state: 'error', errorMessage, done: true }
                : { message: text, text, state: 'final', done: true });
            return;
        }
        catch (error) {
            this.runs.delete(runId);
            const message = error instanceof Error ? error.message : String(error);
            this.sink.chatFinal(runId, params.sessionKey, { text: '', state: 'error', errorMessage: message, done: true });
        }
    }
    abort(runId) {
        const run = this.runs.get(runId);
        if (run) {
            try {
                run.controller.abort();
                void run.agent.cancel?.('aborted by user');
            }
            catch { /* ignore */ }
            this.runs.delete(runId);
        }
    }
    registerBridgeTool(defineTool, register) {
        const bridge = this;
        const def = defineTool({
            name: 'bonio_node_invoke',
            description: 'Invoke a device capability on the companion bonio-app node session (camera, screen capture, location, sms, canvas, input typing, system notifications, calendar, contacts, and similar device commands). Returns the device result payload.',
            parameters: {
                command: {
                    type: 'string',
                    required: true,
                    description: 'Device command name, e.g. camera.snap, screen.capture, sms.send, location.get, canvas.present, input.type, system.notify, calendar.events, contacts.search.',
                },
                arguments: { type: 'object', additionalProperties: true, description: 'Command arguments as a JSON object, e.g. {"text":"hello"} for input.type.' },
                timeoutMs: { type: 'number', description: 'Timeout in milliseconds; default 300000.' },
            },
            output: {
                schema: { type: 'object', additionalProperties: true, description: 'The device result payload returned by the node session.' },
                render(args, value) {
                    if (value && typeof value === 'object' && value.error) {
                        return 'device tool error: ' + String(value.error);
                    }
                    try {
                        return JSON.stringify(value, null, 2);
                    }
                    catch {
                        return String(value);
                    }
                },
            },
            async execute(args, exec) {
                const { command, arguments: cmdArgs = {}, timeoutMs = INVOKE_TIMEOUT_MS } = args ?? {};
                const node = bridge.registry.getNode();
                if (!node)
                    return { isError: true, error: { message: 'no node session connected to the bonio bridge' } };
                const callId = randomUUID();
                const result = await bridge.forwardInvoke(callId, command, cmdArgs, timeoutMs);
                if (result.ok)
                    return { isError: false, value: result.payload ?? {} };
                return { isError: true, error: { message: result.error?.message ?? 'device tool failed' } };
            },
        });
        return register(def);
    }
    /** hiclaw-parity local tools running entirely inside dsh (memo, device info). */
    registerLocalTools(defineTool, register) {
        const disposers = [];
        disposers.push(register(defineTool({
            name: 'memo_save',
            description: 'Save a memo/note. Use when the user asks to remember, save, or note something from the screen or conversation.',
            parameters: {
                title: { type: 'string', required: true, description: 'Short title for the memo.' },
                content: { type: 'string', required: true, description: 'The content to save.' },
                source: { type: 'string', description: 'Source of the memo (e.g. screen, voice).' },
                tags: { type: 'array', items: { type: 'string' }, description: 'Up to three concise category tags.' },
                sourceApp: { type: 'string', description: 'Source application or bundle name.' },
                pageTitle: { type: 'string', description: 'Title of the source page.' },
                pageLink: { type: 'string', description: 'Canonical source page link when available.' },
            },
            output: {
                schema: { type: 'object', additionalProperties: true },
                render(args, value) {
                    const v = value;
                    return v && v.id ? `saved memo ${v.id}: ${v.title}` : JSON.stringify(value);
                },
            },
            async execute(args, exec) {
                const memo = await saveMemo(args ?? { title: '', content: '' });
                return { isError: false, value: { id: memo.id, title: memo.title } };
            },
        })));
        disposers.push(register(defineTool({
            name: 'memo_list',
            description: 'List saved memos/notes. Returns recent memos with title, content, and timestamp.',
            parameters: { limit: { type: 'number', description: 'Max number of memos to return; default 20.' } },
            output: {
                schema: { type: 'object', additionalProperties: true },
                render(args, value) {
                    try {
                        if (value && typeof value === 'object' && typeof value.text === 'string') {
                            return value.text;
                        }
                        return JSON.stringify(value);
                    }
                    catch {
                        return JSON.stringify(value);
                    }
                },
            },
            async execute(args, exec) {
                const memos = await listMemos(args?.limit ?? 20);
                if (memos.length === 0)
                    return { isError: false, value: { text: '没有保存的备忘。', memos: [] } };
                const lines = memos.map((m) => `- ${m.title}: ${m.content}`).join('\n');
                return { isError: false, value: { text: '共有 ' + memos.length + ' 条备忘:\n' + lines, memos } };
            },
        })));
        disposers.push(register(defineTool({
            name: 'device_info',
            description: 'Report information about this device and runtime (HarmonyOS, dsh/bridge versions, architecture).',
            parameters: {},
            output: {
                schema: { type: 'object', additionalProperties: true },
                render(args, value) { return JSON.stringify(value); },
            },
            async execute() {
                return { isError: false, value: { platform: process.platform, arch: process.arch, node: process.versions.node, dsh: 'bonio-bridge 0.1', os: process.env.OS || 'HarmonyOS/OpenHarmony' } };
            },
        })));
        // ── cron tools (file-persisted scheduler) ────────────────────────────────
        const cronDir = () => {
            const home = process.env.DSH_HOME || process.env.HOME || '/data/local/home';
            if (home !== '/root')
                return path.join(home, '.bonio', 'cron');
            return '/data/local/home/.bonio/cron';
        };
        const cronFile = () => path.join(cronDir(), 'jobs.json');
        const loadCronJobs = async () => {
            try {
                return JSON.parse(await fs.readFile(cronFile(), 'utf8'));
            }
            catch {
                return {};
            }
        };
        const saveCronJobs = async (jobs) => {
            await fs.mkdir(cronDir(), { recursive: true });
            await fs.writeFile(cronFile(), JSON.stringify(jobs, null, 2));
        };
        const parseSchedule = (schedule) => {
            const s = String(schedule || '').trim();
            const every = s.match(/^every\s+(\d+)\s*(s|m|h|d)?$/i);
            if (every) {
                const n = parseInt(every[1], 10);
                const unit = (every[2] || 'm').toLowerCase();
                const mult = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
                return { type: 'interval', ms: n * (mult[unit] || 60000) };
            }
            const at = s.match(/^at\s+\+(\d+)\s*(s|m|h|d)?$/i);
            if (at) {
                const n = parseInt(at[1], 10);
                const unit = (at[2] || 'm').toLowerCase();
                const mult = { s: 1000, m: 60000, h: 3600000, d: 86400000 };
                return { type: 'oneshot', ms: n * (mult[unit] || 60000) };
            }
            const cron = s.match(/^cron\s+(.+)$/i);
            if (cron)
                return { type: 'cron', expr: cron[1].trim() };
            return null;
        };
        disposers.push(register(defineTool({
            name: 'cron_add',
            description: 'Schedule a recurring or one-time task. Supports "every 5m" (interval), "at +30m" (one-shot), or "cron 0 9 * * *" (5-field cron expression).',
            parameters: {
                schedule: { type: 'string', required: true, description: "Schedule: 'every <duration>', 'at +<duration>', or 'cron <expr>'." },
                prompt: { type: 'string', required: true, description: 'The message/prompt to send to the agent when the task fires.' },
                maxCount: { type: 'number', description: 'Maximum number of times to run (0 = unlimited).' },
            },
            output: { schema: { type: 'object', additionalProperties: true }, render(_args, value) { return JSON.stringify(value); } },
            async execute(args, exec) {
                const { schedule, prompt, maxCount } = args ?? {};
                const parsed = parseSchedule(schedule);
                if (!parsed)
                    return { isError: true, error: { message: `unsupported schedule: ${schedule}` } };
                const jobs = await loadCronJobs();
                const jobId = `cron-${Date.now()}`;
                jobs[jobId] = { id: jobId, schedule, parsed, prompt, maxCount: maxCount ?? 0, runs: 0, createdAt: Date.now(), enabled: true };
                await saveCronJobs(jobs);
                return { isError: false, value: { id: jobId, schedule, prompt } };
            },
        })));
        disposers.push(register(defineTool({
            name: 'cron_list',
            description: 'List all scheduled cron jobs with their status and run counts.',
            parameters: {},
            output: { schema: { type: 'object', additionalProperties: true }, render(_args, value) { return JSON.stringify(value); } },
            async execute(args, exec) {
                const jobs = await loadCronJobs();
                const list = Object.values(jobs).map((j) => ({ id: j.id, schedule: j.schedule, prompt: String(j.prompt).slice(0, 60), runs: j.runs, enabled: j.enabled }));
                return { isError: false, value: { jobs: list } };
            },
        })));
        disposers.push(register(defineTool({
            name: 'cron_remove',
            description: 'Remove a scheduled cron job by its ID.',
            parameters: { jobId: { type: 'string', required: true, description: 'The ID of the cron job to remove.' } },
            output: { schema: { type: 'object', additionalProperties: true }, render(_args, value) { return JSON.stringify(value); } },
            async execute(args, exec) {
                const { jobId } = args ?? {};
                const jobs = await loadCronJobs();
                if (!jobs[jobId])
                    return { isError: true, error: { message: `cron job not found: ${jobId}` } };
                delete jobs[jobId];
                await saveCronJobs(jobs);
                return { isError: false, value: { removed: jobId } };
            },
        })));
        disposers.push(register(defineTool({
            name: 'cron_runs',
            description: 'Get recent execution history for a cron job.',
            parameters: { jobId: { type: 'string', required: true, description: 'The ID of the cron job to inspect.' } },
            output: { schema: { type: 'object', additionalProperties: true }, render(_args, value) { return JSON.stringify(value); } },
            async execute(args, exec) {
                const { jobId } = args ?? {};
                const jobs = await loadCronJobs();
                const job = jobs[jobId];
                if (!job)
                    return { isError: true, error: { message: `cron job not found: ${jobId}` } };
                return { isError: false, value: { id: jobId, runs: job.runs, lastRunAt: job.lastRunAt, schedule: job.schedule } };
            },
        })));
        const tickCron = async () => {
            try {
                const jobs = await loadCronJobs();
                const now = Date.now();
                let changed = false;
                for (const j of Object.values(jobs)) {
                    if (!j.enabled)
                        continue;
                    const due = j.parsed.type === 'oneshot'
                        ? (j.createdAt + j.parsed.ms <= now)
                        : (j.parsed.type === 'interval' ? ((j.lastRunAt || j.createdAt) + j.parsed.ms <= now) : false);
                    if (!due)
                        continue;
                    if (j.maxCount > 0 && j.runs >= j.maxCount) {
                        j.enabled = false;
                        changed = true;
                        continue;
                    }
                    j.runs += 1;
                    j.lastRunAt = now;
                    changed = true;
                    console.log('[bonio-bridge] cron firing', j.id, j.prompt);
                    void this.runChat({ text: String(j.prompt), sessionKey: `cron-${j.id}` }).catch(() => { });
                }
                if (changed)
                    await saveCronJobs(jobs);
            }
            catch (e) {
                console.log('[bonio-bridge] cron tick error:', e instanceof Error ? e.message : String(e));
            }
        };
        const cronTimer = setInterval(() => { void tickCron(); }, 30000);
        return () => {
            clearInterval(cronTimer);
            for (const dispose of disposers)
                dispose();
        };
    }
}
