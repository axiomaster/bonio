# Boji Desktop macOS 补齐计划

> 生成日期: 2026-04-16
> 依据: README.md 军规

---

## 一、差异分析总结

| 功能 | Windows | macOS | 状态 |
|------|---------|-------|------|
| 屏幕捕获 | ✅ win32_screen_capture | ❌ 缺失 | P0 |
| 窗口截图 | ✅ PrintWindow+BitBlt | ❌ 缺失 | P0 |
| 窗口操作 | ✅ SetWindowPos/GetMonitorInfo | ❌ 缺失 | P0 |
| 浏览器 URL 提取 | ✅ 窗口类名+正则 | ❌ 缺失 | P0 |
| AI Lens | ✅ 截图选区 | ❌ 缺失 | P1 |
| Avatar 窗口锚定 | ✅ 附着任意窗口 | ⚠️ 仅 Dock | P1 |
| Avatar 前台轮询 | ✅ 50ms 锚定+500ms 检查 | ❌ 不执行 | P1 |
| 阅读伴侣 | ✅ 窗口截图+URL | ❌ 缺失 | P1 |
| 笔记截取 | ✅ Win32ScreenCapture | ❌ 缺失 | P2 |
| TTS | ✅ PowerShell+SAPI | ✅ say | ✅ |
| 麦克风 | ✅ winmm.dll | ✅ AudioToolbox | ✅ |

---

## 二、补齐计划

### P0 - 基础设施（必须先完成）

| # | 任务 | 依赖 | 预估工作量 | 产出文件 |
|---|------|------|-----------|----------|
| P0-1 | macOS 屏幕捕获框架 | - | 3-4h | `lib/platform/macos_screen_capture.dart` |
| P0-2 | macOS 窗口截图 | P0-1 | 2h | 复用 P0-1 |
| P0-3 | macOS 窗口操作 (位置/大小) | P0-1 | 2h | 复用 P0-1 |
| P0-4 | macOS 浏览器 URL 提取 | P0-2 | 2h | 复用 P0-1 |

**技术方案**: 使用 `dart:ffi` 调用 macOS 私有 API (`CoreGraphics`, `WindowServer`) 或 `screencapture` 命令 + `NSWindow` API

---

### P1 - 核心功能（依赖 P0）

| # | 任务 | 依赖 | 预估工作量 | 产出文件 |
|---|------|------|-----------|----------|
| P1-1 | macOS AI Lens 截图选区 | P0-1 | 2h | `lib/ui/screens/ai_lens_screen.dart` |
| P1-2 | macOS Avatar 窗口锚定 | P0-3 | 3h | `lib/avatar_window_app.dart` |
| P1-3 | macOS Avatar 前台轮询 | P1-2 | 2h | 复用 avatar_window_app |
| P1-4 | macOS 阅读伴侣 | P0-4 | 2h | `lib/ui/screens/reading_companion_screen.dart` |
| P1-5 | macOS 笔记截取 | P0-4 | 2h | `lib/services/note_service.dart` |

---

### P2 - 优化功能

| # | 任务 | 依赖 | 预估工作量 |
|---|------|------|-----------|
| P2-1 | macOS Dock 集成优化 | - | 1h |
| P2-2 | macOS 通知集成 | - | 1h |

---

## 三、开发顺序

```
P0-1 ──► P0-2 ──► P0-3 ──► P0-4
  │                      │
  │                      ▼
  │                   P1-4 (阅读伴侣)
  │                      │
  ▼                      ▼
P1-1 (AI Lens)       P1-5 (笔记)
  │                      │
  ▼                      ▼
P1-2 (Avatar锚定) ◄───┘
  │
  ▼
P1-3 (前台轮询)
  │
  ▼
P2 (优化)
```

---

## 四、验证标准

- [ ] `flutter build macos` 编译通过
- [ ] 每个功能独立测试
- [ ] 遵循军规: 每个任务单独 git commit + push

---

## 五、风险与注意事项

1. **macOS API 限制**: 窗口操作可能需要 Accessibility 权限
2. **浏览器 URL 提取**: macOS 上可能需要 AppleScript 或 Accessibility
3. **屏幕捕获**: 需要 Screen Recording 权限

---

请确认计划后，我将按顺序开始实施。