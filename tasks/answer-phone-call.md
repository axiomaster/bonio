自动接听电话功能

boji需要监听系统的来电通知，当有来电后，boji识别来电的人，如果来电号码被标记为广告、诈骗等内容，boji语音提示用户是否挂断，同时avatar头顶上有个10s的倒计时，avatar跑动到挂断按钮旁边；

倒计时完成，或者用户语音给出挂断等答复后，boji播放动画，点击挂断按钮，同时挂断电话；

如果是正常电话，boji语音提示用户，xxx来电话了，是否要接听，同时avatar跑到接听按钮旁边，同时avatar头顶上有个10s的倒计时；
倒计时完成前，如果用户答复接听，则avatar播放动画，点击接听按钮；如果用户答复挂断，则avatar移动到挂断按钮，点击挂断；如果倒计时完成，则挂断；

## 技术方案：Skill/Prompt 驱动的来电处理

### 目标
将来电处理逻辑从 `call_handler.cpp` 的硬编码流程迁移到由 LLM（通过 prompt/skill）驱动，使得：
- TTS 话术由模型生成，更自然、可个性化
- 是否接听/挂断的决策逻辑可以更智能（如根据上下文判断）
- 骚扰电话识别可以结合模型推理

### 架构设计

#### 1. 来电 Skill 定义
创建 `skills/call-handler/` skill，包含 system prompt：
```
你是BoJi，一个可爱的猫猫助手。当主人有电话打进来时，你需要：
1. 告诉主人谁在打电话（用可爱的语气）
2. 如果是骚扰电话，建议主人挂掉
3. 等待主人语音回复（接听/挂断）
4. 执行对应操作
```

#### 2. 来电专用 Tools
为 LLM 提供以下工具：
- `call.speak(text)` → 发送 `call.tts` 事件给客户端
- `call.listen()` → 发送 `call.stt.start`，等待用户语音结果
- `call.answer()` → 发送 `call.action` 事件 `{"action":"answer"}`
- `call.reject()` → 发送 `call.action` 事件 `{"action":"reject"}`
- `call.get_info()` → 返回来电号码、联系人名称、是否骚扰标记

#### 3. 集成方式
在 `CallHandler::run_call_flow()` 中：
```cpp
// 构建来电上下文消息
std::string message = "来电通知: " + display + " (号码:" + number + ", 骚扰:" + (is_spam ? "是" : "否") + ")";
// 使用 agent_manager 启动异步任务，skill 为 call-handler
agent_manager->start_task("__call_handler__", message);
```

#### 4. 工具执行
LLM 调用 `call.speak/listen/answer/reject` 时，通过 `ToolRouter` 路由到 `CallHandler` 的对应方法，产生 WebSocket 事件发送至客户端。
