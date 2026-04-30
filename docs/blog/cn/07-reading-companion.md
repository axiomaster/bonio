# 伴读：把浏览器变成深度学习工具

> 在浏览器里看长文章，Bonio 自动帮你提炼目录、生成摘要、打开笔记编辑器，还把窗口自动调成最适合阅读的 70/30 分屏布局。

---

## 场景：长文阅读的困境

你在浏览器里看到一篇万字长文——可能是技术博客、学术论文、行业报告，或者一篇深度调查。你想认真读，但遇到了几个问题：

1. **文章太长，不知道重点在哪。** 没有目录，段落结构不清
2. **想记笔记，但切来切去很烦。** 浏览器和笔记应用来回切换，打断阅读心流
3. **读完就忘。** 没有结构化地保存关键信息，过两天就只记得"好像看过"

"伴读"就是为解决这三个问题而生的。

---

## 交互流程

**触发条件：** 当前锚定窗口必须是**浏览器**（Chrome、Edge、Firefox 等）。插件清单中的 `menu.requires_context: ["browser_window"]` 确保你只会在浏览器窗口上看到"伴读"选项。

**第一步：右键 → 伴读。** Bonio 开始执行以下操作：

**第二步：提取内容。** 通过 **CDP（Chrome DevTools Protocol）** 连接浏览器：

1. 自动发现本机 Chrome/Edge 的调试端口（`http://localhost:9222`）
2. 通过 `Runtime.evaluate` 在页面中注入内容提取脚本
3. 提取内容：
   - 页面标题
   - 当前 URL
   - 所有标题层级（h1-h6）——作为自动目录
   - 正文内容（自动剔除导航栏、广告、侧边栏）

CDP 连接对于浏览器而言是一个调试器——它拥有对页面的完全读取权限，可以提取 DOM 中的任意内容，可以执行任意 JS。这是 Bonio 桌面自动化的核心能力之一。

**第三步：70/30 分屏。** Bonio 自动调整窗口布局：

```
调整前：
┌────────────────────────────────────┐
│       浏览器（占据全屏）             │
│                                    │
└────────────────────────────────────┘

调整后：
┌──────────────────────────┬─────────┐
│   浏览器（缩至 70%）      │ 伴读窗口 │
│                          │ (30%)   │
│                          │ ┌─────┐ │
│                          │ │目录  │ │
│                          │ │摘要  │ │
│                          │ │笔记  │ │
│                          │ └─────┘ │
└──────────────────────────┴─────────┘
                    ▲
          Avatar 悬浮在伴读窗口顶部
```

分屏算法：
1. 获取浏览器窗口当前 Rect
2. 获取显示器工作区（排除任务栏）
3. 计算：浏览器新宽度 = 工作区宽度 × 0.7
4. 创建伴读窗口：x = 浏览器左边界 + 浏览器新宽度, y = 浏览器上边界, w = 工作区剩余宽度, h = 浏览器高度
5. 同时调整浏览器窗口和伴读窗口（Win32 `SetWindowPos` / macOS `setFrame`）

**第四步：AI 分析。** 提取的页面内容发送给 LLM（在伴读专用会话中），AI 生成：

- **文章摘要**：300-500 字的精炼总结
- **段落解析**：每个主要段落的要点提炼
- **关键概念**：文章中提及的核心术语和定义

**第五步：伴读窗口就绪。** 用户看到：

- **左侧（70%）**：浏览器原页面，可以正常滚动阅读
- **右侧（30%）**：伴读窗口，含三个区域：
  - 📑 **目录区域**：可点击的标题树，点击后通过 CDP 执行 `window.scrollTo()` 让浏览器同步滚动
  - 📝 **AI 摘要区域**：文章总结和段落解析
  - ✏️ **Markdown 编辑器**：预填 AI 生成的段落解析内容，用户可直接编辑、增删

Avatar 切换到 `reading` 动画状态——拿笔记录、翻书、偶尔抬头思索。

**第六步：入库存档。** 阅读完成后，点击伴读窗口的"入库"按钮：
- 原文 URL + 标题
- AI 生成的摘要
- 用户编辑后的笔记（Markdown）
- 自动打上 `#伴读` 标签
- 全部存入 Bonio 的记忆系统

以后你可以在 Memory 界面或对话中检索："帮我把 #伴读 的笔记找出来"。

---

## 技术核心：CDP 浏览器自动化

CDP（Chrome DevTools Protocol）是 Blink 内核浏览器（Chrome、Edge、Opera、Brave）暴露的调试协议。Bonio 通过它做到三件事：

### 1. 内容提取

```javascript
// 注入到页面中的内容提取脚本（简化）
function extractPageContent(maxLength) {
  // 提取标题
  const title = document.title;

  // 提取标题层级
  const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'))
    .map(h => ({ level: parseInt(h.tagName[1]), text: h.textContent.trim() }));

  // 提取正文（通过 Readability 算法定位主要内容区域）
  const article = document.querySelector('article') ||
    document.querySelector('main') ||
    document.querySelector('[role="main"]') ||
    document.body;

  const text = article.innerText.substring(0, maxLength || 50000);

  return { title, url: location.href, headings, text };
}
```

### 2. 目录点击 → 浏览器滚动

伴读窗口中点击某个目录标题，通过 CDP 向浏览器注入：

```javascript
// 找到对应标题元素，滚动到它所在位置
const heading = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'))
  .find(h => h.textContent.trim() === '目标标题文本');
if (heading) heading.scrollIntoView({ behavior: 'smooth', block: 'start' });
```

### 3. 自动连接

CDP 连接不需要用户手动开启——Bonio 自动检测本机是否有 Chrome 或 Edge 进程在运行调试端口。如果未开启，Bonio 会自动以 `--remote-debugging-port=9222` 参数重启浏览器（需要用户授权）。

---

## Markdown 编辑器

伴读窗口内嵌了一个轻量级 Markdown 编辑器，支持：
- 实时预览（Markdown → 富文本渲染）
- 常用快捷键（加粗、斜体、列表、标题）
- AI 预填内容（段落解析 + 摘要）
- 用户自由编辑、增删

编辑器内容在用户点击"入库"后，以 Markdown 原文存入记忆系统。下次打开时可以继续编辑。

---

## 设计哲学：从"阅读工具"到"阅读搭子"

"伴读"不是一个 RSS Reader，不是一个稍后读 app，不是一个 Markdown 编辑器——它把这些功能组合成了一个**阅读场景下的完整陪伴体验**。

传统阅读工具的困境是：它们提供了"读"的功能，但没有解决"读了之后怎么办"。笔记是孤立的，摘要是手动的，目录是不可点击的。"伴读"把提取、分析、记录、回顾串成了一个闭环。

更重要的是：**Avatar 在你阅读时一直在旁边。** 它切换到 `reading` 动画——拿笔记录、翻书、偶尔抬头思索——像一个安静陪你读书的朋友。你不需要跟它互动，但你知道它在那里。

---

*下一篇：[记忆系统：你的外挂大脑](08-memory-system.md)*
