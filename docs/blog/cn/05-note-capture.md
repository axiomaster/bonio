# 记一记：碎片化信息的一键收集

> 看到任何想"记住"的东西，右键一点，或者直接拖给 Bonio——它帮你截图、分析、打标签、写摘要，然后存入一个随时可搜索的知识库。

---

## 痛点：信息捕获的门槛

信息爆炸的时代，我们每天在电脑上看到无数"值得记下来"的内容——一篇技术文章的关键段落、一个电商页面的商品信息、一段聊天中的地址或电话。但传统的"记笔记"流程太慢了：

1. 选中内容 → 复制
2. 打开笔记应用（可能还要等它启动）
3. 新建笔记 → 粘贴
4. 手动输入标题、打标签
5. 保存

这个流程足以让大多数碎片信息在"算了太麻烦"的心态中流失。"记一记"把这个流程压缩到了**一次右键点击**。

---

## 交互一：右键智能截屏记

用户在任意窗口，右键 Avatar，选择菜单首项的"记一记"：

1. Bonio 截取当前锚定窗口的完整内容（Win32 `PrintWindow` API + `PW_RENDERFULLCONTENT` 标志）
2. Avatar 播放 `happy` 动画，气泡显示"正在记录..."
3. 截图以 PNG 格式保存到 `~/.bonio/boji-notes/attachments/`
4. 自动生成 200px 宽缩略图到 `thumbnails/`
5. 后台通过 **独立的 LLM 会话**（`boji-notes` session）进行多模态分析
6. AI 返回结构化结果：`{"tags": ["#技术文档", "#架构"], "summary": "关于微服务架构的设计文档..."}`
7. Avatar 气泡更新："已存入 [#技术文档, #架构] 喵！"

整个过程不到 3 秒。用户不需要离开当前应用、不需要打字、不需要思考该打什么标签。**AI 帮你完成了所有组织和索引工作。**

### 截图的技术细节

```cpp
// Win32 截图实现（简化）
HWND hwnd = anchoredWindowHandle;
HDC hdcWindow = GetDC(hwnd);
HDC hdcMem = CreateCompatibleDC(hdcWindow);
RECT rect;
GetWindowRect(hwnd, &rect);
int width = rect.right - rect.left;
int height = rect.bottom - rect.top;

HBITMAP hBitmap = CreateCompatibleBitmap(hdcWindow, width, height);
SelectObject(hdcMem, hBitmap);

// PW_RENDERFULLCONTENT — 即使窗口被部分遮挡也能正确截取
PrintWindow(hwnd, hdcMem, PW_RENDERFULLCONTENT);

// 提取 BGRA 像素 → PNG 编码 → 写入文件
```

`PrintWindow` 直接向窗口的渲染表面请求内容，跨显示器、部分遮挡都能正确捕获——比 `BitBlt` 从屏幕缓冲区拷贝要可靠得多。

---

## 交互二：拖拽"投喂"记

比右键更自然的交互：**直接把东西拖到 Avatar 身上。**

Bonio 的 Avatar 窗口实现了 Win32 `IDropTarget` COM 接口，能接收三种拖拽格式：

| 拖拽来源 | 数据格式 | 处理方式 |
|---------|---------|---------|
| 文件管理器 | `CF_HDROP`（文件路径列表） | 复制文件到 attachments/，生成缩略图，AI 分析 |
| 文本选中 | `CF_UNICODETEXT` | 保存为纯文本笔记，AI 分析打标签 |
| 剪贴板/应用 | `CF_DIB`（位图） | 保存为 PNG，生成缩略图，AI 分析 |

拖拽过程中的**动画反馈**精心模拟了"喂食"的拟人化体验：

```
感应期 (DragEnter/DragOver)
  → Avatar 嘴巴张大，身体前倾（openmouth 动画）

吸入期 (Drop)
  → 闭嘴咀嚼 2 秒（eating 动画）

消化期 (保存完成)
  → 满足表情，摸摸肚子 1 秒（satisfied 动画）
  → 气泡显示："已消化 [#tags] 喵！"

拒食期 (格式不支持/文件过大)
  → 皱眉、推手（refuse 动画）
  → 气泡显示："这个我还消化不了..."
```

这种交互设计的精妙之处在于：**你不需要"学会"怎么用。** 在桌面操作系统上拖文件已经做了二十年，这是最本能的操作。Bonio 只是在这个本能操作的下游接上了 AI 理解能力。

---

## AI 自动分类与打标

