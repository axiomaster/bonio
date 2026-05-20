# HiClaw Agent 能力增强 PRD

**版本**: 1.0  
**日期**: 2025-05-20  
**作者**: PM (hiclaw-capability team)  
**来源**: 基于 `docs/design/rr/20260520-hiclaw-capability-gap-analysis.md` 对标分析

---

## 1. 背景与目标

### 1.1 背景

HiClaw 是用 C++17 重写的 OpenClaw 服务器核心，负责 WebSocket 网关、LLM 调用路由、工具调用执行等核心功能。当前实现聚焦于基础能力，但与 OpenClaw 的成熟工具生态相比，存在明显的功能差距。

### 1.2 核心问题

1. **工具调用能力不足**: Agent 无法完成常见的用户场景（如截屏分析、Web 搜索、后台任务执行）
2. **Skill 系统未完善**: 虽然有 `skill.read` 工具和 `SkillManager`，但缺少 Agent 自进化的关键能力
3. **缺少关键工具**: 图像理解、会话管理、浏览器控制等重要功能完全缺失

### 1.3 目标

通过三个阶段的开发，补齐 P0-P2 核心能力，使 HiClaw Agent 能够：

- **Phase 1 (P0)**: 完成基本任务 — 截屏分析、Web 搜索、可靠 shell 执行
- **Phase 2 (P1)**: 处理复杂场景 — 会话管理、浏览器控制、文件编辑
- **Phase 3 (P2)**: 高级自动化 — 定时任务、进程管理、图像生成

---

## 2. 用户场景

### 场景 1: 微信截图助手 (WeChat Screenshot Assistant)

**用户**: "帮我分析一下这张截图"

**期望流程**:
1. Agent 调用 `screen.capture` 获取当前屏幕截图
2. Agent 调用 `image` 工具分析截图内容
3. Agent 返回分析结果（文字识别、UI 元素识别等）

**当前问题**: `screen.capture` 返回 `UNSUPPORTED_COMMAND`（Desktop 客户端未实现）

### 场景 2: 实时信息查询 (Real-time Information Query)

**用户**: "今天北京天气怎么样？"

**期望流程**:
1. Agent 调用 `web_search` 搜索相关信息
2. Agent 提取并总结结果
3. Agent 返回简洁的天气信息

**当前问题**: 完全缺失 `web_search` 工具

### 场景 3: Skill 自进化 (Agent Self-Evolution)

**用户**: "帮我部署一个 Node.js 应用"

**期望流程**:
1. Agent 检测到任务匹配 "nodejs-deploy" skill
2. Agent 调用 `skill.read` 加载 skill 指令
3. Agent 按照 skill 指令执行 shell 命令
4. Agent 完成部署任务

**当前状态**: `skill.read` 工具已实现，但 Skill 系统需要完善

---

## 3. 功能规格

### 3.1 工具调用框架增强

#### 3.1.1 工具分类体系

将工具按类别组织，便于管理和发现：

| 类别 | 工具示例 |
|------|----------|
| **Files** | file_read, file_write, edit, apply_patch |
| **Runtime** | shell, process, code_execution |
| **Web** | web_search, web_fetch, x_search |
| **Memory** | memory_store, memory_recall, memory_forget |
| **Sessions** | sessions_list, sessions_history, sessions_send |
| **Media** | image, image_generate |
| **UI** | screen.capture, browser, input.type |
| **Automation** | cron, gateway, nodes |
| **Skills** | skill.read, skill.install, skill.list |

#### 3.1.2 工具注册扩展

当前 `register_tool` 机制支持简单工具注册。扩展需求：

- **工具元数据**: 添加 `description`、`category`、`parameters` schema
- **工具发现**: 实现 `tools.list` 工具，让 Agent 知道可用工具
- **错误处理**: 统一错误码和错误消息格式

---

### 3.2 screen.capture — 截屏工具

#### 3.2.1 工具定义

