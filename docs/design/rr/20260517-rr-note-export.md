# 产品需求文档 (PRD)：Bonio 笔记导出与同步 (Note Export & Sync)

**文档版本:** V2.0
**状态:** 设计与调研中
**日期:** 2026-05-17

## 1. 背景与目标
Bonio 已经具备了“记一记”（Memory）和“阅读搭子”等核心伴随功能，能够高效地捕捉屏幕截图、文本片段并由 AI 提取结构化摘要。然而，长期的知识管理（PKM, Personal Knowledge Management）和深度编辑通常需要用户依赖自己习惯的专业笔记软件（如 Obsidian, Logseq, Notion 等）。

Bonio 的定位是“智能伴随与捕捉入口”，而非“重度笔记编辑器”。因此，我们的目标是：**将 Bonio 作为知识收集的“触角”，并将捕获且经过 AI 结构化的知识，无缝、极简地流转到用户的主力笔记应用中。** 本期规划将优先聚焦于**本地笔记应用**（如 Obsidian）的导出与流转。

---

## 2. 竞品调研与分析

为了设计出最符合用户习惯的同步方案，我们调研了市面上几款知名的碎片化记录与网页剪藏工具。

### 2.1 usememos/memos
*   **产品形态**：一个开源的、轻量级的自托管备忘录中心（类似单机版 Twitter/Flomo）。
*   **同步机制（Pull 模式）**：Memos 将所有数据存储在自己的 SQLite 数据库中，并对外暴露 RESTful API。它自身并不主动推送到其他应用。
*   **与 Obsidian 联动方式**：生态社区开发了 `Obsidian Memos Sync` 等插件。用户需要在 Obsidian 中安装插件，配置 Memos 的 API Key 和 Server URL，由 Obsidian 插件定时去“拉取 (Pull)”数据并在 Obsidian 中生成 Daily Notes。
*   **优缺点**：
    *   *优点*：Memos 作为 Server 保持轻量，API 扩展性强。
    *   *缺点*：需要用户在目标笔记软件中折腾安装插件，学习成本高，依赖社区生态的维护。

### 2.2 SimpRead 同步助手 (简悦 SyncHelper)
*   **产品形态**：简悦是一款网页阅读与标注浏览器扩展，而“同步助手”是配合它使用的本地桌面端程序。
*   **同步机制（Push 模式）**：由于浏览器扩展的沙盒限制无法直接操作系统文件，同步助手作为一个本地常驻服务，接收扩展的指令，**直接在本地磁盘生成 Markdown、HTML 或 PDF 文件**。
*   **与 Obsidian 联动方式**：用户在同步助手配置一个“本地导出路径”（直接指向 Obsidian Vault 里的某个文件夹）。简悦产生的标注会由同步助手自动写成 `.md` 文件并连同图片资源一起存入该目录。Obsidian 自身会实时监测到本地文件的变化并完成双向链接。
*   **优缺点**：
    *   *优点*：极度符合极客和本地化用户的需求。无需在目标笔记安装任何插件，直接利用底层文件系统的互通性（File-system as API），不仅支持 Obsidian，还天然支持 Logseq 等任何基于本地 Markdown 的工具。
    *   *缺点*：必须有一个本地客户端运行（Bonio 本身就是本地客户端，因此完美规避了这一缺点）。

### 2.3 obsidian-import 相关脚本工具
*   **产品形态**：各种零散的开源 Python/Node.js 脚本或第三方小工具。
*   **同步机制（手动转换）**：通常要求用户先从源应用（如 Evernote, Roam）导出一个专有格式的压缩包，然后运行命令行工具，将其转换为 Obsidian 兼容的 Markdown 文件及双链语法。
*   **优缺点**：
    *   *优点*：一次性迁移能力强。
    *   *缺点*：不是一个高频、伴随式的流转方案，不适合“记一条、同步一条”的日常场景。

---

## 3. Bonio 的功能实现方案 (Focus on Local)

通过竞品分析，我们可以得出结论：**鉴于 Bonio 已经是一个强大的本地桌面端应用（Flutter Desktop App），我们完全拥有读写本地文件系统的最高权限。因此，Bonio 应采取类似“简悦同步助手”的【本地直接推送 (Push) 模式】。** 

