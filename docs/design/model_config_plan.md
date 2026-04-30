# Model/Provider 配置功能实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 Android 客户端中增加 model/provider 配置页面，允许用户手动选择和配置 model/provider，设置保存到服务端。

**Created:** 2026-03-17

**Total Tasks:** 6 (2 server + 4 android)

---

## 设计原则

1. **API 结构与 `hiclaw.json` 一致** - 使用 snake_case 字段名
2. **`providers` 是只读元数据** - 内置常量，作为 `config.get` 的子字段返回
3. **`models` 是用户配置** - 可读写，存储在 `hiclaw.json`
4. **单一 `config.get` 接口** - 返回所有配置信息，减少请求次数

---

## 背景

### 当前服务端支持的接口

| 接口 | 说明 | 状态 |
|------|------|------|
| `connect` | 认证连接 | ✅ |
| `health` | 健康检查 | ✅ |
| `config.get` | 获取配置 | ⚠️ 不完整（仅返回 node 版本和 default_model） |
| `voicewake.get/set` | 语音唤醒设置 | ✅ |
| `chat.send` | 发送消息 | ✅ |
| `chat.history` | 获取历史 | ✅ |
| `sessions.list` | 会话列表 | ✅ |
| `chat.subscribe` | 订阅会话 | ✅ |
| `node.invoke.result` | 工具调用结果 | ✅ |

### 当前配置结构 (hiclaw.json)

```json
{
  "default_model": "llama3.2",
  "models": [
    {
      "id": "llama3.2",
      "provider": "ollama",
      "base_url": "http://localhost:11434",
      "model_id": "llama3.2",
      "api_key_env": "",
      "api_key": ""
    }
  ],
  "gateway": {
    "port": 8765,
    "host": "0.0.0.0",
    "enabled": true,
    "pairing_code": ""
  }
}
```

### 内置 Provider 列表

| ID | Display Name | Default Base URL | API Key Env |
|----|--------------|------------------|-------------|
| ollama | Ollama | http://localhost:11434 | - |
| openai | OpenAI | https://api.openai.com/v1 | OPENAI_API_KEY |
| anthropic | Anthropic | https://api.anthropic.com/v1 | ANTHROPIC_API_KEY |
| glm | GLM | https://open.bigmodel.cn/api/paas/v4 | GLM_API_KEY |
| minimax | MiniMax | https://api.minimaxi.com/v1 | MINIMAX_API_KEY |
| qwen | Qwen | https://dashscope.aliyuncs.com/compatible-mode/v1 | DASHSCOPE_API_KEY |
| kimi | Kimi | https://api.moonshot.cn/v1 | KIMI_API_KEY |
| gemini | Gemini | https://generativelanguage.googleapis.com/v1beta | GEMINI_API_KEY |
| openai_compatible | Custom | - | OPENAI_API_KEY |

---

## Phase 1: 服务端接口增强

### 设计原则

1. **API 结构与 `hiclaw.json` 一致** - 使用相同的字段名和嵌套结构
2. **`providers` 是只读元数据** - 内置常量，供 UI 选择 Provider 用
3. **`models` 是用户配置** - 可读写，存储在 `hiclaw.json`
4. **单一 `config.get` 接口** - 返回所有配置信息，避免多次请求

---

### Task 1: 增强 `config.get` 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`

**目标:** 返回完整配置，结构与 `hiclaw.json` 一致，额外包含 `providers` 元数据

**当前实现:**
```cpp
if (method == "config.get") {
  json res;
  res["type"] = "res";
  res["id"] = id;
  res["ok"] = true;
  res["payload"] = {
    {"node", {{"version", "0.1.0"}, {"platform", "server"}}},
    {"connection", {{"status", connected ? "connected" : "disconnected"}}},
    {"model", {{"default", config.default_model}}}
  };
  return res.dump();
}
```

**修改后返回格式（与 hiclaw.json 结构一致）:**
```json
{
  "type": "res",
  "ok": true,
  "payload": {
    "default_model": "llama3.2",
    "models": [
      {
        "id": "llama3.2",
        "provider": "ollama",
        "base_url": "http://localhost:11434",
        "model_id": "llama3.2"
      }
    ],
    "gateway": {
      "port": 8765,
      "host": "0.0.0.0",
      "enabled": true
    },
    "providers": [
      {"id": "ollama", "display_name": "Ollama", "requires_api_key": false, "default_base_url": "http://localhost:11434"},
      {"id": "openai", "display_name": "OpenAI", "requires_api_key": true, "default_base_url": "https://api.openai.com/v1"},
      {"id": "glm", "display_name": "GLM", "requires_api_key": true, "default_base_url": "https://open.bigmodel.cn/api/paas/v4"}
    ]
  }
}
```