**工具名称**: `screen.capture`  
**类别**: UI / Remote  
**描述**: Capture a screenshot of the user's current screen. Returns a base64-encoded image.

**参数**: 无

**返回值**:
```json
{
  "success": true,
  "image": "data:image/png;base64,iVBORw0KGgo...",
  "width": 1920,
  "height": 1080,
  "timestamp": 1716192000000
}
```

#### 3.2.2 实现要点

**Desktop 客户端**:
- 已有 `desktop/lib/platform/win32_screen_capture.dart` 实现
- 需要在 `NodeRuntime._onNodeInvoke()` 中添加 `screen.capture` 的处理
- 路由到现有的 `Win32ScreenCapture.capture()` 方法

**错误处理**:
- `UNSUPPORTED_PLATFORM`: 平台不支持（非 Windows）
- `CAPTURE_FAILED`: 截屏失败（权限问题等）

#### 3.2.3 边界情况

- 多显示器环境：默认捕获主显示器
- 屏幕内容加密：某些 DRM 内容可能显示为黑色

---

### 3.3 web_search — 网络搜索工具

#### 3.3.1 工具定义

**工具名称**: `web_search`  
**类别**: Web / Local  
**描述**: Search the web for information. Supports multiple search providers.

**参数**:
```json
{
  "query": "string (required) - 搜索查询",
  "count": "integer (optional) - 返回结果数量，默认 10，最大 50",
  "country": "string (optional) - 国家代码，如 CN, US",
  "language": "string (optional) - 语言代码，如 zh-CN, en-US",
  "freshness": "string (optional) - 时间范围：day, week, month, year",
  "date_after": "string (optional) - ISO 8601 日期，仅搜索此日期之后的结果",
  "date_before": "string (optional) - ISO 8601 日期，仅搜索此日期之前的结果"
}
```

**返回值**:
```json
{
  "success": true,
  "results": [
    {
      "title": "结果标题",
      "url": "https://example.com",
      "snippet": "结果摘要",
      "publishedDate": "2025-05-20",
      "score": 0.95
    }
  ],
  "totalResults": 1000,
  "searchTime": 0.5
}
```

#### 3.3.2 实现要点

**Phase 1 (P0)**:
- 集成至少一个搜索提供商（推荐 Brave Search API 或 Sogou API）
- 支持基本参数：query, count

**Phase 2 (P1)**:
- 添加高级参数：country, language, freshness
- 实现本地缓存（避免重复查询）

**错误处理**:
- `API_KEY_MISSING`: 缺少 API 密钥
- `RATE_LIMITED`: 达到速率限制
- `NO_RESULTS`: 无搜索结果

#### 3.3.3 安全考虑

- API 密钥通过 `hiclaw.json` 配置
- 限制单次查询返回结果数量（避免大量数据传输）
- 添加超时控制（默认 10 秒）

---

### 3.4 shell 增强 — Shell 执行工具

#### 3.4.1 当前问题

- 仅支持同步执行（阻塞）
- 无超时控制（可能永久挂起）
- 无后台执行能力
- 无进程管理

#### 3.4.2 增强方案

**扩展参数**:
```json
{
  "command": "string (required) - 要执行的命令",
  "timeoutMs": "integer (optional) - 超时时间（毫秒），默认 30000，0 表示无限等待",
  "background": "boolean (optional) - 是否后台执行，默认 false",
  "workingDir": "string (optional) - 工作目录"
}
```

**返回值（同步执行）**:
```json
{
  "success": true,
  "stdout": "命令标准输出",
  "stderr": "命令标准错误输出",
  "exitCode": 0,
  "pid": 12345
}
```

**返回值（后台执行）**:
```json
{
  "success": true,
  "message": "Command started in background",
  "pid": 12345
}
```

#### 3.4.3 实现要点

**超时控制**:
- Windows: 使用 `WaitForSingleObject` with timeout
- Linux: 使用 `waitpid` with `WNOHANG` in loop

**后台执行**:
- 创建进程后立即返回 PID
- 进程管理由 `process` 工具负责

