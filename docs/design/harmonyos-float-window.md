# HarmonyOS 系统级悬浮窗 root 实验方案

> 版本: 2026年5月9日
> 状态: 实验验证通过
> 适用范围: 自有、已 root 的 HarmonyOS 设备。本文方案不面向普通用户分发。

---

## 1. 目标

Bonio HarmonyOS 版本需要实现真正的系统级悬浮窗：窗口可以悬浮在桌面和其它 App 之上，效果对标 Android `SYSTEM_ALERT_WINDOW` / `float_window`，而不是应用内子窗口或主窗口内覆盖层。

本次实验的目标是验证：在设备已经 root 的前提下，是否可以通过补齐系统安装态和权限授权态，让普通 HAP 创建 `window.WindowType.TYPE_FLOAT`。

结论：可以实现。关键不在 ArkTS 代码，而在 HarmonyOS 的安装态权限数据和 AccessToken 授权数据。

---

## 2. 背景与限制

HarmonyOS 的 `TYPE_FLOAT` 属于系统级窗口类型。普通三方应用即使在 `module.json5` 中声明 `ohos.permission.SYSTEM_FLOAT_WINDOW`，正常安装也会失败：

```text
install failed due to grant request permissions failed.
PermissionName: ohos.permission.SYSTEM_FLOAT_WINDOW
```

如果绕过安装阶段只修改运行时权限，仍会遇到两类问题：

1. BMS 认为包未声明该权限，运行时检查会报 `code:201`。
2. AccessToken 未给当前 HAP token 授权，窗口服务会报 `Permission ohos.permission.SYSTEM_FLOAT_WINDOW is not granted`。

因此系统级浮窗需要同时满足三层条件：

1. HAP manifest 中声明 `ohos.permission.SYSTEM_FLOAT_WINDOW`。
2. BMS 安装态数据库中记录该权限声明。
3. AccessToken 数据库中给当前应用 token 授权该权限。

---

## 3. ArkTS 实现

应用侧代码使用 HarmonyOS 官方窗口接口创建系统浮窗：

```ts
this.floatWindow = await window.createWindow({
  name: 'CatSystemFloatWindow',
  windowType: window.WindowType.TYPE_FLOAT,
  ctx: this.abilityContext
});

await this.floatWindow.moveWindowTo(100, 100);
await this.floatWindow.resize(200, 200);
this.floatWindow.setWindowBackgroundColor('#00000000');
await this.floatWindow.setWindowFocusable(false);
await this.floatWindow.setWindowTouchable(true);
await this.floatWindow.setUIContent('pages/FloatWindowPage');
await this.floatWindow.showWindow();
```

manifest 中声明系统浮窗权限：

```json5
{
  "name": "ohos.permission.SYSTEM_FLOAT_WINDOW",
  "reason": "$string:reason_float_window",
  "usedScene": {
    "abilities": ["EntryAbility"],
    "when": "inuse"
  }
}
```

仅做以上代码修改并不能通过普通安装。普通安装会在授权校验阶段拒绝系统权限。

---

## 4. root 安装态补丁方案

### 4.1 总体流程

实验路径如下：

1. 正常安装一个可运行的 Bonio HAP。
2. 构建包含 `SYSTEM_FLOAT_WINDOW` 声明的新 HAP。
3. 不直接通过 `bm install` 安装新 HAP，因为安装会被权限校验拒绝。
4. 在 root 环境下补齐 BMS 安装态数据库。
5. 在 root 环境下补齐 AccessToken 授权态数据库。
6. 重启设备，使 BMS 和 AccessToken 服务重新加载数据库。
7. 启动 App，触发 `TYPE_FLOAT` 创建，验证 `CatSystemFloatWindow` 出现在 WindowManager / RenderService 日志中。

### 4.2 不建议直接替换 entry.hap

实验中曾尝试 root 原地替换：

```text
/data/app/el1/bundle/public/com.axiomaster.bonio/entry.hap
```

替换后 BMS 可以读到新 HAP 的 manifest，但 App 启动会卡启动页并闪退。日志显示：

```text
mmap failed, errno[13]. fileName: ets/modules.abc
failed to create js obj
```

判断原因是 HarmonyOS 对已安装 HAP 的可执行映射有额外安装态、签名或 XPM 元数据约束。root `cp` 出来的文件即使 owner、mode、SELinux context 看起来正确，也可能无法被 Ark runtime mmap。

最终验证采用的安全路径是：恢复原始可运行 HAP，只补 BMS 和 AccessToken 数据库。这样 App 可以正常启动，同时系统认为该包拥有系统浮窗权限。

---

## 5. BMS 安装态补丁

### 5.1 数据库位置

BMS 安装态数据位于：

```text
/data/service/el1/public/bms/bundle_manager_service/bmsdb.db
/data/service/el1/public/bms/bundle_manager_service/bmsdb_slave.db
```

关键表：

```sql
installed_bundle(KEY TEXT PRIMARY KEY, VALUE TEXT)
```

Bonio 的记录：

```sql
select KEY, VALUE
from installed_bundle
where KEY = 'com.axiomaster.bonio';
```

