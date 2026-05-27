# Cron Agent Tools Design

## Problem

HiClaw has cron infrastructure (expression parser + job store) but it's CLI-only. The AI agent cannot dynamically create or manage scheduled tasks. When a user says "take a screenshot every minute until I say stop", the agent replies "I can't do that".

OpenClaw supports this via a full `cron` tool set integrated with the agent pipeline.

## Goal

Enable the AI agent to create, list, remove, and inspect scheduled tasks through natural conversation. Tasks execute via the existing `AsyncAgentManager` pipeline and deliver results to the originating session (WeChat/desktop).

## Scope

- **Three schedule types**: `every` (interval), `at` (one-shot), `cron` (expression)
- **Auto-delivery**: Task results sent to the session that created the task
- **Stop conditions**: `maxCount` and `maxDuration` per task, plus manual `cron.remove`
- **Execution history**: Last 20 runs per job with success/failure and result summary
- **Agent tools**: `cron.add`, `cron.list`, `cron.remove`, `cron.runs`
- **Gateway RPC**: `cron.list`, `cron.add`, `cron.remove`, `cron.history` (for future desktop UI)
- **Persistence**: Jobs saved to `<config_dir>/cron/jobs.json`, restored on Gateway restart

## Architecture

### Approach: Built-in Scheduler (Option A)

A `CronScheduler` runs as a background thread inside the Gateway process. Every second it checks for due jobs and dispatches them via `AsyncAgentManager.start_task()`.

```
Gateway Process
  ├─ CronScheduler thread (1s tick loop)
  │   ├─ Check each enabled job: now >= next_run?
  │   ├─ Due → AsyncAgentManager.start_task(session_key, prompt)
  │   ├─ Increment run_count, check stop conditions
  │   └─ Compute next_run
  │
  ├─ Agent tools (cron.add/list/remove/runs)
  │   └─ tool.cpp execute_tool() → CronScheduler methods
  │
  └─ Gateway RPC (cron.list/add/remove/history)
      └─ gateway.cpp handlers → CronScheduler methods
```

## Data Model

### CronJob

```cpp
struct CronJob {
  // Identity
  std::string id;            // "cron_xxxx" (auto-generated)
  std::string session_key;   // Session to run in & deliver to

  // Schedule
  std::string schedule_type; // "every" | "at" | "cron"
  int every_ms;              // for "every": interval in ms
  int64_t at_timestamp;      // for "at": Unix ms (one-shot)
  std::string cron_expr;     // for "cron": 5-field expression

  // Task
  std::string prompt;        // What the agent should do each run

  // Stop conditions
  int max_count;             // 0 = unlimited
  int max_duration_ms;       // 0 = unlimited

  // Runtime state
  int run_count;
  int64_t created_at;
  int64_t next_run;          // Unix ms
  bool enabled;

  // Run history (last 20)
  struct RunRecord {
    int64_t started_at;
    int64_t completed_at;
    bool success;
    std::string result_summary;  // First 200 chars
  };
  std::vector<RunRecord> recent_runs;
};
```

### Persistence Format (`jobs.json`)

```json
{
  "jobs": [
    {
      "id": "cron_a1b2c3",
      "sessionKey": "wechat:weixin:user123",
      "scheduleType": "every",
      "everyMs": 60000,
      "prompt": "截取屏幕并发送截图",
      "maxCount": 10,
      "maxDurationMs": 0,
      "runCount": 3,
      "createdAt": 1748294400000,
      "nextRun": 1748294580000,
      "enabled": true,
      "recentRuns": [
        {
          "startedAt": 1748294400000,
          "completedAt": 1748294415000,
          "success": true,
          "resultSummary": "截图已发送"
        }
      ]
    }
  ]
}
```

## Components

### 1. CronScheduler (`server/src/cron/scheduler.cpp`)

**Responsibilities:**
- Background thread with 1-second tick loop
- Check enabled jobs for due execution
- Dispatch due jobs to `AsyncAgentManager`
- Track run count, check stop conditions
- Compute `next_run` after each execution
- Thread-safe job CRUD (add/list/remove)
- Persist jobs to disk on every mutation
- Restore jobs from disk on Gateway startup