**错误处理**:
- `TIMEOUT`: 命令执行超时
- `COMMAND_NOT_FOUND`: 命令不存在
- `PERMISSION_DENIED`: 权限不足

---

### 3.5 process — 进程管理工具

#### 3.5.1 工具定义

**工具名称**: `process`  
**类别**: Runtime / Local  
**描述**: Manage running processes (list, kill, signal).

**参数**:
```json
{
  "action": "string (required) - 操作类型：list, kill, signal",
  "pid": "integer (optional) - 进程 ID（kill/signal 时必需）",
  "signal": "string (optional) - 信号类型（signal 时必需）：SIGTERM, SIGKILL",
  "filter": "string (optional) - 进程名过滤（list 时可用）"
}
```

**返回值（list）**:
```json
{
  "success": true,
  "processes": [
    {
      "pid": 12345,
      "name": "python",
      "cmdline": "python -m http.server",
      "cpu": 5.2,
      "memory": "1024K"
    }
  ]
}
```

#### 3.5.2 实现要点

**进程列表**:
- Windows: 使用 `EnumProcesses` + `GetModuleBaseName`
- Linux: 读取 `/proc` 文件系统

**信号发送**:
- Windows: 使用 `TerminateProcess` (SIGKILL) 或发送 WM_CLOSE (SIGTERM)
- Linux: 使用 `kill()` 系统调用

---

### 3.6 image — 图像理解工具

#### 3.6.1 工具定义

**工具名称**: `image`  
**类别**: Media / Local  
**描述**: Analyze images using vision-capable LLM models.

**参数**:
```json
{
  "prompt": "string (required) - 分析提示词",
  "image": "string (optional) - 单张图片：文件路径或 URL 或 data URL",
  "images": "array (optional) - 多张图片：最多 20 张",
  "model": "string (optional) - 指定模型，默认使用配置的视觉模型",
  "maxImages": "integer (optional) - 最大图片数量，默认 20"
}
```

**返回值**:
```json
{
  "success": true,
  "result": "图像分析结果（文本）",
  "model": "glm-4v",
  "tokens": 1024
}
```

#### 3.6.2 实现要点

**Phase 1 (P0)**:
- 支持单图分析（`image` 参数）
- 集成至少一个视觉模型（推荐 GLM-4V 或 GPT-4V）
- 支持文件路径和 URL 输入

**Phase 2 (P1)**:
- 支持多图分析（`images` 参数）
- 自动模型选择和降级

**图片处理**:
- 本地文件：读取并转换为 base64 data URL
- URL：直接传递给 LLM API
- data URL：直接使用（需验证格式）

**错误处理**:
- `IMAGE_NOT_FOUND`: 图片文件不存在
- `UNSUPPORTED_FORMAT`: 不支持的图片格式
- `MODEL_NOT_AVAILABLE`: 视觉模型不可用

#### 3.6.3 与 screen.capture 配合

典型工作流：
1. Agent 调用 `screen.capture` 获取截图
2. Agent 将截图 base64 传递给 `image` 工具
3. Agent 获取分析结果并返回给用户

---

### 3.7 Skill 系统 — Agent 自进化能力

#### 3.7.1 当前实现状态

**已有组件**:
- `server/src/skills/skill_manager.cpp` — Skill 管理器
- `server/include/hiclaw/skills/skill_manager.hpp` — 头文件
- `skill.read` 工具 — 加载 skill 指令

**Skill 格式**:
```markdown
---
name: Node.js Deployment
description: Deploy Node.js applications to production
---

You are an expert in Node.js deployment. When the user asks to deploy:
1. Check if package.json exists
2. Run npm install
3. Build with npm run build
4. Start with pm2 start npm --name "app" -- start
```

#### 3.7.2 增强需求

**工具扩展**:

1. **skill.list** — 列出可用技能
   ```json
   {
     "success": true,
     "skills": [
       {"id": "nodejs-deploy", "name": "Node.js Deployment", "enabled": true},
       {"id": "docker-setup", "name": "Docker Setup", "enabled": false}
     ]
   }
   ```

