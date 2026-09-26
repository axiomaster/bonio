# Architecture：Bonio 皮肤导入（Skin Import）

> 日期：2026-09-26
> 来源：[PRD](../prd/skin-import-prd-20260926.md) ← [Raw PRD](../rr/skin-import-20260926.md)
> 范围：Android（`android/`）

## 1. 现状与总体方案

现有链路：

```
PersonalizationTab ── viewModel.setAvatarSkin(id) ── avatarPrefs("avatar_skin")
FloatingWindowService ── PixelAvatarView.setSkin(id) ── CustomSkinManager.getSkinById(id)
                                                       └─ assets/avatars/<rawfileName>
```

改造后：

```
SkinImporter(SAF uri / OkHttp url) ── 校验+解压 ── filesDir/skins/<id>/   ← 新增
                                                        │
CustomSkinManager（内置 + 已安装注册表, StateFlow） ←─────┘
        │
PixelAvatarView.setSkin(id) ── 资产或文件路径加载 + 每皮肤动画规格
```

核心原则：**皮肤包落盘为目录，注册表运行时合成，渲染层按 SkinItem 来源（assets/file）加载**。内置 4 皮肤行为完全不变。

## 2. 模块设计

### 2.1 `avatar/SkinManifest.kt`（新）

- `SkinManifest` 数据类：对应 PRD 3.2 全部字段；`grid` 缺省 `Grid(8,9,192,208)`；`animations: Map<String, SkinAnim>`，`SkinAnim(row, count, frames: IntArray?)`。
- `SkinManifest.parse(json: String): SkinManifest` — org.json 逐字段解析，容错（未知字段忽略）。
- `validate(): String?` — 返回 null 或错误码（`ERR_ID`/`ERR_GRID`/`ERR_ANIM`…），实现 PRD 3.2/3.3 全部约束。
- `DEFAULT_STATES = ["idle","run_right","run_left","wave","jump","failed","waiting","working","thinking"]`；`defaultRow(state)` = 内置表；`defaultFrameCounts/Durations` 与 `KunAnimations` 数值一致（单一事实来源：`KunAnimations` 改为引用本表，消除两处硬编码）。
- `resolvedAnim(state): KunAnimationSpec` — animations 覆盖优先，回退默认表；`count` 缺省 = 该行默认帧数，`frames` 缺省 = 均分 150ms × count。

### 2.2 `avatar/SkinImporter.kt`（新）

```kotlin
object SkinImporter {
  sealed class ImportResult { data class Success(val skin: SkinItem); data class Failure(val code: String, val message: String) }
  suspend fun installFromUri(context, uri): ImportResult      // SAF → cache 拷贝 → install(File)
  suspend fun installFromUrl(context, url, onProgress:(Int)->Unit): ImportResult  // OkHttp 下载 → install(File)
  suspend fun install(context, zip: File): ImportResult       // 核心管线
  suspend fun uninstall(context, id): Boolean
}
```

`install` 管线（全程 `Dispatchers.IO`）：

