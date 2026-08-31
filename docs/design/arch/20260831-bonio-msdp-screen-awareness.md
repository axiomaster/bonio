# Bonio 三层四部分架构与 MSDP 屏幕感知

> 日期：2026-08-31
> 状态：实施中

## 架构

Bonio 按三层划分、由四个部分协作：

```
┌─────────────────────────────────────────────────────────────────┐
│ 交互层：Avatar / 系统悬浮窗                                        │
│ 常驻桌面，承载点击、拖拽、语音与状态反馈；不直接读取屏幕内容。      │
├─────────────────────────────────────────────────────────────────┤
│ 应用层：Bonio App                                                  │
│ 内容管理、设置和权限策略；把 Avatar、MSDP 与 DSH 连接成受控链路。   │
├──────────────────────────────┬──────────────────────────────────┤
│ 系统服务层：MSDP              │ Agent 服务层：DSH                │
│ 当前页上下文、段落 hook 滚动  │ 大模型、会话、记忆、工具编排      │
└──────────────────────────────┴──────────────────────────────────┘
```

DSH 只能通过 Bonio App 的 node session 调用设备能力。MSDP 不能直接连到
Avatar 或 DSH，避免系统权限与原始页面内容跨越应用层的用户控制。

## MSDP 能力边界

`@ohos.multimodalAwareness.onScreen` 是系统 API
(`SystemCapability.MultimodalAwareness.OnScreenAwareness`)。Bonio 使用：

- `getPageContent()`：按需取得当前页的 bundle、窗口、标题、内容、链接与段落。
- `sendControlEvent(SCROLL_TO_HOOK)`：仅在同一次上下文中返回的段落 hook 上滚动。
- `onReadingScreenPermissionListener()`：观察系统是否允许读取当前屏幕。
- `subscribe({groupId: 'SmartEdge'})`：在本地观察前台应用和页面切换。
- `trigger({groupId: 'SmartEdge'})`：在用户双击 Avatar 时采集一次当前页的结构化结果。

该 API **不提供全局原始点击、手势或键盘监听**。对用户在目标应用中的交互，MSDP
可提供的是页面/实体/段落上下文变化，以及受限的 hook 滚动；任何更广泛的输入监听需
另行评估无障碍或系统输入接口，不能把它假设为 onScreen 能力。

## DSH 工具契约

| DSH node 命令 | 参数 | 结果 | 约束 |
|---|---|---|---|
| `screen.context` | `maxTextLength?` | `ScreenContextSnapshot` | 仅用户开启“Screen Awareness”后执行，文本最多 12000 字符。 |
| `screen.scrollToHook` | `hookId` | `{scrolled: true}` | 仅允许操作最近一次 `screen.context` 返回的 hook。 |

`ScreenContextSnapshot` 不落盘、不自动推送到 DSH；仅作为一次显式工具调用的返回值。
未授权、设备不支持、页面不支持、页面未就绪和超时均会转为稳定的 node 错误码。

Avatar 双击是另一条显式链路：Bonio App 调用 SmartEdge `trigger`，把本次结构化
结果发送到 DSH 的独立 `system:screen-memory` 会话。DSH 仅在识别到持久、有用且不含
密码、验证码、金融标识或完整私信的内容时调用 `memo_save`（`source=msdp_smart_edge`）。
页面切换订阅不会自动上传或自动创建记忆。

调试期间，Bonio 会把 SmartEdge `subscribe` 和 `trigger` 返回的完整原始 JSON
作为本地 Chat 调试消息显示。只有 Avatar 双击触发的结果会随记忆请求发送给 DSH；
订阅事件仍不会自动上传。

## 权限与签名

- `ohos.permission.GET_SCREEN_CONTENT`：MSDP 读取页面内容，`system_core` ACL。
- `ohos.permission.ONSCREEN_AWARENESS`：用户授权开关，目标 API 26。
- `ohos.permission.SIMULATE_USER_INPUT`：执行 `SCROLL_TO_HOOK`，`system_core` ACL。

发布包必须使用 `harmonyos/root_float_signing/msdpdemo-system-core-profile.json`
重新生成 profile、通过 `tools/hapsigner` 签名，并在真机上验证上述权限和页面兼容性。
