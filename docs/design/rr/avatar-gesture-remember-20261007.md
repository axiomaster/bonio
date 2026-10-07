# Raw PRD:Avatar 手势重定义与语音交互移除

- 日期:2026-10-07
- 来源:用户口头设计意图(会话转写,未改动语义)
- 状态:已实现(Android 端)

## 原始需求(用户原话要点)

我考虑了一下,需要放弃掉语音交互功能:

1. 之前长按 avatar,会触发语音输入识别,这个功能放弃;修改为长按触发记录屏幕:长按 avatar 后触发截屏,等截屏存储后 avatar 提示"已记住"并播放对应动画,就可以结束了。
2. 用户双击 avatar,也会触发截屏记录功能,但核心是分析屏幕内容,给出类似 magic_cue 的推荐体验;如果有,则从侧边给出建议项;如果没有,就在头顶显示类似暂无建议的提示。

## 澄清结论(会话中确认)

| 问题 | 决定 |
|------|------|
| 语音移除范围 | **STT 与 TTS 全部移除**(先确认只移除语音输入,后补充"TTS 播报也请移除");avatar 反馈只剩气泡与动画 |
| 长按"记住"的含义 | 截图**本地保存**(应用私有目录)+ **交给 agent 后端存为记忆**(可在聊天中追问) |
| 双击分析链路 | **复用现有 magic cue 链路**(截屏 → screen.context(无障碍优先/OCR 降级)→ LLM 建议),仅改触发方式与展示 |
| 服务端 | 不改动;Android 停发 `stt.final_result`,服务端 TTS 类命令/事件在端上优雅降级(`call.tts` 立即回 `call.tts.done` 保住来电流程时序) |

## 交互定义(实现口径)

- **长按(600ms)**:Thinking + 快门动画(TakingPhoto)→ 截图 → 本地存 `filesDir/screenshots/` + companionMemory.capture(explicit)兜底 memo.save → 成功后侧边气泡"已记住"+ Happy 动画;失败 Confused + 错误提示。
- **双击(300ms 窗口)**:截屏分析 → 有建议:侧边 capsule 逐条列出建议项(最多 2 条,点击发送);无建议:头顶"暂无建议"。双击不再写记忆(记忆职责归长按)。
- **移除**:聊天麦克风、扬声器开关、avatar 点按说话、来电语音应答(call.stt)、来电 TTS 播报、语音唤醒空壳、相关权限声明(FOREGROUND_SERVICE_MICROPHONE)与 i18n 文案。

## 实现记录

- 主改动:`android/.../FloatingWindowService.kt`(rememberScreen / runMagicCue 改造 / 多建议项 capsule / STT·TTS 摘除)
- 其余:CallEventHandler、MainViewModel、ChatController、ChatTab、ChatComposer、SettingsTab、AvatarCommandExecutor、SecurePrefs、ConnectionManager、InvokeCommandRegistry、Manifest、AppLanguage;删除 SpeechToTextManager / VoiceRecorder / SystemTtsManager / HealthNagScheduler / ScreenSuggestionRules / VoiceWakeMode / WakeWords。
- refined PRD / arch 文档:本次改动规模可控、复用既有链路,未单独产出(如需可后补)。
