# phone-use-harmonyos

HarmonyOS 设备上运行的 GUI Agent 工具，编译为二进制文件直接在 HarmonyOS 设备内运行。

## 项目背景

参考项目 [Open-AutoGLM](reference/Open-AutoGLM) 实现了完整的 GUI-Agent，支持 HarmonyOS 设备。但 Open-AutoGLM 需要在 PC 上运行，通过 hdc 命令操作设备。

本项目实现了在 HarmonyOS 设备上原生运行的 GUI Agent，无需 PC 端参与，响应更快、延迟更低。

## 功能特性

- 接收自然语言任务描述
- 使用 GLM 大模型理解屏幕内容并规划操作
- 支持多种 UI 操作：点击、滑动、输入、启动应用等
- CLI 命令行接口，易于集成

## 编译

### 环境要求

- OpenHarmony NDK: `D:/tools/commandline-tools-windows/sdk/default/openharmony/native`
- 交叉编译目标: `aarch64-linux-ohos`

### 编译命令

```bash
# 配置
cmake -B build -G Ninja -DCMAKE_MAKE_PROGRAM="D:/tools/commandline-tools-windows/sdk/default/openharmony/native/build-tools/cmake/bin/ninja.exe"

# 编译
D:/tools/commandline-tools-windows/sdk/default/openharmony/native/build-tools/cmake/bin/ninja.exe -C build

# 输出文件
# build/bin/phone-use-harmonyos  - 主程序
# build/bin/test_*               - 测试程序
```

## 部署

```bash
# 使用 PowerShell 部署
hdc file send 'build\bin\phone-use-harmonyos' '/data/local/bin/phone-use-harmonyos'
hdc shell 'chmod +x /data/local/bin/phone-use-harmonyos'
```

## 使用方法

```bash
# 查看帮助
/data/local/bin/phone-use-harmonyos --help

# 执行任务
/data/local/bin/phone-use-harmonyos --apikey "your-bigmodel-api-key" --task "打开美团搜索附近的火锅店"

# 详细输出模式
/data/local/bin/phone-use-harmonyos --apikey "sk-xxx" --task "打开微信" --verbose

# 设置超时
/data/local/bin/phone-use-harmonyos --apikey "sk-xxx" --task "截图" --timeout 60
```

### 命令行参数

| 参数 | 说明 | 必需 |
|------|------|------|
| `--apikey` | BigModel API 密钥 | 是 |
| `--task` | 任务描述（中文） | 是 |
| `--timeout` | 超时时间（秒），默认 30 | 否 |
| `--verbose` | 详细输出模式 | 否 |
| `--help, -h` | 显示帮助信息 | 否 |
| `--version` | 显示版本号 | 否 |

### 退出码

| 代码 | 含义 |
|------|------|
| 0 | 任务成功完成 |
| 1 | 通用错误 |
| 2 | 参数无效 |
| 4 | 任务执行失败 |
| 5 | 超时（超过 20 步） |
| 10 | 网络错误 |
| 11 | 初始化失败 |

## 支持的操作

| 操作 | 示例 |
|------|------|
| 点击 | 点击屏幕上的按钮 |
| 滑动 | 向上滑动浏览列表 |
| 输入 | 在输入框中输入文字 |
| 长按 | 长按某元素 |
| 启动应用 | 打开微信 |
| 返回 | 返回上一页 |
| 主页 | 返回主屏幕 |
| 等待 | 等待页面加载 |

## 配置文件

配置文件路径: `/data/local/.phone-use-harmonyos/phone-use-harmonyos.conf`

```json
{
  "glm_api_key": "your-bigmodel-api-key",
  "glm_endpoint": "https://open.bigmodel.cn/api/paas/v4/chat/completions",
  "system_prompt": "You are a phone automation assistant..."
}
```

## 技术实现

- 使用 `snapshot_display` 命令截屏（0.5x 尺寸以节省带宽）
- 使用 `/bin/uitest uiInput` 命令执行 UI 操作
- 使用 GLM 视觉模型理解屏幕内容
- 使用 musl libc（需使用 `usleep()` 替代 `std::this_thread::sleep_for`）

## 项目结构

```
├── src/
│   ├── main.cpp           # CLI 入口
│   ├── CliArgs.cpp        # 命令行参数解析
│   ├── TaskExecutor.cpp   # 任务执行器（Agent 循环）
│   ├── UIInspector.cpp    # 屏幕截图
│   ├── AutoGLMClient.cpp  # GLM API 客户端
│   ├── AppManager.cpp     # 应用启动管理
│   ├── HttpClient.cpp     # HTTP 网络请求
│   └── ConfigManager.cpp  # 配置管理
├── include/               # 头文件
├── test/                  # 测试代码
└── reference/             # 参考实现
```

## 许可证

MIT License