"记一记"背后的 AI 分析使用**独立的 LLM 会话**（session key = `boji-notes`），不与用户的聊天历史混合。这个专用会话有专门的 system prompt：

```
你是 Bonio Notes 分类助手。分析用户给出的内容，返回严格 JSON 格式：
{
  "tags": ["标签1", "标签2", "标签3"],
  "summary": "一句话内容摘要（不超过50字）"
}

标签要求：
- 3-5 个中文标签，以 # 开头
- 从内容语义中提取，不要凭空编造
- 覆盖主题类别（如 #技术文档、#购物、#美食、#旅行、#健康）
```

标签系统的设计意图：
- **跨会话检索**：用户在聊天中说"帮我找 #购物 的笔记"，AI 能直接按标签过滤
- **UI 过滤**：Memory 管理界面支持按标签筛选
- **聚类发现**：用户可以看到自己的知识分布——"原来我记了这么多 #美食 的东西"

---

## 数据存储

记忆数据以 JSON 文件形式存储在本地：

```
~/.bonio/boji-notes/
├── index.json              # 笔记索引
├── attachments/            # 原始附件（截图、拖拽的文件）
├── thumbnails/             # 缩略图（200px 宽）
└── note_*.json             # 各笔记的详细数据
```

`index.json` 中每条记录的结构：

```json
{
  "id": "note_20260430_143021",
  "title": "Bonio 架构设计文档",
  "tags": ["#技术文档", "#架构", "#AI"],
  "summary": "讨论了 Bonio 的双引擎架构和插件系统设计",
  "sourceApp": "Google Chrome",
  "createdAt": "2026-04-30T14:30:21Z",
  "attachments": ["note_20260430_143021_screenshot.png"]
}
```

选择 JSON 文件而非 SQLite 的理由：零依赖、可直接手动查看和编辑、易于备份和迁移。个人记忆的数据量（通常几千条）在文件系统上完全可控。

---

## 对话式调取

存入记忆只是第一步。真正的价值在于**需要时能找回来**。

用户双击 Avatar，在输入框中自然地问：

- "帮我找上周记的那篇关于 Kubernetes 的文章"
- "我上个月好像记了一个红色背包的，帮我找找"
- "把最近所有 #购物 的笔记列出来"
- "上次开会提到的产品定价是多少？"

Bonio 检索 `boji-notes` 会话上下文中积累的记忆，以卡片形式展示结果。点击卡片可以打开原始截图或文件路径。

---

## 从"记一记"看 Bonio 的设计哲学

"记一记"的交互设计体现了 Bonio 一贯的产品理念：

1. **降低捕获门槛。** 将 5 步操作压缩为 1 步，让用户愿意"随手记"。信息的价值在于被记录，而不是在记忆中流失。
2. **AI 承担组织成本。** 手动打标签是认知负担。AI 天然适合做分类和摘要——这就是 AI 该做的事。
3. **情感化反馈。** "喂食"动画不是无意义的装饰——它让用户感受到"AI 在认真对待你给它的东西"。这种情感连接是用文字界面永远做不到的。

---

## 笔记导出与同步：从捕捉到归档的完整工作流

"记一记"解决了信息捕获的痛点，但长期的知识管理（PKM）通常需要依赖用户习惯的专业笔记应用。Bonio 的定位是"智能伴随与捕捉入口"，而非"重度笔记编辑器"。因此我们提供了**极简的笔记导出与同步功能**，将 Bonio 作为知识收集的"触角"，无缝流转到用户的主力笔记应用中。

### 核心特性

**纯本地文件互操作**：Bonio 直接读写本地文件系统，无需云端中转。用户在设置中配置目标应用的本地路径（如 Obsidian Vault），笔记转化为 Markdown 文件并直接写入目标目录。

**资源本地化兜底**：截图/图片附件自动复制到目标应用的附件目录。Markdown 中的图片语法转换为目标应用友好的格式：
- **Obsidian**：`![[image.png]]`（Wiki Link）
- **ZIP**：标准 Markdown `![](attachments/image.png)`

**元数据完整保留**：AI 生成的标签转换为 YAML Frontmatter，来源 URL、创建时间等元数据完整保留：

```yaml
---
tags:
  - 阅读搭子
  - 技术
source: https://example.com/article
date: 2026-05-17T14:30:00.000Z
---
```

**URL Scheme 深度链接**：导出成功后，可通过 URL Scheme 直接唤起目标应用。Obsidian: `obsidian://open?vault=VaultName&file=BoJi-Inbox/note.md`，用户无需手动导航到目标文件。

