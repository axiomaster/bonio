# HiClaw 能力对标分析：HiClaw vs OpenClaw

## 1. 现状概览

**HiClaw** 是用 C++17 重写的 OpenClaw 服务器核心，负责 WebSocket 网关、LLM 调用路由、工具调用执行等核心功能。当前实现聚焦于基础能力，提供了基本的本地工具执行和远程工具路由框架。

**OpenClaw** 是成熟的 Node.js TypeScript 实现，提供了丰富的工具生态，包括文件操作、shell 执行、Web 搜索、会话管理、消息发送、图像处理、媒体生成、定时任务等完整能力。

## 2. HiClaw 现有能力清单

| Tool Name | Category | Local/Remote | Parameters | Description |
|-----------|----------|--------------|------------|-------------|
| shell | Runtime | Local | command (string) | Run shell commands via popen/fork+exec |
| file_read | Files | Local | path (string) | Read file contents with path guard |
| file_write | Files | Local | path (string), content (string) | Write content to file |
| web_fetch | Web | Local | url (string) | Fetch URL content via HTTP GET |
| memory_store | Memory | Local | key (string), content (string), category (string) | Store facts in file-based memory |
| memory_recall | Memory | Local | query (string), limit (int) | Search memory by query |
| memory_forget | Memory | Local | key (string) | Remove memory by key |
| skill.read | Skills | Local | name (string) | Load skill instructions |
| memo.save | Memos | Local | title (string), content (string), source (string) | Save memo/note |
| memo.list | Memos | Local | limit (int) | List saved memos |
| screen.capture | UI | Remote | - | Capture screenshot (routed to node) |
| camera.snap | Media | Remote | camera (front/back) | Take photo (routed to node) |
| location.get | Location | Remote | - | Get GPS location (routed to node) |
| notifications.list | Notifications | Remote | - | List notifications (routed to node) |
| device.info | Device | Remote | - | Get device info (routed to node) |
| contacts.search | Contacts | Remote | query (string) | Search contacts (routed to node) |
| calendar.events | Calendar | Remote | days (int) | List calendar events (routed to node) |
| system.notify | System | Remote | title (string), body (string) | Send notification (routed to node) |
| input.type | Input | Remote | text (string), animate (bool), charDelayMs (int) | Type text into focused input field |
| input.find | Input | Remote | - | Find focused input field |

**本地工具总数**: 9  
**远程工具总数**: 10  
**总计**: 19

## 3. OpenClaw 能力清单

| Tool Name | Category | Local/Remote | Parameters | Description |
|-----------|----------|--------------|------------|-------------|
| read | Files | Local | path (string) | Read file contents |
| write | Files | Local | path (string), content (string) | Create/overwrite files |
| edit | Files | Local | path (string), oldText, newText | Precise text edits |
| apply_patch | Files | Local | path (string), patch (string) | Apply unified diff patches |
| exec | Runtime | Local | command (string), background, timeoutMs | Execute shell commands with advanced options |
| process | Runtime | Local | action (list/kill/signal), pid, signal | Manage running processes |
| code_execution | Runtime | Local | language (string), code (string) | Run sandboxed remote code analysis |
| web_search | Web | Local | query (string), count, country, language, freshness, date_after, date_before | Search web with multiple providers |
| web_fetch | Web | Local | url (string) | Fetch web content |
| x_search | Web | Local | query (string) | Search X (Twitter) posts |
| memory_search | Memory | Local | query (string), limit | Semantic memory search |
| memory_get | Memory | Local | key (string) | Read memory files |
| sessions_list | Sessions | Local | - | List agent sessions |
| sessions_history | Sessions | Local | sessionKey, limit | Get session history |
| sessions_send | Sessions | Local | sessionKey, message, timeoutSeconds | Send message to session |
| sessions_spawn | Sessions | Local | task, agentId, model, runtime, mode | Spawn sub-agent session |
| sessions_yield | Sessions | Local | - | End turn for sub-agent results |
| subagents | Sessions | Local | action (list/describe/stop), agentId | Manage sub-agents |
| session_status | Sessions | Local | - | Get current session status |
| browser | UI | Local | action (navigate/click/type/wait), url, selector | Control web browser via CDP |
| canvas | UI | Remote | action (show/hide/update), content | Control Canvas surfaces |
| message | Messaging | Local/Remote | action, channel, target, message, presentation | Send/manage channel messages |
| heartbeat_respond | Automation | Local | outcome (success/failure) | Record heartbeat outcomes |
| cron | Automation | Local | action (status/list/add/update/remove/run/runs/wake), job, schedule | Manage cron jobs |
| gateway | Automation | Local | action (control/broadcast/emit) | Gateway control |
| nodes | Nodes | Local | action (status/describe/pending/approve/reject/notify/camera_*/photos_*/screen_record/location_get/notifications_*/device_*/invoke) | Discover/control paired nodes |
| agents_list | Agents | Local | - | List available agents |
| update_plan | Agents | Local | plan (string) | Update execution plan |
| image | Media | Local | prompt, image/images, model, maxImages | Image understanding with vision models |
| image_generate | Media | Local | prompt, size, aspectRatio, quality, count | Image generation |
| music_generate | Media | Local | prompt, duration, style | Music generation |
| video_generate | Media | Local | prompt, duration, aspectRatio | Video generation |
| tts | Media | Local | text, channel | Text-to-speech conversion |