**字段说明:**
- `default_model`, `models`, `gateway`: 与 `hiclaw.json` 结构完全一致
- `providers`: 只读元数据，来自内置常量，供 UI 选择用

---

### Task 2: 添加 `config.set` 接口

**Files:**
- Modify: `server/src/net/gateway.cpp`
- Modify: `server/include/hiclaw/config/config.hpp` (可能需要添加热更新支持)

**功能:**
- 更新 `default_model`
- 更新/添加/删除 `models[]` 条目
- 更新 `gateway` 配置（可选）
- 保存到 `hiclaw.json`

**请求格式（与 hiclaw.json 结构一致）:**
```json
{
  "method": "config.set",
  "id": "1",
  "params": {
    "default_model": "glm-4",
    "models": [
      {
        "id": "glm-4",
        "provider": "glm",
        "base_url": "",
        "model_id": "glm-4",
        "api_key": "xxx"
      }
    ]
  }
}
```

**响应格式:**
```json
{
  "type": "res",
  "id": "1",
  "ok": true,
  "payload": {
    "default_model": "glm-4",
    "saved": true
  }
}
```

**实现要点:**
1. 解析 params 中的 `default_model`、`models`、`gateway`
2. 更新内存中的 Config 对象
3. 调用 `config::save()` 持久化到 `hiclaw.json`
4. 返回更新后的配置

**注意:** 需要将 Config 对象改为可修改的（当前在 gateway 中是 const 引用）

---

### ~~Task 3: 添加 `providers.list` 接口~~

**已取消** - `providers` 作为 `config.get` 的子字段返回，不需要单独接口
```

---

## Phase 2: Android 客户端配置页面

### Task 3: 创建配置数据类

**Files:**
- Create: `android/app/src/main/java/ai/axiomaster/BoJi/remote/config/ProviderInfo.kt`
- Create: `android/app/src/main/java/ai/axiomaster/BoJi/remote/config/ModelConfig.kt`
- Create: `android/app/src/main/java/ai/axiomaster/BoJi/remote/config/ServerConfig.kt`

**ProviderInfo.kt:**
```kotlin
package ai.axiomaster.BoJi.remote.config

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProviderInfo(
    val id: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("requires_api_key") val requiresApiKey: Boolean = true,
    @SerialName("default_base_url") val defaultBaseUrl: String = ""
)
```

**ModelConfig.kt:**
```kotlin
package ai.axiomaster.BoJi.remote.config

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ModelConfig(
    val id: String,
    val provider: String,
    @SerialName("base_url") val baseUrl: String? = null,
    @SerialName("model_id") val modelId: String? = null,
    @SerialName("api_key") val apiKey: String? = null
)
```

**ServerConfig.kt:**
```kotlin
package ai.axiomaster.BoJi.remote.config

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ServerConfig(
    @SerialName("default_model") val defaultModel: String,
    val models: List<ModelConfig> = emptyList(),
    val providers: List<ProviderInfo> = emptyList(),
    val gateway: GatewayConfig? = null
)

@Serializable
data class GatewayConfig(
    val port: Int = 8765,
    val host: String = "0.0.0.0",
    val enabled: Boolean = true
)
```

---

### Task 4: 创建 ConfigRepository

**Files:**
- Create: `android/app/src/main/java/ai/axiomaster/BoJi/remote/config/ConfigRepository.kt`

**功能:**
- `getConfig()`: 调用 `config.get`，返回 ServerConfig（包含 providers）
- `setConfig(defaultModel, models)`: 调用 `config.set`，更新配置

**ConfigRepository.kt:**
```kotlin
package ai.axiomaster.BoJi.remote.config

import ai.axiomaster.BoJi.remote.gateway.GatewaySession
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