2. **skill.install** — 安装新技能（从内容）
   - 已有 `install_from_content()` 方法
   - 需要暴露为工具

3. **skill.enable / skill.disable** — 启用/禁用技能
   - 已有方法实现
   - 需要暴露为工具

#### 3.7.3 Skill 发现机制

**系统提示注入**:
- `build_skill_index_prompt()` 已实现
- 在 agent.cpp 中通过 `get_skill_index()` 注入到系统提示

**Agent 工作流**:
1. 系统提示包含 "Available Skills" 列表
2. 用户请求匹配某个 skill
3. Agent 调用 `skill.read` 加载完整指令
4. Agent 按照指令执行任务

---

### 3.8 文件编辑工具 (edit, apply_patch)

#### 3.8.1 edit — 精确文本编辑

**工具名称**: `edit`  
**类别**: Files / Local  
**描述**: Edit a file by replacing exact text.

**参数**:
```json
{
  "path": "string (required) - 文件路径",
  "oldText": "string (required) - 要替换的原文",
  "newText": "string (required) - 替换后的文本"
}
```

**返回值**:
```json
{
  "success": true,
  "message": "Replaced 1 occurrence",
  "path": "/path/to/file"
}
```

**实现要点**:
- 读取文件内容
- 查找 `oldText` 的所有出现
- 替换为 `newText`
- 写回文件
- 如果 `oldText` 不存在，返回错误

**错误处理**:
- `OLDTEXT_NOT_FOUND`: 未找到要替换的文本
- `MULTIPLE_MATCHES`: 多处匹配（需要确认）

#### 3.8.2 apply_patch — 应用补丁

**工具名称**: `apply_patch`  
**类别**: Files / Local  
**描述**: Apply a unified diff patch to a file.

**参数**:
```json
{
  "path": "string (required) - 文件路径",
  "patch": "string (required) - unified diff 格式补丁"
}
```

**返回值**:
```json
{
  "success": true,
  "message": "Patch applied successfully",
  "path": "/path/to/file"
}
```

**实现要点**:
- 解析 unified diff 格式
- 应用补丁到文件
- 处理冲突和失败情况

**错误处理**:
- `PATCH_PARSE_FAILED`: 补丁格式错误
- `PATCH_APPLY_FAILED`: 补丁应用失败
- `CONFLICT`: 补丁冲突

---

### 3.9 会话管理工具 (sessions_*)

#### 3.9.1 sessions_list

**工具名称**: `sessions_list`  
**类别**: Sessions / Local  
**描述**: List all agent sessions.

**参数**: 无

**返回值**:
```json
{
  "success": true,
  "sessions": [
    {
      "key": "main",
      "displayName": "Main",
      "createdAt": 1716192000000,
      "updatedAt": 1716192000000,
      "messageCount": 42
    }
  ]
}
```

#### 3.9.2 sessions_history

**工具名称**: `sessions_history`  
**类别**: Sessions / Local  
**描述**: Get message history for a session.

**参数**:
```json
{
  "sessionKey": "string (optional) - 会话 key，默认为当前会话",
  "limit": "integer (optional) - 返回消息数量，默认 50"
}
```

**返回值**:
```json
{
  "success": true,
  "messages": [
    {
      "role": "user",
      "content": "用户消息",
      "timestamp": 1716192000000
    },
    {
      "role": "assistant",
      "content": "助手回复",
      "timestamp": 1716192000000,
      "toolCalls": [...]
    }
  ]
}
```

#### 3.9.3 sessions_send

**工具名称**: `sessions_send`  
**类别**: Sessions / Local  
**描述**: Send a message to another session.

**参数**:
```json
{
  "sessionKey": "string (required) - 目标会话 key",
  "message": "string (required) - 要发送的消息",
  "timeoutSeconds": "integer (optional) - 等待响应超时，默认 30"
}
```