`VALUE` 是一段完整 JSON，`bm dump -n com.axiomaster.bonio` 的权限信息主要来自这里。

### 5.2 需要补齐的字段

在 `installed_bundle.VALUE` JSON 中补齐以下位置：

1. `baseBundleInfo.reqPermissionDetails`
2. `baseBundleInfo.reqPermissionStates`
3. `baseBundleInfo.reqPermissions`
4. `baseApplicationInfo.permissions`
5. `innerModuleInfos.entry.requestPermissions`

追加权限详情：

```json
{
  "moduleName": "entry",
  "name": "ohos.permission.SYSTEM_FLOAT_WINDOW",
  "reason": "$string:reason_float_window",
  "reasonId": 16777224,
  "usedScene": {
    "abilities": ["EntryAbility"],
    "when": "inuse"
  }
}
```

模块级 `requestPermissions` 中的 `moduleName` 可保持与其它模块权限一致：

```json
{
  "moduleName": "",
  "name": "ohos.permission.SYSTEM_FLOAT_WINDOW",
  "reason": "$string:reason_float_window",
  "reasonId": 16777224,
  "usedScene": {
    "abilities": ["EntryAbility"],
    "when": "inuse"
  }
}
```

`reqPermissionStates` 需要与 `reqPermissions` 长度匹配。实验中 `SYSTEM_FLOAT_WINDOW` 使用：

```text
0
```

### 5.3 写回注意事项

写回前必须备份：

```sh
cp bmsdb.db bmsdb.db.before_bonio_float_patch
cp bmsdb_slave.db bmsdb_slave.db.before_bonio_float_patch
```

写回后恢复 owner、mode、SELinux context：

```sh
chown foundation:foundation bmsdb.db bmsdb_slave.db
chmod 0660 bmsdb.db bmsdb_slave.db
chcon u:object_r:bms_db_file:s0 bmsdb.db bmsdb_slave.db
```

本机先做 SQLite 完整性校验：

```sql
PRAGMA integrity_check;
```

预期结果：

```text
ok
```

### 5.4 BMS 验证

重启后验证：

```sh
bm dump -n com.axiomaster.bonio | grep SYSTEM_FLOAT_WINDOW -C 3
```

成功时可以看到：

```json
"permissions": [
  "ohos.permission.SYSTEM_FLOAT_WINDOW"
]
```

并且 `reqPermissionDetails`、`reqPermissions` 中都包含该权限。

---

## 6. AccessToken 授权态补丁

### 6.1 数据库位置

AccessToken 数据位于：

```text
/data/service/el1/public/access_token/access_token.db
/data/service/el1/public/access_token/access_token_slave.db
```

关键表：

```sql
hap_token_info_table
permission_state_table
```

先查 Bonio 当前 token：

```sql
select token_id, user_id, bundle_name
from hap_token_info_table
where bundle_name = 'com.axiomaster.bonio';
```

实验设备中 token 为：

```text
537557554
```

### 6.2 补齐授权行

在 `permission_state_table` 中为当前 token 增加或替换：

```sql
insert or replace into permission_state_table
  (token_id, permission_name, device_id, is_general, grant_state, grant_flag)
values
  (537557554, 'ohos.permission.SYSTEM_FLOAT_WINDOW', 'PHONE-001', 1, 0, 4);
```

主库和从库都必须补齐。实验中曾出现主库已有授权行、从库缺失授权行，导致运行时仍报：

```text
Permission ohos.permission.SYSTEM_FLOAT_WINDOW is not granted
```

### 6.3 写回注意事项

写回前备份：

```sh
cp access_token.db access_token.db.before_bonio_float_patch
cp access_token_slave.db access_token_slave.db.before_bonio_float_patch
```

写回前建议清理 WAL/SHM，避免数据库恢复覆盖补丁：

```sh
rm -f access_token.db-wal access_token.db-shm access_token.db-dwr
rm -f access_token_slave.db-wal access_token_slave.db-shm access_token_slave.db-dwr
```

写回后恢复 owner、mode、SELinux context：

```sh
chown access_token:access_token access_token.db access_token_slave.db
chmod 0660 access_token.db access_token_slave.db
chcon u:object_r:accesstoken_data_file:s0 access_token.db access_token_slave.db
```

注意 context 是 `accesstoken_data_file`，不是 `access_token_data_file`。

重启后拉回数据库确认主从库都包含授权行：

```sql
select *
from permission_state_table
where token_id = 537557554
  and permission_name = 'ohos.permission.SYSTEM_FLOAT_WINDOW';
```

预期结果：

```text
537557554|ohos.permission.SYSTEM_FLOAT_WINDOW|PHONE-001|1|0|4
```

---

## 7. 最终验证

### 7.1 App 启动验证

恢复原始可运行 HAP 后，App 应正常启动。日志中不应再出现：

```text
mmap failed, errno[13]. fileName: ets/modules.abc
failed to create js obj
```

### 7.2 浮窗创建验证

点击 Settings 中的 `Enable Cat Overlay` 后，日志中不应再出现：

```text
Permission ohos.permission.SYSTEM_FLOAT_WINDOW is not granted
Failed to create system float window: {"code":201}
```

