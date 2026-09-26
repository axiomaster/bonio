# Refined PRD：Bonio 皮肤导入（Skin Import）

> 日期：2026-09-26
> 来源 Raw PRD：[docs/design/rr/skin-import-20260926.md](../rr/skin-import-20260926.md)
> 状态：已评审，进入架构设计 `docs/design/arch/skin-import-arch-20260926.md`

## 1. 背景与目标

Bonio Android 客户端的悬浮宠物当前只支持 4 个**内置**皮肤（`CustomSkinManager` 硬编码：cat/kun/mario/messi，sprite sheet 随 APK 打包）。本功能让用户把**外部皮肤 zip 包**导入 App，与内置皮肤并列展示、随时切换。

**目标**：

1. 定义开放的皮肤包格式（zip + 清单 + 素材要求），社区/用户可自行制作；
2. 支持 **本地文件导入**（系统文件选择器）与 **在线链接导入**（URL 下载）；
3. 导入成功即可切换、重启后仍然生效；支持删除自定义皮肤。

## 2. 用户故事

| # | 故事 | 验收标准 |
|---|------|----------|
| U1 | 作为用户，我在"个性化"页点"添加皮肤"，从手机里选一个皮肤 zip，导入后立即出现在皮肤画廊并可点选切换 | 导入成功 → 画廊出现新卡片并自动启用；悬浮窗头像立即换肤 |
| U2 | 作为用户，我粘贴一个 https 链接，App 下载该 zip 并导入 | 下载有进度提示；完成后同 U1；下载失败/格式不对时给出明确报错 |
| U3 | 作为用户，我删除一个不需要的自定义皮肤 | 仅自定义皮肤可删；若删除的是当前皮肤，回落到默认 cat |
| U4 | 作为用户，我重复导入同 id 的皮肤包 | 按"覆盖更新"处理，不产生重复卡片 |
| U5 | 作为用户，我导入一个损坏/超限/伪装成 zip 的文件 | 导入被拒绝，提示具体原因（格式错误/超出大小限制/与内置皮肤冲突等），不产生半成品目录 |

## 3. 皮肤包格式（v1，`format_version = 1`）

### 3.1 包结构

```
<skin-id>.zip
├── manifest.json          # 必需，UTF-8 JSON
├── spritesheet.webp       # 必需（webp 或 png，与 manifest.spritesheet 一致）
└── preview.png            # 可选；缺省时取 idle 行第 1 帧作为画廊预览
```

- 条目位于 zip **根部**（允许一层同名文件夹包裹，导入时自动剥掉）；
- 除上述三类文件外，其他条目一律拒绝；条目总数 ≤ 16；
- zip 整体 ≤ 20 MB；清单/素材单文件 ≤ 10 MB。

### 3.2 manifest.json 字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `format_version` | int | ✅ | 必须为 `1` |
| `id` | string | ✅ | `^[a-z0-9][a-z0-9_-]{1,31}$`；不得与内置 id（cat/kun/mario/messi）重复；重复导入同 id 按 U4 覆盖 |
| `name` | string | ✅ | 展示名，≤ 24 字符 |
| `subtitle` | string | ✅ | 一句话描述，≤ 32 字符 |
| `version` | string | ⬜ | 作者自定版本号，≤ 16 字符 |
| `author` | string | ⬜ | ≤ 24 字符 |
| `victory_quote` | string | ⬜ | 完成态气泡台词；缺省用通用文案 |
| `spritesheet` | string | ✅ | 素材文件名，`spritesheet.webp` / `spritesheet.png` |
| `preview` | string | ⬜ | 预览文件名（png/jpg/webp） |
| `grid` | object | ⬜ | `{cols, rows, frame_width, frame_height}`；缺省 `{8, 9, 192, 208}`；约束：1≤cols≤16，1≤rows≤16，32≤fw≤512，32≤fh≤512，cols×fw ≤ 2048，rows×fh ≤ 2048，总像素 ≤ 4MP |
| `animations` | object | ⬜ | 状态 → `{row, count?, frames?}` 覆盖表，见 3.3 |

### 3.3 动画行语义

9 个逻辑状态固定为（与内置 `KunAnimations` 一致）：`idle, run_right, run_left, wave, jump, failed, waiting, working, thinking`。

- 缺省映射：按行号 0–8 一一对应，帧数与每帧时长使用内置默认表；
- `animations` 可覆盖某状态的 `row`（sprite sheet 行号）、`count`（实际使用帧数，1≤count≤cols）、`frames`（每帧毫秒数组，长度=count）；
- 未覆盖的状态回退默认表；行号越界时按 0 处理（渲染层已有 clamp）。

### 3.4 素材要求

| 素材 | 要求 |
|------|------|
| spritesheet | PNG/WebP；实际像素尺寸必须精确等于 `cols×frame_width` × `rows×frame_height`；每格一帧、透明背景；同一行的各帧建议内容边界对齐（渲染层有逐行紧裁，但行内跳帧会肉眼抖动）；状态行姿态建议：idle 趴/站循环、run_right/run_left 朝向奔跑、wave 挥手、jump 跳跃、failed 委屈、waiting 等待、working 干活、thinking 思考 |
| preview | png/jpg/webp，最长边 ≤ 1024px，建议取 idle 行首帧 |

## 4. 交互设计

个性化 → 宠物形象卡片：

1. 画廊末尾新增 **「＋ 添加」** 卡片，点击弹出底部菜单：**从本地导入** / **从链接导入**；
2. 本地：系统文件选择器（mime：zip / x-zip-compressed / octet-stream）；
3. 链接：输入 https URL → 显示下载进度 → 校验导入；
4. 成功：toast「皮肤已导入」+ 自动切换为该皮肤（含悬浮窗实时换肤）；
5. 失败：对话框展示原因（下载失败 / 格式错误 / 大小超限 / 与内置皮肤 id 冲突 / 素材校验失败…）；
6. 自定义卡片右上角 **「×」** 删除（确认框）；删除当前皮肤时回落 cat。

## 5. 非功能需求

- **安全**：zip 解压防路径穿越（拒绝 `../`、绝对路径、符号链接）；大小/条目上限；仅解析 JSON 与位图，不执行任何包内代码；
- **稳定**：导入为"先校验后原子落盘"，任何一步失败不留半成品；重复导入同 id 先删旧目录再落新；
- **性能**：spritesheet 解码复用现有 `bitmapCache`；按文件路径 + mtime 作缓存键，覆盖导入后自动失效；
- **i18n**：新增文案同时提供中英文（沿用 `AppStrings`）；
- **范围**：仅 Android；不做皮肤商店/在线列表，不做桌面与 HarmonyOS 同步。
