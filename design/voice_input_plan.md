# Voice Input Implementation Plan: Client-side STT + TTS

## Design Rationale

Voice recognition runs on the client (Android/HarmonyOS) using platform-native streaming APIs, not on the server. This gives the lowest possible latency: the user speaks, partial text appears in real time, and once the user stops, the finalized text is sent via the existing `chat.send` text channel. The server never touches audio.

```
  User -> Client: Press mic / long-press cat
  Client -> Client: Start SpeechRecognizer (streaming)
  loop: User speaks -> Client: onPartialResults -> update UI (real-time)
  User -> Client: Release / silence detected
  Client -> Client: onResults -> final text
  Client -> Server: chat.send (text, sessionKey)
  Server -> LLM: run_streaming_with_history
  LLM -> Server: streaming response
  Server -> Client: chat events (delta/final)
  Client -> Client: TTS.speak(finalText)
  Client -> User: Voice playback
```

## Current State

| Component | Android | HarmonyOS |
|-----------|---------|-----------|
| Voice recording | `VoiceRecorder.kt` - records m4a, Base64 encodes, sends as attachment (server ignores) | Simulated - sends `'[Voice Message]'` text |
| STT | None | None |
| TTS | `SystemTtsManager.kt` - working, uses `android.speech.tts.TextToSpeech` | Not implemented |
| UI trigger | Waveform animation in `ChatComposer` when `AgentState.Listening`, but no real voice flow | Long-press cat avatar in `ChatTab` |

## Phase 1: Android - Replace VoiceRecorder with Streaming SpeechRecognizer

### Task 1.1: Create `SpeechToTextManager.kt`

New file: `android/app/src/main/java/ai/axiomaster/BoJi/remote/chat/SpeechToTextManager.kt`

Wraps `android.speech.SpeechRecognizer` with a clean API:

```kotlin
class SpeechToTextManager(private val context: Context) {
    interface Listener {
        fun onPartialResult(text: String)   // real-time partial transcript
        fun onFinalResult(text: String)     // finalized transcript after silence
        fun onError(errorCode: Int)         // recognition error
        fun onReadyForSpeech()              // mic is active
        fun onEndOfSpeech()                 // silence detected
    }

    fun startListening(listener: Listener, preferOffline: Boolean = false)
    fun stopListening()    // force finalize
    fun cancelListening()  // discard
    fun isListening(): Boolean
    fun destroy()
}
```

Key implementation details:
- Use `SpeechRecognizer.createOnDeviceSpeechRecognizer(context)` when `preferOffline=true` and on-device recognition is available; otherwise fall back to `createSpeechRecognizer(context)` (Google cloud recognizer)
- Set `RecognizerIntent.EXTRA_PARTIAL_RESULTS = true` for streaming partial results
- Set `RecognizerIntent.EXTRA_LANGUAGE` to `Locale.getDefault().toLanguageTag()`
- Handle `RecognitionListener.onPartialResults()` for real-time text, `onResults()` for final text
- Must run on main thread (Android SpeechRecognizer requirement)

### Task 1.2: Wire STT into MainViewModel

Modify: `android/app/src/main/java/ai/axiomaster/BoJi/MainViewModel.kt`

- Add `SpeechToTextManager` instance
- Add `partialSttText: StateFlow<String?>` -- the real-time partial transcript shown in the input area
- Add `startVoiceInput()` / `stopVoiceInput()` / `cancelVoiceInput()` methods
- In `SpeechToTextManager.Listener`:
  - `onPartialResult` -> update `partialSttText`
  - `onFinalResult` -> call `sendChat(finalText, ...)` and clear `partialSttText`
  - `onReadyForSpeech` -> transition agent state to `Listening`
  - `onEndOfSpeech` -> transition to `Thinking`
  - `onError` -> transition to `Idle`, show error

### Task 1.3: Update ChatComposer UI for voice input

Modify: `android/app/src/main/java/ai/axiomaster/BoJi/ui/screens/chat/ChatComposer.kt`

- Add a **mic button** next to the send/add button (visible when input is empty and not typing)
- When mic button is pressed: call `onStartVoice()`
- When `AgentState.Listening`: show the waveform animation (existing) + display `partialSttText` overlaid on the input area so user sees real-time transcript
- Add a stop/cancel button during listening
- When voice finishes: the text auto-sends (handled by ViewModel)

Modify: `android/app/src/main/java/ai/axiomaster/BoJi/ui/screens/ChatTab.kt`

- Pass new voice callbacks (`onStartVoice`, `onStopVoice`, `partialSttText`) through to `ChatComposer`

### Task 1.4: Ensure microphone permission

- Verify `RECORD_AUDIO` is declared in `AndroidManifest.xml`
- Request permission at runtime before starting voice input