**Interface:**
```cpp
class CronScheduler {
public:
  CronScheduler(const config::Config& config,
                std::shared_ptr<session::SessionStore> session_store);

  void start(std::shared_ptr<AsyncAgentManager> agent_manager);
  void stop();

  // CRUD (thread-safe)
  std::string add_job(const CronJob& job);          // Returns job_id
  bool remove_job(const std::string& job_id);
  std::vector<CronJob> list_jobs() const;
  std::vector<CronJob::RunRecord> get_runs(const std::string& job_id) const;

private:
  void scheduler_loop();
  void compute_next_run(CronJob& job);
  void save_jobs();
  void load_jobs();
};
```

**Thread model:**
- Scheduler runs in its own `std::thread`
- All job mutations protected by `std::mutex`
- Agent execution uses `AsyncAgentManager`'s thread pool (same as WeChat/desktop)

**Startup recovery:**
- Load `jobs.json` from disk
- Recompute `next_run` for all enabled jobs
- Resume scheduling

**Completion tracking:**
When dispatching a job, CronScheduler wraps the agent's event callback to intercept the `chat` event with `state: "final"`. This allows it to:
1. Record `RunRecord` with completion time and result summary (first 200 chars of the response)
2. Track `run_count` and check stop conditions
3. Compute `next_run` for the next execution

The wrapper calls the original event callback first (so results still reach WeChat/desktop), then records the run.

**Session key propagation:**
`execute_tool()` is called from `agent.cpp`'s agent loop, which runs inside `AsyncAgentManager::run_task()`. The `session_key` is available in the task context. A new `session_key` parameter is added to the tool execution callback signature so tools like `cron.add` can bind the job to the originating session.

### 2. Agent Tools (`server/src/tools/tool.cpp`)

Four new tools added to `all_tools_array()`:

**cron.add:**
```json
{
  "type": "function",
  "function": {
    "name": "cron.add",
    "description": "Create a scheduled task that runs periodically or at a specific time. Use 'every' for intervals (e.g. 'every 1m'), 'at' for one-shot (e.g. 'at +30m'), 'cron' for cron expressions (e.g. '0 9 * * *').",
    "parameters": {
      "type": "object",
      "properties": {
        "schedule": {"type": "string", "description": "Schedule: 'every <interval>' | 'at <offset>' | 'cron <expr>'. Intervals: 30s, 1m, 5m, 1h. Offsets: +30m, +1h."},
        "prompt": {"type": "string", "description": "What the agent should do on each execution"},
        "maxCount": {"type": "integer", "description": "Max executions (0=unlimited)", "default": 0},
        "maxDuration": {"type": "string", "description": "Max duration (e.g. '1h', '30m'). Empty=unlimited.", "default": ""}
      },
      "required": ["schedule", "prompt"]
    }
  }
}
```

**cron.list:**
```json
{
  "type": "function",
  "function": {
    "name": "cron.list",
    "description": "List all scheduled tasks with their status, schedule, and run count.",
    "parameters": {"type": "object", "properties": {}}
  }
}
```

**cron.remove:**
```json
{
  "type": "function",
  "function": {
    "name": "cron.remove",
    "description": "Remove/stop a scheduled task by its ID.",
    "parameters": {
      "type": "object",
      "properties": {
        "jobId": {"type": "string", "description": "The cron job ID to remove"}
      },
      "required": ["jobId"]
    }
  }
}
```

**cron.runs:**
```json
{
  "type": "function",
  "function": {
    "name": "cron.runs",
    "description": "View execution history for a scheduled task.",
    "parameters": {
      "type": "object",
      "properties": {
        "jobId": {"type": "string", "description": "The cron job ID"}
      },
      "required": ["jobId"]
    }
  }
}
```