这不仅开发成本最低、稳定性最高，而且用户体验最无感——不需要用户在 Obsidian 侧去寻找和安装所谓的 "Bonio 插件"。

### 3.1 核心功能特性

1.  **纯本地文件互操作 (File-System Integration)**
    *   通过让用户在 Bonio 设置中选择一个本地路径（即用户的 Obsidian Vault 路径或 Logseq Graph 路径），Bonio 直接将记录转化为 Markdown 文件写入该目录。
2.  **资源本地化兜底**
    *   Bonio 在“记一记”时截取的图片，不能仅仅以 Bonio 内部缓存的形式存在。在同步时，Bonio 必须自动将图片复制到目标笔记的附件目录（如 `Vault/BoJi-Inbox/assets/`），并把 Markdown 中的图片语法转换为 Obsidian 友好的 `![[image.png]]` 或相对路径 `![](assets/image.png)`。
3.  **极简的交互 (One-Click Export)**
    *   在 Bonio 的 Memory 卡片 UI 上，提供一个显眼的【导出到 Obsidian】按钮。点击后秒级完成，不需要中间转换过程。
4.  **提供通用 ZIP 导出作为补充**
    *   对于不使用 Obsidian 等本地知识库软件的用户，支持一键将当前卡片的文本与图片打包为 `.zip` 下载到本地，方便其后续手动导入到其他云端笔记。

### 3.2 交互流程设计

*   **步骤一：全局配置 (Settings)**
    *   新增【笔记同步】配置卡片。
    *   提供选项：**目标应用**（下拉选择：无 / Obsidian / 本地 ZIP 归档）。
    *   当选择 `Obsidian` 时，显示路径选择器，让用户使用系统的文件夹选择对话框 (FilePicker) 定位到自己的 `Obsidian Vault` 根目录。
    *   允许用户设定一个特定的子目录名称（默认：`BoJi-Inbox`），Bonio 同步的内容将统一归档在此目录下，避免弄乱用户的根目录。
*   **步骤二：捕获与触发 (Capture & Trigger)**
    *   用户通过快捷键呼出 Bonio 进行截屏、提问或记录。AI 完成分析并生成 Summary 和 Tags。
    *   在主界面的 Memory 卡片中，展示一个 `Sync` 按钮。
*   **步骤三：执行与反馈 (Execute & Feedback)**
    *   用户点击 `Sync` 按钮。
    *   Bonio 在后台将 Markdown 内容及关联的图片（重命名防冲突）写入配置的 `BoJi-Inbox`。
    *   界面弹出 Toast 提示：“同步成功”。并在 Toast 侧边提供一个按钮 `在 Obsidian 中打开`。
    *   利用系统的 URL Scheme（`obsidian://open?vault=VaultName&file=BoJi-Inbox/xxx.md`），用户点击后直接唤起并跳转到刚生成的 Obsidian 笔记。

### 3.3 数据模型定义要求

*   在现有的 `BonioNote` 数据模型中增加一个状态字段，比如 `syncHistory`，用于标记某条记录是否已经被导出过，防止重复点击生成多份文件（如果重复点击，可以覆盖原文件而不是新建）。
*   在生成 Markdown 时，自动将 Bonio AI 提炼的 `Tags` 转为 Obsidian 支持的 YAML Frontmatter 或底部 `#tag` 格式。

---

## 4. 为什么裁剪云端功能 (Notion API 等)？

根据您的反馈“优先聚焦本地功能”，我们在本期 PRD 中彻底移除了 Notion 等云端同步的规划。原因如下：
1. **开发成本与不确定性**：云端 API（尤其是 Notion Block API）极为复杂，无法直接将 Markdown 字符串扔过去，需要做繁重的 AST（抽象语法树）解析和 Block 转换。
2. **图片托管限制**：本地拦截的截图若要推送到 Notion，需要先经过图床上传或转换，这带来了额外的隐私风险和稳定性问题。
3. **定位契合度**：Bonio 主打桌面伴随与隐私安全，其产生的 AI 内容和截图大多是本地私密的上下文，优先推送到纯本地的 Obsidian 更符合产品的价值观。
