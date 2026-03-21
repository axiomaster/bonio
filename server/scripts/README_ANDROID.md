# Android 编译环境配置指南

## 1. 安装 Android NDK

### 方法 A: 通过 Android Studio (推荐)

1. 打开 Android Studio
2. 进入 **Tools → SDK Manager** (或 **Settings → Appearance & Behavior → System Settings → Android SDK**)
3. 切换到 **SDK Tools** 标签
4. 勾选 **Show Package Details**
5. 展开 **NDK (Side by side)**
6. 选择一个版本 (推荐 26.x.x) 并点击 **Apply** 安装
7. 安装完成后，NDK 路径通常在:
   - Windows: `%LOCALAPPDATA%\Android\Sdk\ndk\<version>`
   - Linux/macOS: `~/Android/Sdk/ndk/<version>`

### 方法 B: 命令行安装

```powershell
# 使用 sdkmanager (位于 Android SDK 的 cmdline-tools/bin 目录)
sdkmanager "ndk;26.1.10909125"
```

### 方法 C: 直接下载

1. 访问 https://developer.android.com/ndk/downloads
2. 下载对应平台的 NDK 包
3. 解压到任意目录 (如 `D:\Android\ndk\26.1.10909125`)

## 2. 设置环境变量

### Windows (PowerShell)
```powershell
# 临时设置 (当前会话)
$env:ANDROID_NDK_HOME = "D:\Android\sdk\ndk\26.1.10909125"

# 永久设置 (用户级别)
[Environment]::SetEnvironmentVariable("ANDROID_NDK_HOME", "D:\Android\sdk\ndk\26.1.10909125", "User")
```

### Windows (CMD)
```cmd
REM 临时设置
set ANDROID_NDK_HOME=D:\Android\sdk\ndk\26.1.10909125

REM 永久设置 (需要管理员权限)
setx ANDROID_NDK_HOME "D:\Android\sdk\ndk\26.1.10909125"
```

### Linux/macOS
```bash
# 临时设置
export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.1.10909125

# 永久设置 (添加到 ~/.bashrc 或 ~/.zshrc)
echo 'export ANDROID_NDK_HOME=~/Android/Sdk/ndk/26.1.10909125' >> ~/.bashrc
source ~/.bashrc
```

## 3. 验证环境

```powershell
# 运行环境检查脚本
cd d:\projects\boji\server
scripts\check-env.bat
```

## 4. 编译

```powershell
# 设置 NDK 路径 (根据你的实际安装路径修改)
set ANDROID_NDK_HOME=%LOCALAPPDATA%\Android\Sdk\ndk\26.1.10909125

# 编译 (默认 arm64-v8a)
scripts\build-android.bat

# 或指定其他 ABI
set ANDROID_ABI=armeabi-v7a
scripts\build-android.bat

# 或编译所有架构
scripts\build-android-all.bat
```

## 5. 部署到设备

```powershell
# 确保设备已连接并开启 USB 调试
adb devices

# 部署
scripts\deploy-android.bat

# 手动部署
adb push build-android-arm64-v8a\hiclaw /data/local/tmp/
adb shell chmod +x /data/local/tmp/hiclaw
adb shell /data/local/tmp/hiclaw --version
```

## 常见问题

### Q: 编译时报 "CMake not found"
A: NDK 自带 CMake，但需要确保路径正确。也可以安装系统级 CMake:
```powershell
winget install Kitware.CMake
```

### Q: 编译时报 "Ninja not found"
A: NDK 自带 Ninja。如果仍报错，可以安装系统级 Ninja:
```powershell
winget install Ninja-build.Ninja
```

### Q: 如何选择 ABI?
A:
- `arm64-v8a`: 64位 ARM 设备 (现代手机，推荐)
- `armeabi-v7a`: 32位 ARM 设备 (旧手机)
- `x86_64`: 64位 Intel 模拟器

### Q: 如何选择 API Level?
A: 默认 API 24 (Android 7.0) 适用于绝大多数设备。如需支持更老的设备:
```powershell
set ANDROID_API_LEVEL=21
```

## 输出目录

编译产物位于:
- `build-android-arm64-v8a/hiclaw` - ARM 64位
- `build-android-armeabi-v7a/hiclaw` - ARM 32位
- `build-android-x86_64/hiclaw` - x86 64位