**工具总数**: 30+ (不含 nodes 工具的子操作)

## 4. 能力差距矩阵

| Tool Name | OpenClaw | HiClaw | Gap | Priority |
|-----------|----------|--------|-----|----------|
| **文件操作基础** | read/write | file_read/file_write | ✅ 相当 | - |
| edit | ✅ | ❌ | 缺少精确文本编辑工具 | P1 |
| apply_patch | ✅ | ❌ | 缺少 patch 应用工具 | P1 |
| **Shell 执行** | exec (advanced) | shell (basic) | HiClaw 无后台执行、超时控制、进程管理 | P0 |
| process | ✅ | ❌ | 缺少进程管理工具 | P1 |
| code_execution | ✅ | ❌ | 缺少远程沙箱代码执行 | P2 |
| **Web 能力** | web_search | ❌ | **HiClaw 完全缺失 Web 搜索** | P0 |
| web_fetch | ✅ | ✅ | 相当 | - |
| x_search | ✅ | ❌ | 缺少 X 搜索 | P2 |
| **内存系统** | memory_search/memory_get | memory_recall | HiClaw 实现较简单 | P1 |
| **会话管理** | sessions_*/subagents | ❌ | **HiClaw 完全缺失会话管理系统** | P1 |
| **浏览器控制** | browser | ❌ | **HiClaw 完全缺失 CDP 浏览器控制** | P1 |
| **消息系统** | message | ❌ | **HiClaw 完全缺失消息发送工具** | P1 |
| **定时任务** | cron | ❌ | **HiClaw 完全缺失 cron 工具** | P2 |
| **图像理解** | image | ❌ | **HiClaw 完全缺失图像分析工具** | P0 |
| **图像生成** | image_generate | ❌ | 缺少图像生成工具 | P2 |
| **媒体生成** | music_generate/video_generate | ❌ | 缺少音视频生成工具 | P3 |
| **TTS** | tts | Desktop 端实现 | HiClaw 服务端无 TTS 工具 | P1 |
| **节点管理** | nodes (comprehensive) | 部分 (仅路由) | HiClaw 只有路由框架，无工具封装 | P1 |

**优先级定义**:
- **P0**: 核心能力缺失，阻塞基本 Agent 功能
- **P1**: 重要功能，影响日常使用
- **P2**: 增强功能，提升体验
- **P3**: 锦上添花的功能

## 5. 关键差距分析

### P0-1: Shell 执行增强 (exec)