class ConfigRepository(private val session: GatewaySession) {

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /**
     * Get full config from server, including providers metadata
     */
    suspend fun getConfig(): Result<ServerConfig> = withContext(Dispatchers.IO) {
        try {
            val response = session.request("config.get", buildJsonObject { })
            if (!response.ok) {
                return@withContext Result.failure(Exception(response.error ?: "Unknown error"))
            }

            val payload = response.payload
            val config = json.decodeFromJsonElement(ServerConfig.serializer(), payload)
            Result.success(config)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Update config on server (saves to hiclaw.json)
     */
    suspend fun setConfig(
        defaultModel: String? = null,
        models: List<ModelConfig>? = null
    ): Result<Boolean> = withContext(Dispatchers.IO) {
        try {
            val params = buildJsonObject {
                if (defaultModel != null) {
                    put("default_model", defaultModel)
                }
                if (models != null) {
                    put("models", json.encodeToJsonElement(models))
                }
            }

            val response = session.request("config.set", params)
            if (!response.ok) {
                return@withContext Result.failure(Exception(response.error ?: "Unknown error"))
            }

            Result.success(true)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
```

---

### Task 5: 创建 ModelConfigScreen UI

**Files:**
- Create: `android/app/src/main/java/ai/axiomaster/BoJi/ui/screens/ModelConfigScreen.kt`

**UI 设计:**

```
┌─────────────────────────────────────┐
│ ← Model Configuration               │
├─────────────────────────────────────┤
│                                     │
│ Provider                            │
│ ┌─────────────────────────────────┐ │
│ │ GLM                         ▼   │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Model ID                            │
│ ┌─────────────────────────────────┐ │
│ │ glm-4                           │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Base URL (Optional)                 │
│ ┌─────────────────────────────────┐ │
│ │ https://open.bigmodel.cn/...    │ │
│ └─────────────────────────────────┘ │
│                                     │
│ API Key                             │
│ ┌─────────────────────────────────┐ │
│ │ ••••••••••••••••••••••         │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌─────────────────────────────────┐ │
│ │           Save                  │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ───────── Current Models ───────── │
│                                     │
│ ● llama3.2 (ollama)        [Edit]  │
│ ○ glm-4 (glm)              [Edit]  │
│                                     │
└─────────────────────────────────────┘
```

**UI 元素:**
1. Provider 下拉选择（从 providers 列表）
2. Model ID 输入框
3. Base URL 输入框（可选，默认使用 Provider 的 default_base_url）
4. API Key 输入框（密码类型，仅当 provider.requires_api_key = true 时显示）
5. 保存按钮
6. 当前已配置的 Model 列表（从 models[]）

---

### Task 6: 集成到 ServerTab

**Files:**
- Modify: `android/app/src/main/java/ai/axiomaster/BoJi/ui/screens/ServerTab.kt`

**功能:**
1. 显示当前 Model/Provider 配置摘要
2. 点击进入 ModelConfigScreen 配置页面
3. 支持快速切换当前使用的 Model

**ServerTab 显示内容:**
```
┌─────────────────────────────────────┐
│ Server Status: Connected            │
│ ─────────────────────────────────── │
│ Current Model: glm-4                │
│ Provider: GLM                       │
│ ─────────────────────────────────── │
│ [Configure Models...]               │
└─────────────────────────────────────┘
```

---

## 依赖关系

```
Phase 1 (Server):
Task 1 (config.get) ──┐
Task 2 (config.set) ──┴──> 需要先完成

Phase 2 (Android):
Task 3 (数据类) ──> Task 4 (Repository) ──> Task 5 (UI) ──> Task 6 (集成)
         ↑                                           ↑
         └─────────── 依赖 Phase 1 ──────────────────┘
```

---

## 接口设计总结

| 接口 | 方法 | 说明 |
|------|------|------|
| `config.get` | 只读 | 返回完整配置 + providers 元数据 |
| `config.set` | 写入 | 更新 default_model, models[], gateway |

**字段命名约定:** 使用 snake_case（与 hiclaw.json 一致）
- `default_model` (not `defaultModel`)
- `base_url` (not `baseUrl`)
- `model_id` (not `modelId`)
- `api_key` (not `apiKey`)

---

## 测试计划

### 服务端测试

```bash
# 1. 测试 config.get（返回完整配置 + providers）
wscat -c ws://localhost:8765
> {"method": "connect", "id": "1", "params": {"password": ""}}
> {"method": "config.get", "id": "2"}
# 期望: 返回 default_model, models[], gateway{}, providers[]

# 2. 测试 config.set（更新配置）
> {"method": "config.set", "id": "3", "params": {"default_model": "glm-4", "models": [{"id": "glm-4", "provider": "glm", "api_key": "test-key"}]}}
# 期望: 返回 ok=true, saved=true

# 3. 验证配置已保存
> {"method": "config.get", "id": "4"}
# 期望: default_model = "glm-4", models 包含 glm-4
```

### Android 测试

1. 启动 APP，连接服务端
2. 进入 Server Tab，查看当前 Model 显示
3. 点击 "Configure Models" 进入配置页面
4. 选择 Provider（如 GLM）
5. 输入 Model ID 和 API Key
6. 点击保存
7. 验证配置已保存到服务端（重新打开配置页面查看）
8. 发送消息验证使用新配置的 Model

---

## 参考文件

| 功能 | 文件路径 |
|------|---------|
| Gateway 协议处理 | `server/src/net/gateway.cpp` |
| 配置结构定义 | `server/include/hiclaw/config/config.hpp` |
| Provider 列表 | `server/include/hiclaw/config/default_providers.hpp` |
| 配置加载/保存 | `server/src/config/config.cpp` |
| Android Gateway 会话 | `android/.../remote/gateway/GatewaySession.kt` |
| Android Server Tab | `android/.../ui/screens/ServerTab.kt` |