**同步状态跟踪**：每条笔记记录 `syncStatus` 字段，记录每次成功导出的目标 ID 和时间戳。笔记卡片上显示同步状态标识（绿色云图标），详情中可查看完整同步历史。

### 交互方式

**单条笔记导出**：Memory 页面 → 笔记卡片 → 详情对话框 → 点击"导出/同步"按钮。导出成功后显示 SnackBar，提供"打开"按钮直接跳转到 Obsidian。

**批量导出**：Memory 页面提供"批量选择"模式，用户可勾选多条笔记后批量导出。显示批量进度（如"正在导出 3/10..."），完成后显示成功/失败统计。

**自动同步**：设置中提供"自动同步"开关。开启后，每条新笔记自动导出到默认目标（仅 Obsidian）。静默失败处理：自动同步失败不阻断用户操作，仅记录日志。

### 配置方式

设置 → "笔记同步" 配置卡片：
- **自动同步**：Switch 开关，开启后新笔记自动导出到 Obsidian
- **默认同步目标**：下拉选择（无、Obsidian 本地、ZIP 归档）
- **Obsidian Vault 路径**：文件夹选择器
- **存放子目录**：默认 `Bonio-Inbox`，可自定义避免弄乱用户 Vault 根目录

**⚠️ Vault 路径配置说明**

Vault 路径必须指向 Obsidian Vault 的**根目录**（即包含 `.obsidian` 隐藏文件夹的那个目录），而不是其他路径。配置错误会导致文件导出成功但 Obsidian 中看不到。

常见错误示例：

```
# ❌ 错误：指向了 .obsidian 配置目录（Obsidian 不会索引此目录的内容）
D:\lism\Documents\obsidian\projects\.obsidian

# ❌ 错误：指向了包含多个 Vault 的父目录
D:\lism\Documents\obsidian

# ✅ 正确：指向包含 .obsidian 的 Vault 根目录
D:\lism\Documents\obsidian\projects
```

如何确认你的 Vault 根目录：
1. 打开 Obsidian → 左下角齿轮（设置）→ 关于 → 查看"Vault 路径"
2. 或在文件管理器中找到包含 `.obsidian` 文件夹的目录

配置正确的 Vault 路径后，导出的笔记会出现在 `{Vault根目录}/{子目录}/` 下，例如：

```
D:\lism\Documents\obsidian\
└── projects\              ← Vault 根目录（选择这个）
    ├── .obsidian\         ← Obsidian 配置（不要选这个）
    ├── Bonio-Inbox\       ← 导出的笔记在这里
    │   ├── attachments\   ← 截图附件
    │   ├── 微信.md
    │   └── 阅读搭子.md
    └── 欢迎.md
```

### 技术实现

导出器接口采用插件化设计：
- `NoteExporter`：抽象接口，定义 `id`、`name` 和 `exportNote()` 方法
- `ObsidianExporter`：实现 Obsidian 本地 Vault 导出，支持 Wiki 链接转换和 URL Scheme
- `ZipExporter`：实现 ZIP 归档导出，标准 Markdown 格式

`NoteExportService` 提供统一导出服务：
- `export()`：单条笔记导出
- `exportBatch()`：批量导出，返回 `BatchExportResult`（成功/失败统计和错误详情）
- `autoSyncNote()`：自动同步单条笔记，静默执行，失败仅记录日志

配置持久化使用 `shared_preferences`：
- Key 命名规范：`note_export_*` 前缀
- 支持的配置项：`auto_sync`、`default_target`、`obsidian_vault`、`obsidian_subfolder`

### 用户体验亮点

**一键流转**：从"记一记"到"归档"只需一次点击。无需复制粘贴，无需手动打标签，AI 已经帮你完成了所有组织工作。

**零学习成本**：无需在目标应用中安装任何插件或配置。生成的 Markdown 文件天然兼容主流本地笔记应用。

**本地优先**：纯本地文件互操作，保护隐私。无需云端中转，不依赖第三方服务。

**冲突处理**：同一条笔记重复导出时生成新文件（不覆盖）。文件名冲突时自动添加后缀 `_1`、`2`...。

**批量友好**：支持多选笔记后一次性导出，显示进度和结果。单条失败不影响其他笔记，完成后列出失败的笔记及原因。

---

*下一篇：[搜同款：一键比价的购物搭子](06-search-similar.md)*