**OpenClaw 能力**:
- 支持后台执行 (`background: true`)
- 超时控制 (`timeoutMs`)
- 进程管理 (`process` 工具)
- 批准流程集成 (gateway approval)

**HiClaw 现状**:
- 仅实现基本的 `shell` 工具
- 使用 popen/fork+exec 同步执行
- 无后台执行、无超时控制、无进程管理

**影响**: 无法执行长时间运行的任务，无法管理后台进程，安全性较弱

**建议实施**: 
1. 扩展 `shell` 工具参数，添加 `backgroundMs`、`timeoutMs` 选项
2. 实现 `process` 工具，支持 list/kill/signal 操作
3. 集成网关批准流程

### P0-2: Web 搜索 (web_search)

**OpenClaw 能力**:
- 多提供商支持 (Brave, Perplexity, etc.)
- 高级参数: count, country, language, freshness, date range
- 缓存机制

**HiClaw 现状**:
- 完全缺失 Web 搜索能力
- 仅有 `web_fetch` 可获取单个 URL

**影响**: Agent 无法获取实时信息，无法回答时事问题

**建议实施**:
1. 实现 `web_search` 工具，集成至少一个搜索提供商
2. 支持基本参数: query, count (default 10)
3. 考虑添加本地缓存

### P0-3: 图像理解 (image)

**OpenClaw 能力**:
- 多模型支持 (OpenAI, Anthropic, etc.)
- 支持文件路径、URL、data URL
- 多图分析 (images 参数，最多 20 张)
- 自动模型选择和降级

**HiClaw 现状**:
- 完全缺失图像理解能力
- 虽然有 `screen.capture` 获取截图，但无法分析

**影响**: Agent 无法"看到"图像内容，无法处理视觉信息

**建议实施**:
1. 实现 `image` 工具，支持单图和多图分析
2. 集成至少一个视觉模型 (如 GLM-4V)
3. 支持文件路径和 URL 输入

### P1-1: 会话管理系统 (sessions_*)

**OpenClaw 能力**:
- `sessions_list`: 列出所有会话
- `sessions_history`: 获取会话历史
- `sessions_send`: 向其他会话发送消息
- `sessions_spawn`: 创建子 Agent 会话
- `sessions_yield`: 等待子 Agent 结果
- `subagents`: 管理子 Agent

**HiClaw 现状**:
- 完全缺失会话管理工具
- 仅有基础的会话持久化 (`session/store.cpp`)

**影响**: 无法实现多 Agent 协作，无法管理长期会话

**建议实施**:
1. 实现会话列表和历史查询工具
2. 实现会话间消息发送
3. 考虑子 Agent 生成机制 (可延后)

### P1-2: 浏览器控制 (browser)

**OpenClaw 能力**:
- 基于 Chrome DevTools Protocol (CDP)
- 操作: navigate, click, type, wait, screenshot
- 支持复杂交互流程

**HiClaw 现状**:
- 完全缺失浏览器控制能力
- Desktop 端有 CDP 代码但未暴露为工具

**影响**: 无法自动化 Web 操作，无法与动态网页交互

**建议实施**:
1. 将 Desktop 端 CDP 代码抽象为通用工具
2. 实现基础操作: navigate, click, type
3. 暴露为 `browser` 工具供 Agent 调用

### P1-3: 消息系统 (message)

**OpenClaw 能力**:
- 多渠道支持: Discord, Slack, Telegram, WeChat, etc.
- 丰富操作: send, delete, react, poll, pin, threads
- 富文本: presentation (blocks, buttons, selects)

**HiClaw 现状**:
- 完全缺失消息工具
- 有 WeChat 适配器但未暴露为工具

**影响**: Agent 无法主动发送消息到外部渠道

**建议实施**:
1. 实现 `message` 工具，支持基本发送功能
2. 集成现有 WeChat 适配器
3. 逐步添加更多渠道支持

### P1-4: 文件编辑增强 (edit, apply_patch)