## Phase 2: HarmonyOS - Implement STT with CoreSpeechKit

### Task 2.1: Create `SpeechToTextManager.ets`

New file: `harmonyos/entry/src/main/ets/voice/SpeechToTextManager.ets`

Wraps `@kit.CoreSpeechKit` `speechRecognizer`:

```typescript
export interface SttListener {
    onPartialResult(text: string): void
    onFinalResult(text: string): void
    onError(message: string): void
    onReadyForSpeech(): void
    onEndOfSpeech(): void
}

export class SpeechToTextManager {
    startListening(listener: SttListener): void
    stopListening(): void
    cancelListening(): void
    destroy(): void
}
```

Key details:
- Use `speechRecognizer.createEngine()` with `{ language: 'zh-CN', online: 1 }`
- Use `AudioCapturer` from `@kit.AudioKit` to capture PCM (16kHz, mono, 16-bit) and feed to `engine.writeAudio()`
- Parse `onResult` callback for partial vs final results (check `result.isLast`)

### Task 2.2: Wire into ChatTab

Modify: `harmonyos/entry/src/main/ets/pages/ChatTab.ets`

- Replace the simulated `onCatRelease` that sends `'[Voice Message]'` with real STT flow:
  - `onCatPress()` -> `sttManager.startListening()`
  - `onCatRelease()` -> `sttManager.stopListening()`
  - `onFinalResult(text)` -> `chatController.sendMessage(text, ...)`
- Add `@State partialSttText: string` for real-time display during listening
- Show partial text in the UI while listening

### Task 2.3: Implement TTS for HarmonyOS

New file: `harmonyos/entry/src/main/ets/voice/SystemTtsManager.ets`

```typescript
export class SystemTtsManager {
    speak(text: string): void
    stop(): void
    destroy(): void
}
```

Use `@kit.CoreSpeechKit` `textToSpeech` API. Wire `ChatController.onAssistantSpoke` to call `ttsManager.speak()` (same pattern as Android).

## Phase 3: AgentState and Cleanup

### Task 3.1: Update AgentState transitions

Both platforms should follow this state machine for voice:

```
  Idle --> Listening:  mic pressed
  Listening --> Thinking: speech finalized, text sent to server
  Listening --> Idle: cancelled / error
  Thinking --> Speaking: assistant response received
  Speaking --> Idle: TTS completed
```

Ensure:
- `Listening` is entered when STT starts (mic active)
- `Thinking` when final text is sent to server
- `Speaking` when TTS starts
- `Idle` when TTS finishes (add `UtteranceProgressListener` on Android, `onComplete` callback on HarmonyOS)

### Task 3.2: Enhance SystemTtsManager (Android)

The existing `SystemTtsManager.kt` works but lacks a completion callback. Add `UtteranceProgressListener` to notify when speech finishes, so we can transition from `Speaking` -> `Idle`.

### Task 3.3: Deprecate VoiceRecorder for voice input

The existing `VoiceRecorder.kt` records m4a audio and sends as base64 attachment. Keep the class (useful for audio attachments in the future) but remove it from the voice input flow.

## What Does NOT Change

- **Server**: No changes. The server only receives text via `chat.send` and returns text via chat events.
- **Protocol**: No changes. Voice is converted to text client-side before entering the existing `chat.send` flow.
- **SessionStore / chat.history**: No changes. Messages are stored as text.

## Files Summary

| File | Action | Platform |
|------|--------|----------|
| `android/.../chat/SpeechToTextManager.kt` | **Create** | Android |
| `android/.../MainViewModel.kt` | Modify | Android |
| `android/.../ui/screens/chat/ChatComposer.kt` | Modify | Android |
| `android/.../ui/screens/ChatTab.kt` | Modify | Android |
| `android/.../AndroidManifest.xml` | Verify permission | Android |
| `harmonyos/.../voice/SpeechToTextManager.ets` | **Create** | HarmonyOS |
| `harmonyos/.../voice/SystemTtsManager.ets` | **Create** | HarmonyOS |
| `harmonyos/.../pages/ChatTab.ets` | Modify | HarmonyOS |

## Latency Analysis

| Step | Expected Latency |
|------|-----------------|
| User starts speaking -> partial results appear | ~200-500ms (first partial) |
| User stops -> final text ready | ~100-300ms (Android VAD) |
| Text sent via `chat.send` -> server starts LLM | ~50-100ms (WebSocket RTT) |
| LLM first token -> client receives delta | ~500-2000ms (depends on LLM) |
| Final response -> TTS starts playing | ~100-200ms (local TTS init) |
| **Total end-to-end (voice in -> voice out)** | **~1-3s** (dominated by LLM) |

Compared to the whisper.cpp server-side approach which would add 3-5s just for transcription, this client-side approach saves the entire transcription delay.
