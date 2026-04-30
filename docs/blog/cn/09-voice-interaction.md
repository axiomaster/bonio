# 语音交互：从听到说到理解

> Bonio 不仅能听懂你在说什么，还能判断你"想干什么"——是闲聊、是截屏、还是接电话。全程本地处理，低延迟，隐私安全。

---

## 语音管线的三层架构

Bonio 的语音系统是一个完整的"听→理解→说"闭环：

```
┌──────────────────────────────────────────────────────────┐
│                      语音管线                             │
│                                                          │
│  输入层 (STT)         理解层 (Intent)        输出层 (TTS) │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────┐  │
│  │ Sherpa-ONNX  │───▶│ IntentRouter │───▶│ DesktopTts │  │
│  │ Paraformer   │    │ (服务端分类)  │    │ (平台TTS)  │  │
│  │ 流式 ASR     │    │              │    │            │  │
│  └──────────────┘    └──────────────┘    └────────────┘  │
│                                                          │
│  ┌──────────────┐                                       │
│  │ 麦克风 (FFI)  │  Win32 waveIn / macOS CoreAudio       │
│  └──────────────┘                                       │
└──────────────────────────────────────────────────────────┘
```

---

## STT：为什么选择本地离线方案

Bonio 的语音识别使用 **Sherpa-ONNX 流式 Paraformer**——一个中英双语的离线 ASR 模型。

| 对比维度 | 云端 ASR（Whisper API 等） | Sherpa-ONNX（Bonio 的选择） |
|---------|--------------------------|---------------------------|
| **延迟** | 网络往返 + 处理 (>500ms) | 本地推理 (<100ms) |
| **隐私** | 音频上传到第三方服务器 | 音频不离开你的机器 |
| **网络依赖** | 必须有网 | 完全离线 |
| **成本** | 按调用量收费 | 零成本 |
| **模型大小** | N/A | ~50MB（encoder + decoder） |

Sherpa-ONNX 的 Paraformer 模型支持**流式识别**——不需要等你说完才开始转文字。音频以 100ms 的 buffer 推入识别器，实时产出 partial 结果（显示在 Avatar 气泡中），语音结束后产出 final 结果，发送给 LLM。

这跟 Android 端的实现完全一致——桌面端和移动端共享同一个模型文件和识别引擎（通过 `sherpa_onnx` FFI 绑定）。

### 麦克风捕获：绕过 Flutter 的坑

Flutter 桌面端的麦克风采集有个经典问题：如果使用 Flutter 的 platform channel 调用原生麦克风 API，在多引擎场景下（Bonio 有两个 Flutter 引擎），`MethodChannel` 的响应会找不到正确的引擎，抛出 `MissingPluginException`。

Bonio 的解决方案：**直接用 dart:ffi 调 Win32 waveIn API**，绕过所有中间层。

```
SherpaOnnxSpeechManager (Dart)
  └─ Win32Microphone (dart:ffi)
       └─ waveInOpen / waveInAddBuffer / waveInStart (Win32 API)
            └─ 每 20ms 轮询 WHDR_DONE 标志
                 └─ 取 PCM16 16kHz 单声道数据 → 喂入 Sherpa-ONNX
```

`waveIn` 使用 `CALLBACK_NULL` 轮询模式而非回调模式——因为 Win32 音频回调跑在原生线程上，Flutter 的 isolate 无法从原生线程安全地调用 Dart 方法。通过 Dart timer 每 20ms 轮询 buffer 状态，避免了跨线程通信的崩溃风险。

---

## TTS：零依赖的多平台方案

Bonio 的语音合成同样避开 native plugin 的依赖：

| 平台 | 实现 | 命令 |
|------|------|------|
| **Windows** | PowerShell + System.Speech.Synthesis (SAPI) | `PowerShell -Command "Add-Type -AssemblyName System.Speech; ..."` |
| **macOS** | `/usr/bin/say` | `say -v Tingting -o /tmp/tts.aiff -f /tmp/tts.txt` |
| **Linux** | espeak-ng / spd-say（检测 PATH 可用性） | `espeak-ng -v zh` |