1. **尺寸预检**：zip ≤ 20MB；
2. **安全解压**到 `cacheDir/skin_import_tmp/`：`ZipFile` 遍历 entry——拒绝名字含 `..`、以 `/` 开头、含 `\` 的条目；跳过目录条目；剥一层同名外层文件夹；仅接受 `manifest.json`、`spritesheet.webp|png`、`preview.*`；条目 ≤16、单文件 ≤10MB；
3. **清单校验**：解析 + `validate()`；`format_version==1`；id 非内置保留 id；
4. **素材校验**：`BitmapFactory` 实际解码 spritesheet（`inJustDecodeBounds=false`）→ 尺寸必须等于 `grid` 乘积且总像素 ≤4MP；preview 存在则同样解码限制 ≤1024px；
5. **原子落盘**：`filesDir/skins/<id>` 先改名旧目录为 `.bak` → 拷入新目录 → 成功后删 `.bak`；任何失败删临时目录并恢复原状；
6. `CustomSkinManager.refresh(context)` 通知注册表。

`installFromUrl`：OkHttp（已有依赖）`GET`，`ConnectTimeout 10s / ReadTimeout 30s`，跟随重定向，流式落 cache 文件，`Content-Length` 或累计字节 ≥20MB 即中止（`ERR_TOO_LARGE`），进度按 0–100 回调。仅接受 `http(s)`。

`uninstall`：仅自定义 id；删目录 + 若 `avatar_skin == id` 则回落 `"cat"`。

### 2.3 `avatar/CustomSkinManager.kt`（改）

- `SkinItem` 增加 `val sheetFile: String? = null`（自定义皮肤绝对路径；内置仍用 `rawfileName`）、`val manifest: SkinManifest? = null`、`val isCustom` 语义由 `isBuiltin=false` 承担（字段已有）。
- 新增运行时注册表：

```kotlin
private val _customSkins = MutableStateFlow<List<SkinItem>>(emptyList())
val customSkins: StateFlow<List<SkinItem>>
fun refresh(context)          // 扫描 filesDir/skins/*/manifest.json
fun allSkins(context): List<SkinItem>   // built-in + custom
override getSkinById(id)      // 未命中自定义时磁盘兜底扫描一次（防其他进程/时序）
```

- `getAgentBubble(state, skin)`：自定义皮肤 `victory_quote` 生效于 `completed`，其余沿用通用文案。

### 2.4 `avatar/PixelAvatarView.kt`（改）

- `loadSkin`：`SkinItem.sheetFile != null` → `BitmapFactory.decodeFile`；缓存键 `file:<path>:<lastModified>`（覆盖导入自动失效）；assets 路径键不变。
- 动画规格：`currentSpecs: Map<String, KunAnimationSpec>` 随皮肤切换由 `SkinManifest.resolvedAnim` 生成；`getAnimationSpec()` 查表，无 manifest 时用内置 `KunAnimations`。
- 行紧裁 `rowBounds` 缓存键加入皮肤 id（现在按 row 全局缓存，换肤不失效会有跨皮肤脏数据——顺带修复）。

### 2.5 UI（`ui/screens/PersonalizationTab.kt` + `MainViewModel.kt`）

- `MainViewModel`：
  - `val customSkins = CustomSkinManager.customSkins`（初始化时 `refresh`）；
  - `fun importSkinFromUri(uri)` / `fun importSkinFromUrl(url, onProgress)` / `fun deleteCustomSkin(id)`，结果经 `skinImportEvent: MutableStateFlow<ImportResult?>` 一次性回调 UI；
- `PersonalizationTab` 宠物形象卡片：
  - 画廊数据源改为 `CustomSkinManager.allSkins(context) + 自定义`；自定义卡片右上角「×」→ 确认删除；
  - 「＋ 添加」卡片 → `AlertDialog` 两选项；本地走 `ActivityResultContracts.GetContent()`；链接弹 `TextField` 对话框 + 下载进度条；
  - 成功 → `viewModel.setAvatarSkin(newId)` + toast；失败 → 错误对话框（错误码 → i18n 文案）；
- i18n：`AppLanguage.kt` 新增 ~12 条中英文案（导入/下载/删除/各错误码）。

## 3. 错误码（i18n key 对齐）

`ERR_TOO_LARGE` `ERR_BAD_ZIP` `ERR_NO_MANIFEST` `ERR_BAD_MANIFEST` `ERR_RESERVED_ID` `ERR_SHEET` `ERR_DOWNLOAD` `ERR_BAD_URL` `ERR_IO`

## 4. 测试

- 单测（`app/src/test/`，JUnit + org.json，无需 Android 框架）：
  - `SkinManifestTest`：合法清单解析；id/grid/animations 各非法分支；覆盖与回退（`resolvedAnim`）；
  - `SkinPackageTest`：内存构造 zip（`ZipOutputStream` + `ByteArrayInputStream`）→ 校验拒绝 zip-slip 条目、拒绝多余条目、接受合法包（清单+假 sheet 尺寸校验用可注入 decoder 或仅测条目过滤层）。
- 手工验收：内置 4 皮肤回归；打包真实 zip 导入/覆盖/删除/重启持久化；断网下载失败路径。

## 5. 兼容与回滚

- 纯新增能力 + 渲染层内部重构；`avatarPrefs("avatar_skin")` 键不变，老用户无感；
- `KunAnimations` 帧表收敛到 `SkinManifest` 默认表后，`PixelAvatarView` 内置路径数值与旧版完全一致（单测断言各 row/frames 相等）；
- 失败回滚 = revert 本 feature 提交，无数据迁移。