UI dump 可能只剩一个 200x200 小窗口：

```json
"bounds": "[100,122][300,300]",
"type": "Canvas"
```

WindowManager / RenderService 日志可看到：

```text
CatSystemFloatWindow
```

这表示 `TYPE_FLOAT` 系统级悬浮窗已创建成功。

---

## 8. 已知问题

### 8.1 拖动接口仍需适配

当前浮窗创建成功后，拖动时报：

```text
Failed to start moving float window: {"code":801}
```

说明 `startMoving` 对 `TYPE_FLOAT` 或当前输入事件来源还有额外限制。后续可以尝试：

1. 使用 `moveWindowTo` 自行处理触摸增量。
2. 检查 `setWindowTouchable`、`setWindowFocusable` 与 `startMoving` 的组合限制。
3. 改为通过全局触摸/无障碍事件驱动位置更新。

### 8.2 直接替换 HAP 会破坏启动

不要用 root 直接覆盖已安装的 `entry.hap` 作为常规方案。即使 BMS metadata 可以通过 root 修改，Ark runtime 仍可能因为安装态/XPM/代码签名元数据不一致而拒绝 mmap。

如果误替换导致闪退，应恢复原始 HAP：

```sh
mv entry.hap entry.hap.broken_root_replaced
mv entry.hap.pre_float_rename entry.hap
chown installs:installs entry.hap
chmod 0644 entry.hap
chcon u:object_r:data_app_el1_file:s0 entry.hap
```

### 8.3 数据库写回风险

BMS 和 AccessToken 都是系统关键数据库。写错可能导致包管理、权限服务异常，严重时需要恢复备份或重刷系统。实验操作必须满足：

1. 仅在自有 root 设备上执行。
2. 修改前备份原始数据库。
3. 本地 patch 后先执行 `PRAGMA integrity_check`。
4. 主库和从库保持一致。
5. 写回后恢复 owner、mode、SELinux context。

---

## 9. 工程化脚本方案

当前 root 实验路径已经封装为 HarmonyOS 平台专用脚本：

```text
harmonyos/scripts/float-window-root.ps1
harmonyos/scripts/float_window_patch.py
```

PowerShell 脚本负责设备交互、备份、写回和重启；Python 脚本只处理本地 SQLite/JSON patch，避免在设备 shell 中拼复杂 SQL 和 JSON。

### 9.1 Dry-run

默认不写回设备，只拉取数据库、生成补丁文件并做完整性校验：

```powershell
$env:DEVECO_SDK_HOME = "D:\Program Files\Huawei\DevEco Studio\sdk"
powershell -ExecutionPolicy Bypass -File harmonyos\scripts\float-window-root.ps1
```

输出目录默认位于：

```text
.codex-build/harmonyos-float-window/<timestamp>/
```

其中：

```text
original/        # 从设备拉回的原始 DB
patched/         # 本地 patch 后的 DB
patch-summary.json
```

### 9.2 写回设备

确认 dry-run 输出无误后，显式传入 `-Apply` 才会写回系统数据库：

```powershell
powershell -ExecutionPolicy Bypass -File harmonyos\scripts\float-window-root.ps1 -Apply
```

写回流程会自动完成：

1. 检查 hdc 连接。
2. 检查 shell 是否为 root。
3. 拉取 BMS 与 AccessToken 主/从库。
4. 本地 patch 并执行 `PRAGMA integrity_check`。
5. 上传补丁 DB 到 `/data/local/tmp/bonio_float_window_patch_<timestamp>`。
6. 备份设备原始 DB。
7. 替换 BMS 主/从库并恢复 `foundation:foundation`、`0660`、`bms_db_file`。
8. 替换 AccessToken 主/从库并恢复 `access_token:access_token`、`0660`、`accesstoken_data_file`。
9. 重启设备。

如果需要手动控制重启：

```powershell
powershell -ExecutionPolicy Bypass -File harmonyos\scripts\float-window-root.ps1 -Apply -NoReboot
```

### 9.3 安全约束

脚本默认只允许目标 bundle 为：

```text
com.axiomaster.bonio
```

如果传入其它 bundle，脚本会直接拒绝执行。这样可以避免误 patch 系统包或其它应用。

脚本不会替换已安装的 `entry.hap`。这是刻意设计：实验已经证明 root 直接替换 HAP 可能导致 Ark runtime `mmap errno[13]`，从而启动失败。稳定复现方案只 patch BMS 和 AccessToken 安装/授权态，保留原本可运行的 HAP 文件。

### 9.4 复现验收

设备重启后执行：

```sh
bm dump -n com.axiomaster.bonio | grep SYSTEM_FLOAT_WINDOW -C 3
```

然后启动 Bonio，点击 Settings 中的 `Enable Cat Overlay`。成功时：

1. 不再出现 `Permission ohos.permission.SYSTEM_FLOAT_WINDOW is not granted`。
2. 不再出现 `Failed to create system float window: {"code":201}`。
3. `uitest dumpLayout` 可看到 200x200 左右的浮窗页面。
4. WindowManager / RenderService 日志中可看到 `CatSystemFloatWindow`。