全部通过 `Process.start()` 调用，**零 native plugin 依赖**。不使用 `flutter_tts` 的原因很简单——那个插件在 Windows 上需要 CMake 和 NuGet 的额外配置，对于"只想要声音"的需求来说太重了。

TTS 的使用场景：
- AI 回复朗读（可在设置中开关）
- 来电时的 TTS 播报（"张三来电，是否接听？"）
- 健康提醒的 TTS 播报（"已经很晚了，该休息了"）
- 服务端 `avatar.command` 的 `tts` 指令

---

## 意图路由：语音不只是"语音转文字"

很多人以为语音交互就是"把说的话转成文字然后当聊天消息发出去"。Bonio 比这多了一层：**意图分类**。

服务端的 `IntentRouter` 在收到 STT 最终结果后，先判断用户**想干什么**，再做不同的事情：

| 意图 | 分类方法 | 处理方式 |
|------|---------|---------|
| **Chat** | 不匹配任何特殊模式 | 作为普通聊天消息发送给 LLM |
| **ScreenCapture** | 包含"截屏"/"截图"/"截个图" 等关键词 | 发送 `avatar.command` 触发截图 |
| **Summarize** | 包含"总结"/"归纳"/"概括" + 与当前窗口相关 | 发送 `avatar.command` 触发截图 + 总结 |
| **CallAnswer** | 包含"接"/"接听"/"接电话" 等 | 发送 `call.action: answer` |
| **CallReject** | 包含"挂"/"挂断"/"不接" 等 | 发送 `call.action: reject` |

```cpp
// IntentRouter 的关键词匹配逻辑（简化）
Intent classify_intent(const std::string& text) {
  if (contains_any(text, {"截屏", "截图", "截个图", "screen", "capture"}))
    return Intent::ScreenCapture;
  if (contains_any(text, {"总结", "归纳", "概括", "summarize", "摘要"}))
    return Intent::Summarize;
  if (contains_any(text, {"接", "接听", "接电话", "answer", "yes"}))
    return Intent::CallAnswer;
  if (contains_any(text, {"挂", "挂断", "不接", "reject", "no", "拒接"}))
    return Intent::CallReject;
  return Intent::Chat;
}
```

这层"理解"让语音交互从"替代打字"升级为"直接操控应用"。你说"截个图"，Bonio 不会傻傻地把这三个字发给 LLM 聊天——它会直接执行截图操作。

---

## 来电处理：AI 接电话

`CallHandler` 是一个专门处理来电的服务端子模块。它的工作流：

```
手机端检测到来电
  → nodeSession 发送 call.incoming 事件
  → CallHandler 接收
  → 查询号码是否为骚扰电话（本地规则匹配）
  → 如果不是：
      → 通过 TTS 在桌面播报："张三来电，是否接听？说出'接'或'挂断'"
      → 启动 30 秒倒计时
      → 通过 STT 听取用户的语音指令
      → IntentRouter 分类为 CallAnswer 或 CallReject
      → 发送 call.action 事件回手机端执行
  → 如果是骚扰电话：
      → 自动发送 call.action: reject（静默挂断）
```

骚扰检测通过两种方式：
- **号码匹配**：本地维护的骚扰号码规则
- **联系人名称启发式**：包含"骚扰"、"推销"、"广告"、"诈骗"等关键词的自动拒接

整个过程完全离线，不需要把电话号码上传到任何云服务。

---

## 健康守护：屏幕时间提醒

`HealthMonitor` 是一个安静的守护者。它追踪手机端上报的屏幕状态（通过 `device.status` 事件），在深夜时段（23:00 - 6:00）如果用户连续使用超过 2 小时，通过 Avatar 的 TTS 发送提醒：

- **第一次**（温和提醒）："已经比较晚了，记得休息眼睛哦~"
- **第二次**（加强提醒）：15 分钟后如果还在用，提醒语气升级

这不是强制锁屏或家长式管控——只是一个"朋友式的唠叨"。15 分钟冷却时间确保不会频繁打扰。

---

*下一篇：[微信集成：用手机指挥桌面AI](10-wechat-integration.md)*
