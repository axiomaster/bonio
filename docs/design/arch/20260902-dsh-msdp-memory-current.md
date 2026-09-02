# Bonio 当前实现：DSH、MSDP 与伴随记忆

> 日期：2026-09-02
> 分支：`dsh`
> 状态：已实现，持续验证

本文是 Bonio HarmonyOS + DSH 当前实现的权威说明，覆盖最近完成的屏幕感知、记忆、聊天和设备部署修改。

## 1. 总体架构

HarmonyOS 端默认通过本机 DSH bridge 通信，不再依赖远程 hiclaw 作为当前设备的 Agent 后端：

```text
Bonio Avatar / Chat UI
        |
        v
bonio-bridge :10724 -> DSH agent -> DeepSeek vision model
        |
        +-- operator session: chat
        +-- node session: device capabilities
        +-- system:companion-memory: MSDP analysis and memo persistence
```

关键配置：bridge `127.0.0.1:10724`，DSH Web `127.0.0.1:13082`，模型 `deepseek-v4-flash-vision-exp`，HarmonyOS bundle `com.example.msdpdemo`。

## 2. 双 session

| Session | key | 内容 | 用途 |
|---|---|---|---|
| 主对话 | DSH 默认主 session，通常为 `main` | Chat 文本、Avatar 长按语音转写 | 用户对话、工具执行、多轮上下文 |
| 伴随记忆 | `system:companion-memory` | MSDP `subscribe`/`trigger` 结果和识别摘要 | 独立分析屏幕内容，不污染主对话 |

伴随记忆摘要完成后，HarmonyOS 端调用 `memo.save` 更新 Memory 页签。DSH bridge 持久化 session 映射和历史，并会轮换损坏的 session。`memo_list` 给 Agent 返回纯文本摘要，不携带大段 base64 图片。

## 3. MSDP 链路

### 自动浏览记

```text
MSDP subscribe -> 过滤系统自有页面 -> companion-memory -> DSH 摘要 -> memo.save
```

忽略 bundle `com.example.msdpdemo`、`com.huawei.hmos.vassistant.launcher`、`com.ohos.sceneboard`，以及 app name `bonio`、`大桌面`。文章、商品、美食、店铺、短视频和购买记录属于高价值浏览信息；密码、验证码、完整私信和短暂界面状态不记录。

### 双击 Avatar 主动记

双击调用 `onScreen.trigger({ groupId: 'SmartEdge' })`，解析 `OnscreenAwarenessInfo[]`，提取 view tree、entity、pageTags 和 PixelMap，再将原始结果与原图发送到伴随记忆 session。

双击表示用户明确要求长期记忆，prompt 要求返回 `shouldRemember: true`。微信小程序缺少 view tree 时，使用截图识别。订单字段必须忠实转录，商品名称无法辨认时写“商品名称未识别”，禁止根据图片外观或常识把冷萃改成拿铁。主动记忆或收藏分析无效时使用本地 fallback，避免明确操作没有记忆卡片。

### 图片处理

MSDP `items[].itemInfo.image` 的 `PixelMap` 同时生成两份图片：

| 字段 | 格式 | 用途 |
|---|---|---|
| `coverImageBase64` | JPEG，最长边最多 480，质量 60 | Memory 列表封面 |
| `originalImageBase64` | PNG，质量 100，原始分辨率 | DSH 视觉分析和详情页 |

DSH attachment 使用原始 PNG，不使用压缩 cover。`memo.list` 只返回封面，`memo.get` 返回原图；Memory 详情页只展示原始截图。

## 4. 记忆存储

每条记忆对应一个目录，设备路径为 `/data/local/home/.bonio/memos/`：

```text
~/.bonio/memos/<memo-id>/
├── memo.json
├── cover.jpg
└── screenshot.png
```

`memo.json` 保存标题、摘要、来源、标签和时间；图片作为独立文件保存。bridge 提供 `memo.save`、`memo.list`、`memo.get`、`memo.delete`。旧版 `<id>.json` 会在请求时迁移为目录结构；不可解析的旧文件保留并记录警告。

## 5. 双维度标签

内容标签由 DSH 生成，例如 `内容:新闻`、`内容:时政`、`内容:财经`、`内容:购物`、`内容:美食`、`内容:生活`、`内容:科技`。

行为标签由客户端根据事件补齐：

| 标签 | 条件 |
|---|---|
| `行为:浏览记` | MSDP subscribe 普通浏览 |
| `行为:主动记` | 双击 Avatar 触发 `trigger` |
| `行为:收藏记` | `pageTags` 包含 `addtofavorite` |

“全部”筛选对应空筛选条件，表示不筛选。

## 6. 订单与复购

订单记忆优先保存商品名称、规格、冰量、糖度、数量、金额、品牌、门店、取餐方式和订单状态。类似“埃塞瑰夏冷萃 / 大杯 / 冰 / 不另外加糖”必须原样保留。

“再来一单”目标流程是：主对话召回订单记忆，结合原始截图确认规格，再调用设备侧 `phone-use-harmonyos` skill 和 `ohos-cli-tool` 完成页面操作；支付等高风险步骤保留用户确认边界。

## 7. Chat UI 修复

- Chat `final` 或 `error` 状态显示 4 秒后回到 `idle`，`aborted` 立即回到 `idle`，不再永久停留在“在等你回复哦~”。
- 历史解析只保留非空文本、带 base64 的图片和文件；未知块、空块、工具结果和 reasoning 不再渲染为 file 图标。
- Memory 列表显示压缩封面；打开详情前先请求 `memo.get`，详情只显示原始截图，不回退到模糊封面。

## 8. 部署与验证

HarmonyOS 需要使用 DevEco hvigor 全量执行 `clean assembleHap`，再以 `harmonyos/root_float_signing/msdpdemo-system-core-profile.p7b` 通过 `tools/hapsigner` 签名，并用 HDC `install -r` 覆盖安装。当前验证设备为 `5MQ0125716000138`，安装后的 bundle 权限级别为 `system_core`。

bridge 或设备 skill 修改后分别使用仓库中的 `tools/deploy-bonio-bridge-ohos.sh` 和 `tools/deploy-dsh-skills-ohos.sh` 部署。

验证重点：双 session 分离；订单双击后 `memo.get` 返回 `originalImage`；`cover.jpg` 与 `screenshot.png` 分辨率明显不同；详情显示原图；Chat 完成后 Avatar 回到 `idle`。

## 9. 最近落地的提交

`028f705` 封面和订单详情；`54d402e` 内容/行为标签；`ec681f3` 原始 MSDP 截图；`0fbb486` 损坏 session 轮换；`caee1be` 记忆工具 JSON 兼容；`fbad0f3` Avatar 收尾状态和 Chat 附件过滤；`a8b01b1` 设备 skill 部署；`ce50a04` 详情页使用原始截图。

## 10. 当前限制

- PixelMap 是否返回取决于 MSDP 服务和页面支持，没有图片时只能使用结构化文本。
- MSDP on-screen 不等于全局点击/滑动监听，完整 SOP 仍需额外输入或无障碍能力。
- 原图链路落地前创建的旧记忆可能只有 cover，无法凭空恢复原图。
