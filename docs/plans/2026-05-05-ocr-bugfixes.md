# OCR 功能 Bug 修复计划

## Context

OCR "识别文字" 功能存在 5 个 bug：扩展屏头像定位错误、OCR 只能截伴随窗口、DPI 缩放导致窗口巨大、OCR 在服务端执行、结果窗口 UI 不符合预期。需要逐一修复。

---

## Bug 1: 扩展屏头像定位错误

**问题**：扩展屏上的浏览器窗口（非全屏），头像不在窗口上方，而在屏幕底部中央，且底部有空隙（类似任务栏高度）。

**根因**：`avatar_window_app.dart:2256-2260` 全屏检测使用 `SM_CXSCREEN/SM_CYSCREEN`（仅返回主显示器尺寸），导致扩展屏窗口被错误分类。

**修复**：

1. 将 `_getMonitorRects` (L1962) 提取为文件级函数 `getMonitorRects(int hwnd)`（它不使用任何实例状态）
2. 在 `_getWinWindowRect` (L2256-2260) 中用 `getMonitorRects(hwnd)` 获取实际显示器尺寸替代 `SM_CXSCREEN/SM_CYSCREEN`
3. `hasBottomTaskbar` 检测 (L1993) 加入阈值 `> 4`，避免扩展屏微小差异被误判为任务栏

**文件**：`desktop/lib/avatar_window_app.dart`

---

## Bug 2: OCR 只能截取伴随窗口

**问题**：OCR 应该可以选择屏幕任意区域，当前限制为只能截取伴随窗口。

**根因**：`_enterLensMode` (L1401-1417) 要求 `_anchoredHwnd != 0` 并调用 `captureWindow(_anchoredHwnd)`。

**修复**：

1. 当 `ocr == true` 时，跳过 anchoredHwnd 检查
2. 使用 `ScreenCapture.captureScreen()` 截取主屏幕（已存在于 `screen_capture.dart:12`）
3. 将 avatar 窗口扩展到覆盖主屏幕（起点 (0,0)，尺寸用 capture 的物理像素除以 DPI 缩放）
4. 非 OCR 模式保持原有逻辑不变

**文件**：`desktop/lib/avatar_window_app.dart`（`_enterLensMode` 方法）

---

## Bug 3: OCR 框选后窗口巨大（DPI 缩放）

**问题**：选择识别文字后，avatar 窗口变得非常大，与屏幕显示倍率相关。

**根因**：`_enterLensMode` (L1436-1439) `windowManager.setSize(Size(expandW, expandH))` 传入的是物理像素，但 `setSize` 期望逻辑像素。

**修复**：

```dart
await windowManager.setSize(Size(expandW / _avatarDpiScale, expandH / _avatarDpiScale));
```

同时适用于 OCR 模式的屏幕扩展（Bug 2 的修复也包含同样的 DPI 修正）。

**文件**：`desktop/lib/avatar_window_app.dart`（`_enterLensMode` L1439）

---

## Bug 4: OCR 在服务端执行，创建 bonio-ocr session

**问题**：设计要求 OCR 在 client 端实现，但实际会创建 server 端 session。

**根因**：`app_state.dart:257-300` 的 AI 降级路径创建 `sessionKey: 'bonio-ocr'` 聊天 session。当本地 PaddleOCR 初始化失败时会触发此路径。

**修复**：

1. `_handleOcrText` (L198-230)：在调用 `recognize` 前检查 `runtime.paddleOcr.isInitialized`，添加日志
2. `_ocrViaAi` (L257-300)：在完成 OCR 后删除临时 session：
   ```dart
   // 在 completer.future 完成后
   try {
     await runtime.operatorSession.request('sessions.delete', jsonEncode({
       'sessionKey': 'bonio-ocr',
     }), timeoutMs: 5000);
   } catch (_) {}
   ```
3. 改善 PaddleOCR 初始化日志（`node_runtime.dart`），便于排查初始化失败原因

**文件**：`desktop/lib/providers/app_state.dart`、`desktop/lib/services/node_runtime.dart`

---

## Bug 5: OCR 结果窗口 UI 问题

**5 个子问题**：

### 5.1 标题应在 OS 标题栏
- `ocr_result_window.dart` initState 中添加 `windowManager.setTitle(S.current.ocrResultTitle)`
- 移除 AppBar 或将 AppBar 改为无 title 的简单工具栏

### 5.2 上方显示截屏图片，下方显示识别文字
- `OcrResultWindow` 新增 `imageBase64` 参数
- 传递链：`app_state._handleOcrText` → `node_runtime.createOcrResultWindow(text, imageBase64:)` → `main.dart` 参数解析 → `OcrResultWindow(imageBase64:)`
- 窗口 body 用 Column：顶部 `Image.memory(base64Decode(imageBase64))`（约束 maxHeight: 200），底部 TextField

### 5.3 移除多余的关闭按钮
- 删除 AppBar actions 中的 IconButton（X 按钮）

### 5.4 底部只保留"复制"按钮
- 删除 OutlinedButton "关闭"（L101-107），只保留 FilledButton "复制"

### 5.5 关闭窗口不退出整个应用
- 添加 `WindowListener` mixin
- initState 中 `setPreventClose(true)`
- `onWindowClose` 回调中：`setPreventClose(false)` 后 `windowManager.close()`
- 移除所有 `windowManager.destroy()` 调用

**文件**：
- `desktop/lib/ui/screens/ocr_result_window.dart`（主要改动）
- `desktop/lib/services/node_runtime.dart`（L414-438，传递 imageBase64）
- `desktop/lib/main.dart`（L84-88，解析 imageBase64 参数）
- `desktop/lib/providers/app_state.dart`（L227，传递 imageBase64）

---

## 实施顺序

1. **Bug 3** → DPI 缩放（独立修复，影响 Bug 2 的窗口扩展）
2. **Bug 1** → 扩展屏头像定位（独立修复）
3. **Bug 2** → OCR 任意区域选择（依赖 Bug 3 的 DPI 修正）
4. **Bug 4** → 服务端 session 问题（独立修复）
5. **Bug 5** → 结果窗口 UI（依赖 Bug 4 的 imageBase64 传递）

## 验证

- 编译：`cd desktop && flutter build windows`
- 运行：`scripts\build-and-run.bat`
- 测试场景：
  1. 扩展屏浏览器窗口（非全屏）：avatar 应在窗口上方
  2. 右键"识别文字"：应出现全屏覆盖，可框选任意区域
  3. 150% DPI 屏幕：框选后窗口大小正常，不巨大
  4. OCR 识别后：聊天页面不出现 bonio-ocr session
  5. 结果窗口：标题在标题栏、上方图片、下方文字、只有复制按钮、关闭不退出应用
