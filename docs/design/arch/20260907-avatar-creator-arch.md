# 技术架构文档 (Architecture)：Bonio Avatar 皮肤工厂与端侧动态装配

**文档版本:** V1.0  
**日期:** 2026-09-07  
**对应需求文档:** [docs/design/prd/20260907-avatar-creator-prd.md](../prd/20260907-avatar-creator-prd.md)

---

## 1. 架构目标与设计原则

1. **规范绝对统一 (Strict Sprite Contract)**：
   - 所有无论是内置（Cat/Kun/Mario/Messi）还是用户自建（Custom）的皮肤，在像素网格、尺寸、动作行分布上执行统一的“8列 x 9行，单帧 192x208，总图 1536x1872”规范。
2. **双轨渲染平滑解耦 (Dual-Path Rendering)**：
   - 悬浮窗 `FloatWindowPage` 不再写死静态 switch，抽象为 `CustomSkinManager` 统一寻址服务，支持应用内 Resource (`$rawfile(...)`) 与本地沙箱文件 URI (`file://...`) 的统一透明消费。
3. **安全沙箱存储 (Isolated Local Sandbox)**：
   - 自定义皮肤持久化保存于应用内部存储目录 `<el2>/files/avatar_skins/<skin_id>/`，伴随元数据 `meta.json` 索引，卸载或清理可控，防止文件泄漏。
4. **轻量与可扩展 (Extensible Skin Ecosystem)**：
   - 为后续跨端导入、皮肤市场共享或端侧 AI 离线生成提供规范的资产包结构。

---

## 2. 总体架构拓扑图

```text
+-------------------------------------------------------------------------+
|                              User Interface                             |
|  +---------------------------+       +-------------------------------+  |
|  |     SkillsTab.ets         |       |   AvatarCreatorDialog.ets     |  |
|  |  (Skin Gallery & Switch)  |       | (Upload, Generate, Preview)   |  |
|  +-------------+-------------+       +---------------+---------------+  |
+----------------|-------------------------------------|------------------+
                 |                                     |
                 v                                     v
+-------------------------------------------------------------------------+
|                     CustomSkinManager (Service Layer)                   |
|  - listSkins(): CustomSkinItem[]                                        |
|  - createSkinFromImage(name, uri, meta): Promise<string>                |
|  - deleteSkin(skinId): void                                             |
|  - getSkinFileUri(skinId): string                                       |
+----------------+-------------------------------------+------------------+
                 |                                     |
                 v                                     v
+--------------------------------+   +------------------------------------+
| Local Sandbox File Storage     |   | State & Persistence                |
| <filesDir>/avatar_skins/       |   | - SecurePrefs (avatar.skin)        |
| ├── custom_1/                  |   | - AppStorage ('avatarSkin')        |
| │   ├── spritesheet.png        |   +------------------------------------+
| │   └── meta.json              |                     |
| └── skins_index.json           |                     v
+--------------------------------+   +------------------------------------+
                                     | System Float Window                |
                                     | (FloatWindowPage.ets)              |
                                     | - Image(skinManager.getSpriteUri())|
                                     | - Dynamic KunAnimations timer      |
                                     +------------------------------------+
```

---

## 3. 核心子系统与关键实现

### 3.1 皮肤元数据标准与沙箱结构
每一个安装在设备上的皮肤均具有标准化的数据描述：

```typescript
export interface CustomSkinItem {
  id: string;              // 内置: 'cat' | 'kun' | 'mario' | 'messi'；自定义: 'custom_<uuid>'
  name: string;            // 展示名称（如：“草帽路飞”）
  subtitle: string;        // 描述（如：“HD Pixel Art Avatar”）
  isBuiltin: boolean;      // 是否内置资源
  rawfile?: string;        // 内置资源名称，如 'mario-spritesheet.webp'
  fileUri?: string;        // 自定义沙箱绝对路径 file://...
  previewUri?: string;     // 封面预览图
  victoryQuote?: string;   // 任务完成专属气泡台词
  createdAt: number;       // 创建时间戳
}
```

### 3.2 动态渲染协议与状态机
`FloatWindowPage` 将原有写死分支升级为：
1. **状态机驱动**：监听 `AppStorage.get('avatarSkin')` 的变更。
2. **纹理寻址策略**：
   - 若 `skin === 'cat'`：启动 Canvas Lottie 动画器。
   - 若 `skin.isBuiltin`：调用 `Image($rawfile(skin.rawfile))`。
   - 若 `!skin.isBuiltin`：调用 `Image(skin.fileUri)`，借助 ArkUI 强大的本地图片加载器直接显示沙箱图片，无需转 Base64 消耗内存。
3. **帧计算无感适配**：
   - 保持 `KUN_FRAME_WIDTH = 192 * AVATAR_SIZE / 208` 坐标系，所有符合规范的自定义 8x9 SpriteSheet 在缩放和裁剪定位逻辑上与 Kun 100% 保持一致。

---

## 4. 容错与优雅降级机制

1. **文件损坏/不存在检查**：
   - 加载自定义皮肤前校验文件是否存在；若损坏或丢失，自动重置为默认 `cat` 并向用户发出浮动轻提示。
2. **内存优化**：
   - 用户连续生成或预览不同皮肤时，即时释放旧图解码句柄，避免 OOM。