**Execution in `execute_tool()`:**
- `cron.add`: Parse schedule string, create `CronJob`, inject `session_key` from current context, call `scheduler->add_job()`. Return job_id + next_run time.
- `cron.list`: Call `scheduler->list_jobs()`. Format as readable text.
- `cron.remove`: Call `scheduler->remove_job(job_id)`. Return confirmation.
- `cron.runs`: Call `scheduler->get_runs(job_id)`. Format run history.

**Schedule parsing:**
- `every <duration>`: Parse "30s"/"1m"/"5m"/"1h" → milliseconds
- `at <offset>`: Parse "+30m"/"+1h" → absolute timestamp
- `cron <expr>`: Validate with existing `cron::Schedule` parser

### 3. Gateway RPC (`server/src/net/gateway.cpp`)

Add RPC handlers for `cron.list`, `cron.add`, `cron.remove`, `cron.history`.

These mirror the agent tools but are called directly by the desktop UI via WebSocket. The `cron.add` RPC takes the same parameters plus `sessionKey`.

### 4. Integration Points

**Gateway startup:**
```
gateway.cpp start_gateway()
  ├─ Create CronScheduler
  ├─ Create AsyncAgentManager (pass CronScheduler reference)
  ├─ Create WeChatAdapter (pass AsyncAgentManager)
  ├─ CronScheduler.start(AsyncAgentManager)
  └─ ...
```

**Agent context:**
When `execute_tool()` handles `cron.add`, it needs the current `session_key` to bind the job to the originating session. This is passed through the existing tool execution context.

**Tool availability:**
Cron tools are available in ALL agent contexts (WeChat, desktop chat, standalone). The `all_tools_array()` function includes them alongside existing tools (shell, file, web, memory, etc.).

## Execution Flow

### Example: "每分钟截一次屏，截10次后停"

```
1. User → Agent: "每分钟截一次屏，截10次后停"
2. LLM → tool_call: cron.add(schedule="every 1m", prompt="截取屏幕并发送截图", maxCount=10)
3. execute_tool("cron.add") → CronScheduler.add_job(...)
4. CronScheduler: job added, next_run = now + 60s
5. Agent → User: "已创建定时截屏任务，每分钟执行一次，共执行10次。"

--- 60s later ---

6. CronScheduler: job due → AsyncAgentManager.start_task(session_key, "截取屏幕并发送截图")
7. Agent loop: LLM → tool_call screen.capture → nodeSession → screenshot PNG
8. Image sent to WeChat / displayed in desktop
9. Agent: "截图已发送" → delivered to session
10. CronScheduler: run_count=1, next_run = now + 60s

--- Repeats 10 times ---

11. After run 10: maxCount reached → job.enabled = false
12. Agent: "截屏任务已完成，共执行10次。" → delivered to session
```

### Example: "停止截屏"

```
1. User → Agent: "停止截屏"
2. LLM → tool_call: cron.list()
3. execute_tool("cron.list") → returns active jobs
4. LLM → tool_call: cron.remove(jobId="cron_a1b2c3")
5. CronScheduler: job removed
6. Agent → User: "已停止截屏任务。"
```

## Files to Create/Modify

### New files
| File | Purpose |
|------|---------|
| `server/include/hiclaw/cron/scheduler.hpp` | CronScheduler class header |
| `server/src/cron/scheduler.cpp` | Scheduler implementation |

### Modified files
| File | Change |
|------|--------|
| `server/src/tools/tool.cpp` | Add cron tool definitions + execution |
| `server/src/agent/agent.cpp` | Include cron tools in all_tools_array() |
| `server/src/net/gateway.cpp` | Add CronScheduler, cron RPC handlers, pass to tools |
| `server/src/net/wechat_adapter.cpp` | Pass CronScheduler reference if needed |
| `server/src/net/async_agent.cpp` | Pass session_key context to tool executor |
| `server/include/hiclaw/tools/tool.hpp` | Update ToolRouter to accept CronScheduler |

## Out of Scope (Future)

- Desktop UI for cron management (API ready, UI not built)
- Webhook delivery notifications
- Multi-account delivery
- Task timeout / error backoff / retry policies
- Permission scopes for restricted cron runs