**返回值**:
```json
{
  "success": true,
  "response": "会话响应"
}
```

**实现要点**:
- 复用 `session/store.cpp` 中的现有实现
- 暴露为工具供 Agent 调用
- 支持跨会话消息传递

---

### 3.10 定时任务工具 (cron)

#### 3.10.1 工具定义

**工具名称**: `cron`  
**类别**: Automation / Local  
**描述**: Manage scheduled tasks using cron expressions.

**参数**:
```json
{
  "action": "string (required) - 操作类型：status, list, add, update, remove, run",
  "job": "string (optional) - 任务内容（add/update 时必需）",
  "schedule": "string (optional) - cron 表达式（add/update 时必需）",
  "id": "string (optional) - 任务 ID（update/remove/run 时必需）"
}
```

**返回值（list）**:
```json
{
  "success": true,
  "jobs": [
    {
      "id": "daily-reminder",
      "schedule": "0 9 * * *",
      "job": "提醒用户喝水",
      "nextRun": "2025-05-21T09:00:00Z",
      "enabled": true
    }
  ]
}
```

#### 3.10.2 实现要点

**复用现有代码**:
- `server/src/cron/` 已有 cron 表达式解析器
- `cron::store` 已有任务存储
- 需要暴露为工具接口

**cron 表达式格式**:
```
分钟 小时 日期 月份 星期
*    *    *    *    *
```

支持语法:
- `*` — 任意值
- `N` — 具体值
- `N-M` — 范围
- `*/M` — 步长（如 `*/5` 每 5 分钟）

**错误处理**:
- `INVALID_CRON_EXPR`: cron 表达式格式错误
- `JOB_NOT_FOUND`: 任务不存在
- `JOB_EXISTS`: 任务已存在

---

## 4. 非功能需求

### 4.1 性能

- **工具响应时间**: 本地工具 < 1s，远程工具 < 5s
- **并发支持**: 支持多个工具并发执行
- **资源限制**: 单个工具最多占用 512MB 内存

### 4.2 安全

- **路径保护**: `file_read` / `file_write` / `edit` 使用 `path_guard` 防止路径遍历
- **命令注入防护**: `shell` 工具需要过滤危险命令
- **API 密钥管理**: 所有第三方 API 密钥通过配置文件管理，不硬编码

### 4.3 错误处理

- **统一错误码**: 定义清晰的错误码和错误消息
- **错误传播**: 工具错误需要正确传播到 Agent 和用户
- **重试机制**: 网络相关工具（`web_search`, `web_fetch`）支持自动重试

### 4.4 可观测性

- **日志记录**: 所有工具调用需要记录日志
- **指标收集**: 记录工具调用次数、成功率、延迟
- **调试支持**: 提供工具调用追踪功能

---

## 5. 优先级和里程碑

### Phase 1: 核心能力补齐 (P0)

**目标**: 让 Agent 能够完成基本任务

**功能列表**:
1. `screen.capture` — Desktop 客户端实现截屏处理
2. `web_search` — 实现 Web 搜索工具
3. `image` — 实现图像理解工具
4. `shell` 增强 — 添加超时控制和后台执行
5. `process` — 实现进程管理工具

**验收标准**:
- 用户可以要求 Agent "帮我截屏并分析当前屏幕"
- 用户可以要求 Agent "搜索今天的北京天气"
- Agent 可以执行长时间运行的命令而不阻塞

### Phase 2: 重要功能增强 (P1)

**目标**: 让 Agent 能够处理复杂场景

**功能列表**:
1. `sessions_list` / `sessions_history` / `sessions_send` — 会话管理
2. `browser` — 浏览器控制（复用 Desktop CDP 代码）
3. `message` — 消息发送工具（集成 WeChat 适配器）
4. `edit` / `apply_patch` — 文件编辑增强
5. Skill 系统完善 — `skill.list`, `skill.install`, `skill.enable/disable`

**验收标准**:
- Agent 可以列出和查询历史会话
- Agent 可以自动化 Web 操作（如登录网站）
- Agent 可以通过 WeChat 发送消息
- Agent 可以精确编辑文件（而非整体重写）