**OpenClaw 能力**:
- `edit`: 精确文本替换 (oldText → newText)
- `apply_patch`: 应用 unified diff 格式补丁

**HiClaw 现状**:
- 仅有 `file_write` 整体写入
- 无精确编辑能力

**影响**: 修改文件时需要重写整个内容，效率低且容易出错

**建议实施**:
1. 实现 `edit` 工具，支持字符串替换
2. 实现 `apply_patch` 工具，支持 diff 补丁

### P2-1: 定时任务 (cron)

**OpenClaw 能力**:
- 完整的 cron 表达式支持
- 操作: status, list, add, update, remove, run, runs, wake
- 支持一次性任务和周期任务
- 多种 sessionTarget: main, isolated, current

**HiClaw 现状**:
- 有 cron 表达式解析器和存储 (`cron/`)
- 但未暴露为工具给 Agent 使用

**影响**: Agent 无法创建定时任务，无法实现"稍后提醒"功能

**建议实施**:
1. 将现有 cron 系统暴露为工具
2. 支持基本的 add/list/remove 操作

### P2-2: 进程管理 (process)

**OpenClaw 能力**:
- 操作: list, kill, signal
- 支持进程查询和管理

**HiClaw 现状**:
- 完全缺失

**影响**: 无法管理后台启动的进程

**建议实施**:
1. 实现 `process` 工具
2. 支持基本操作: list, kill

### P2-3: 图像生成 (image_generate)

**OpenClaw 能力**:
- 多提供商支持
- 参数: prompt, size, aspectRatio, quality, count
- 支持参考图编辑

**HiClaw 现状**:
- 完全缺失

**影响**: Agent 无法生成图像内容

**建议实施**: 
1. 实现 `image_generate` 工具
2. 集成至少一个图像生成 API

### P3: 媒体生成 (music_generate, video_generate)

**OpenClaw 能力**:
- 音乐生成: prompt, duration, style
- 视频生成: prompt, duration, aspectRatio

**HiClaw 现状**:
- 完全缺失

**影响**: 无法生成音频和视频内容

**建议实施**: 低优先级，可延后实现

## 6. 建议实施优先级

### Phase 1: 核心能力补齐 (P0)
1. **web_search** - 实现基础 Web 搜索
2. **image** - 实现图像理解工具
3. **shell 增强和 process** - 添加后台执行、超时控制、进程管理

### Phase 2: 重要功能增强 (P1)
4. **sessions_*** - 实现会话管理工具 (list/history/send)
5. **browser** - 暴露现有 CDP 代码为工具
6. **message** - 实现消息发送工具
7. **edit / apply_patch** - 实现文件编辑增强

### Phase 3: 高级功能 (P2)
8. **cron** - 暴露现有 cron 系统为工具
9. **image_generate** - 实现图像生成
10. **tts** - 服务端 TTS 工具

### Phase 4: 增强功能 (P3)
11. **music_generate / video_generate** - 媒体生成
12. **code_execution** - 远程代码执行
13. **x_search** - X 搜索

## 7. 实施建议

### 架构考虑
1. **工具注册扩展**: 当前的 `register_tool` 机制需要支持更复杂的工具定义
2. **工具分类**: 建议按类别组织工具 (files, runtime, web, memory, sessions, media, etc.)
3. **工具发现**: 实现工具能力发现机制，让 Agent 知道哪些工具可用
4. **错误处理**: 统一工具错误处理和结果返回格式

### 复用现有代码
1. **Desktop 端代码**: browser control (CDP) 代码可复用
2. **Cron 系统**: 现有 cron 解析器和存储可直接暴露
3. **WeChat 适配器**: 可包装为消息工具

### 测试策略
1. 每个新工具都需要单元测试
2. 集成测试验证工具与 Agent 的交互
3. 安全测试: 路径保护、命令注入防护

---

**文档信息**
- 创建日期: 2025-05-20
- 作者: Planner (hiclaw-capability team)
- 基于: HiClaw server/ 和 OpenClaw reference/openclaw/ 代码分析