### Phase 3: 高级功能 (P2)

**目标**: 让 Agent 具备高级自动化能力

**功能列表**:
1. `cron` — 定时任务工具
2. `image_generate` — 图像生成工具
3. `tts` — 服务端 TTS 工具
4. `code_execution` — 远程代码执行

**验收标准**:
- Agent 可以创建定时任务（如"每天早上 9 点提醒我"）
- Agent 可以生成图像
- Agent 可以执行代码并返回结果

---

## 6. 验收标准

### 6.1 功能验收

每个功能需要通过以下验收测试：

| 功能 | 测试用例 | 预期结果 |
|------|----------|----------|
| `screen.capture` | 用户要求截屏 | 返回 base64 编码的截图 |
| `web_search` | 用户搜索"今天天气" | 返回相关搜索结果 |
| `image` | 用户要求分析截图 | 返回图像内容描述 |
| `shell` (后台) | 后台运行 npm run dev | 立即返回 PID，不阻塞 |
| `process` (list) | 列出所有 Python 进程 | 返回进程列表 |
| `sessions_list` | 列出所有会话 | 返回会话元数据列表 |
| `edit` | 替换文件中的文本 | 文件内容正确更新 |
| `cron` (add) | 添加定时任务 | 任务被正确调度 |

### 6.2 集成验收

**端到端测试**:
1. 启动 HiClaw 服务器
2. 连接 Desktop 客户端
3. 发送复杂任务（如"截屏分析、然后搜索相关信息、最后发送到 WeChat"）
4. 验证 Agent 能够正确调用工具链完成任务

### 6.3 性能验收

- 本地工具响应时间 < 1s (95th percentile)
- 远程工具响应时间 < 5s (95th percentile)
- 内存占用稳定，无泄漏

### 6.4 安全验收

- 路径遍历攻击被阻止
- 命令注入攻击被阻止
- API 密钥不在日志中泄露

---

## 7. 实施建议

### 7.1 架构考虑

1. **工具注册扩展**: 扩展 `register_tool` 以支持工具元数据
2. **工具分类**: 按类别组织工具，便于发现和管理
3. **工具发现**: 实现 `tools.list` 工具
4. **错误处理**: 统一错误码和错误消息格式

### 7.2 复用现有代码

1. **Desktop 端代码**: `win32_screen_capture.dart` 已实现截屏
2. **Cron 系统**: 现有 `cron/` 模块可直接暴露为工具
3. **Session 系统**: 现有 `session/store.cpp` 可直接暴露为工具
4. **WeChat 适配器**: 可包装为 `message` 工具

### 7.3 测试策略

1. **单元测试**: 每个新工具都需要单元测试
2. **集成测试**: 验证工具与 Agent 的交互
3. **安全测试**: 路径保护、命令注入防护
4. **性能测试**: 工具响应时间和资源占用

---

## 8. 风险与依赖

### 8.1 风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 第三方 API 不稳定 | web_search 可能失败 | 实现多个提供商，自动降级 |
| 视觉模型成本高 | image 工具使用成本高 | 添加缓存，限制使用频率 |
| 跨平台兼容性 | Desktop 客户端平台差异 | 抽象平台接口，分平台实现 |

### 8.2 依赖

- **搜索 API**: 需要申请 Brave Search 或 Sogou API 密钥
- **视觉模型**: 需要配置 GLM-4V 或 GPT-4V API
- **浏览器控制**: Desktop 端 CDP 代码需要完善

---

## 9. 参考资料

- **Gap 分析**: `docs/design/rr/20260520-hiclaw-capability-gap-analysis.md`
- **OpenClaw 参考**: `reference/openclaw/`
- **HiClaw 架构**: `CLAUDE.md`
- **工具定义**: `server/src/tools/tool.cpp`
- **Skill 系统**: `server/src/skills/skill_manager.cpp`

---

**文档结束**
