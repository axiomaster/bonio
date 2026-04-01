# Replace Vosk with Sherpa-ONNX Speech Recognition

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Vosk offline speech recognition with Sherpa-ONNX + Paraformer model for significantly better Chinese ASR accuracy, on both Android and HarmonyOS.

**Architecture:** Keep the existing dual-layer STT architecture (system STT primary, on-device fallback). Replace the Vosk fallback layer with Sherpa-ONNX using the streaming Paraformer bilingual model. The `SpeechToTextManager` interface stays the same — only the internal `VoskSpeechManager` is swapped out for a new `SherpaOnnxSpeechManager`. Android uses native JNI libraries; HarmonyOS uses the OHPM `.har` package.

**Tech Stack:** Sherpa-ONNX v1.12.34, Paraformer streaming bilingual (zh-en) model, ONNX Runtime

---

## Task 1: Download and integrate Sherpa-ONNX native libraries (Android)

**Files:**
- Create: `android/app/src/main/jniLibs/arm64-v8a/libsherpa-onnx-jni.so`
- Create: `android/app/src/main/jniLibs/arm64-v8a/libonnxruntime.so`
- Modify: `android/app/build.gradle.kts`

**Step 1: Download Sherpa-ONNX Android native libraries**

```bash
cd /tmp
curl -L -o sherpa-onnx-android.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.12.34/sherpa-onnx-v1.12.34-android.tar.bz2
tar xvf sherpa-onnx-android.tar.bz2
```

**Step 2: Copy native libraries to jniLibs**

```bash
mkdir -p d:/projects/boji/android/app/src/main/jniLibs/arm64-v8a
cp /tmp/sherpa-onnx-android/arm64-v8a/libsherpa-onnx-jni.so d:/projects/boji/android/app/src/main/jniLibs/arm64-v8a/
cp /tmp/sherpa-onnx-android/arm64-v8a/libonnxruntime.so d:/projects/boji/android/app/src/main/jniLibs/arm64-v8a/
```

**Step 3: Copy Kotlin API source files**

The sherpa-onnx Kotlin API is distributed as source files, not a Maven AAR. Copy them into the project:

```bash
mkdir -p d:/projects/boji/android/app/src/main/java/com/k2fsa/sherpa/onnx
cp /tmp/sherpa-onnx-android/kotlin-api/OnlineRecognizer.kt d:/projects/boji/android/app/src/main/java/com/k2fsa/sherpa/onnx/
```

The key file needed is `OnlineRecognizer.kt` (streaming recognition). The file defines all config classes and the `OnlineRecognizer` class that wraps the JNI calls.

**Step 4: Remove Vosk dependency from build.gradle.kts**

In `android/app/build.gradle.kts`, remove:
```kotlin
// Vosk offline speech recognition
implementation("com.alphacephei:vosk-android:0.3.75")
```

No new Gradle dependency needed — Sherpa-ONNX uses JNI `.so` files + Kotlin source.

**Step 5: Verify build compiles**

```bash
cd d:/projects/boji/android && ./gradlew assembleDebug
```

Expected: Build succeeds (Sherpa-ONNX classes unused but compiled).

**Step 6: Commit**

```bash
git add android/app/src/main/jniLibs/ android/app/src/main/java/com/k2fsa/ android/app/build.gradle.kts
git commit -m "feat(android): add sherpa-onnx native libraries and remove vosk dependency"
```

---

## Task 2: Download and bundle Paraformer streaming model

**Files:**
- Delete: `android/app/src/main/assets/vosk-model-small-cn/` (entire directory)
- Create: `android/app/src/main/assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/` with model files

**Step 1: Download the streaming Paraformer bilingual model**

```bash
cd /tmp
curl -L -o sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2 https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2
tar xvf sherpa-onnx-streaming-paraformer-bilingual-zh-en.tar.bz2
```

The model directory should contain:
- `encoder.int8.onnx` — encoder (quantized)
- `decoder.int8.onnx` — decoder (quantized)
- `tokens.txt` — vocabulary

**Step 2: Replace Vosk model assets**

```bash
rm -rf d:/projects/boji/android/app/src/main/assets/vosk-model-small-cn
cp -r /tmp/sherpa-onnx-streaming-paraformer-bilingual-zh-en d:/projects/boji/android/app/src/main/assets/
```

**Step 3: Verify model files are present**

```bash
ls -la d:/projects/boji/android/app/src/main/assets/sherpa-onnx-streaming-paraformer-bilingual-zh-en/
```

Expected: `encoder.int8.onnx`, `decoder.int8.onnx`, `tokens.txt` present.

**Step 4: Commit**

```bash
git add android/app/src/main/assets/
git commit -m "feat(android): replace vosk-model-small-cn with sherpa-onnx streaming paraformer bilingual model"
```

---

## Task 3: Implement SherpaOnnxSpeechManager

**Files:**
- Delete: `android/app/src/main/java/ai/axiomaster/boji/remote/chat/VoskSpeechManager.kt`
- Create: `android/app/src/main/java/ai/axiomaster/boji/remote/chat/SherpaOnnxSpeechManager.kt`

This replaces `VoskSpeechManager` with a new class that uses Sherpa-ONNX's `OnlineRecognizer` for streaming recognition. The class must implement the same contract used by `SpeechToTextManager`:

- `prepareModelAsync(onReady, onError)` — init model
- `startListening(listener)` — start mic + recognition loop
- `stopListening()` — stop and deliver final result
- `cancelListening()` — stop and discard
- `destroy()` — cleanup

**Step 1: Create SherpaOnnxSpeechManager.kt**

```kotlin
package ai.axiomaster.boji.remote.chat

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.k2fsa.sherpa.onnx.*

class SherpaOnnxSpeechManager(private val context: Context) {

    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var recognizer: OnlineRecognizer? = null
    @Volatile private var running = false
    @Volatile private var cancelled = false
    @Volatile private var recordThread: Thread? = null
    private var currentListener: SpeechToTextManager.Listener? = null

    private val TAG = "SherpaOnnxSpeechManager"

    val isModelReady: Boolean
        get() = recognizer != null

    fun prepareModelAsync(onReady: () -> Unit, onError: (Exception) -> Unit) {
        Thread {
            try {
                val config = OnlineRecognizerConfig(
                    modelConfig = OnlineModelConfig(
                        paraformer = OnlineParaformerModelConfig(
                            encoder = "$MODEL_DIR/encoder.int8.onnx",
                            decoder = "$MODEL_DIR/decoder.int8.onnx",
                        ),
                        tokens = "$MODEL_DIR/tokens.txt",
                        modelType = "paraformer",
                    ),
                    enableEndpoint = true,
                    endpointConfig = EndpointConfig(
                        rule1 = EndpointRule(false, 2.4f, 0.0f),
                        rule2 = EndpointRule(true, 1.4f, 0.0f),
                        rule3 = EndpointRule(false, 0.0f, 20.0f),
                    ),
                )
                val r = OnlineRecognizer(
                    assetManager = context.assets,
                    config = config,
                )
                recognizer = r
                Log.d(TAG, "Sherpa-ONNX model loaded successfully")
                mainHandler.post(onReady)
            } catch (e: Exception) {
                Log.e(TAG, "Sherpa-ONNX model init failed", e)
                mainHandler.post { onError(e) }
            }
        }.start()
    }

    @SuppressLint("MissingPermission")
    fun startListening(listener: SpeechToTextManager.Listener) {
        if (running) {
            stopListening()
        }
        currentListener = listener

        val r = recognizer
        if (r == null) {
            Log.w(TAG, "Recognizer not ready, preparing now...")
            prepareModelAsync(
                onReady = { startListening(listener) },
                onError = {
                    listener.onError(android.speech.SpeechRecognizer.ERROR_CLIENT)
                }
            )
            return
        }

        running = true
        cancelled = false
        recordThread = Thread({
            runRecognitionLoop(r, listener)
        }, "SherpaOnnxRecordThread").apply { start() }
    }

    fun stopListening() {
        running = false
        recordThread?.join(2000)
        recordThread = null
    }

    fun cancelListening() {
        cancelled = true
        running = false
        recordThread?.join(2000)
        recordThread = null
        currentListener = null
    }

    fun destroy() {
        cancelListening()
        // OnlineRecognizer doesn't need explicit close
        recognizer = null
    }

    @SuppressLint("MissingPermission")
    private fun runRecognitionLoop(r: OnlineRecognizer, listener: SpeechToTextManager.Listener) {
        val sampleRate = 16000
        val bufSize = maxOf(
            AudioRecord.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            ),
            4096
        )

        val audioRecord: AudioRecord
        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufSize
            )
            if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_AUDIO) }
                return
            }
        } catch (e: Exception) {
            Log.e(TAG, "AudioRecord creation failed", e)
            mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_AUDIO) }
            return
        }

        val stream = r.createStream()
        try {
            audioRecord.startRecording()
            mainHandler.post { listener.onReadyForSpeech() }

            val buffer = ShortArray(bufSize)
            var lastPartial = ""
            var deliveredFinal = false

            while (running) {
                val samplesRead = audioRecord.read(buffer, 0, buffer.size)
                if (samplesRead <= 0) continue

                // Convert short[] to float[]
                val samples = FloatArray(samplesRead)
                for (i in 0 until samplesRead) {
                    samples[i] = buffer[i] / 32768.0f
                }
                stream.acceptWave(samples, sampleRate)

                while (r.isReady(stream)) {
                    r.decode(stream)
                }

                val partial = r.getResult(stream).text
                if (partial.isNotBlank() && partial != lastPartial) {
                    lastPartial = partial
                    mainHandler.post { listener.onPartialResult(partial) }
                }

                // Endpoint detected = end of utterance
                if (r.isEndpoint(stream)) {
                    val finalText = r.getResult(stream).text
                    if (finalText.isNotBlank()) {
                        deliveredFinal = true
                        running = false
                        mainHandler.post { listener.onFinalResult(finalText) }
                    }
                    r.reset(stream)
                    lastPartial = ""
                }
            }

            if (!cancelled) {
                if (!deliveredFinal) {
                    // Decode any remaining audio
                    val finalText = r.getResult(stream).text
                    if (finalText.isNotBlank()) {
                        mainHandler.post { listener.onFinalResult(finalText) }
                    }
                }
                mainHandler.post { listener.onEndOfSpeech() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Recognition loop error", e)
            mainHandler.post { listener.onError(android.speech.SpeechRecognizer.ERROR_CLIENT) }
        } finally {
            try {
                audioRecord.stop()
                audioRecord.release()
            } catch (_: Exception) {}
        }
    }

    companion object {
        private const val MODEL_DIR = "sherpa-onnx-streaming-paraformer-bilingual-zh-en"
    }
}
```

**Step 2: Delete VoskSpeechManager.kt**

```bash
rm d:/projects/boji/android/app/src/main/java/ai/axiomaster/boji/remote/chat/VoskSpeechManager.kt
```

**Step 3: Commit**

```bash
git add android/app/src/main/java/ai/axiomaster/boji/remote/chat/SherpaOnnxSpeechManager.kt
git rm android/app/src/main/java/ai/axiomaster/boji/remote/chat/VoskSpeechManager.kt
git commit -m "feat(android): replace VoskSpeechManager with SherpaOnnxSpeechManager"
```

---

## Task 4: Update SpeechToTextManager to use Sherpa-ONNX

**Files:**
- Modify: `android/app/src/main/java/ai/axiomaster/boji/remote/chat/SpeechToTextManager.kt`

Replace the internal `VoskSpeechManager` usage with `SherpaOnnxSpeechManager`. The `Listener` interface and public API stay the same.

**Step 1: Update SpeechToTextManager.kt**

Changes needed:
1. Replace `private val voskManager = VoskSpeechManager(context)` with `private val sherpaManager = SherpaOnnxSpeechManager(context)`
2. Replace `@Volatile private var usingVosk = false` with `@Volatile private var usingSherpa = false`
3. In `startVoskListening()` → rename to `startSherpaListening()`, replace `voskManager.startListening()` with `sherpaManager.startListening()`
4. In `stopListeningOnMain()` → replace `voskManager.stopListening()` with `sherpaManager.stopListening()`
5. In `cancelListeningOnMain()` → replace `voskManager.cancelListening()` with `sherpaManager.cancelListening()`
6. In `destroy()` → replace `voskManager.destroy()` with `sherpaManager.destroy()`
7. In `warmUpVosk()` → rename to `warmUp()`, replace `voskManager.prepareModelAsync()` with `sherpaManager.prepareModelAsync()`
8. Update all Log messages from "Vosk" to "Sherpa-ONNX"

The key rename map:
- `VoskSpeechManager` → `SherpaOnnxSpeechManager`
- `voskManager` → `sherpaManager`
- `usingVosk` → `usingSherpa`
- `startVoskListening` → `startSherpaListening`
- `warmUpVosk()` → `warmUp()`

**Step 2: Update MainViewModel.kt**

Change `sttManager.warmUpVosk()` → `sttManager.warmUp()` in the `init` block.

**Step 3: Update FloatingWindowService.kt**

Change `sttManager?.warmUpVosk()` → `sttManager?.warmUp()`.

**Step 4: Verify build compiles**

```bash
cd d:/projects/boji/android && ./gradlew assembleDebug
```

Expected: Build succeeds with no errors.

**Step 5: Commit**

```bash
git add android/app/src/main/java/ai/axiomaster/boji/remote/chat/SpeechToTextManager.kt
git add android/app/src/main/java/ai/axiomaster/boji/MainViewModel.kt
git add android/app/src/main/java/ai/axiomaster/boji/FloatingWindowService.kt
git commit -m "feat(android): wire SherpaOnnxSpeechManager into SpeechToTextManager"
```

---

## Task 5: Add Sherpa-ONNX to HarmonyOS app

**Files:**
- Modify: `harmonyos/oh-package.json5`
- Create: SherpaOnnxSpeechManager.ets (HarmonyOS equivalent)

**Step 1: Add sherpa_onnx OHPM dependency**

In `harmonyos/oh-package.json5`, add:
```json5
"dependencies": {
    "@ohos/lottie": "^2.0.29",
    "sherpa_onnx": "1.12.1"
}
```

**Step 2: Install dependency**

```bash
cd d:/projects/boji/harmonyos && ohpm install
```

**Step 3: Create HarmonyOS SherpaOnnxSpeechManager**

Create `harmonyos/entry/src/main/ets/voice/SherpaOnnxSpeechManager.ets` — a HarmonyOS equivalent of the Android SherpaOnnxSpeechManager using the sherpa_onnx OHPM package APIs.

This task is deferred until the Android integration is validated. The HarmonyOS voice integration (VoiceWakeManager, TalkModeManager) has placeholder code that needs to be wired separately.

**Step 4: Commit**

```bash
git add harmonyos/oh-package.json5 harmonyos/entry/src/main/ets/voice/SherpaOnnxSpeechManager.ets
git commit -m "feat(harmonyos): add sherpa-onnx dependency and speech manager skeleton"
```

---

## Task 6: Test and validate on device

**Step 1: Install and test on Android device**

```bash
cd d:/projects/boji/android && ./gradlew installDebug
```

Test scenarios:
1. Connect to HiClaw server
2. Tap microphone in chat → speak Chinese → verify text appears correctly
3. Test partial results display during speech
4. Test floating window long-press voice input
5. Test with English words mixed in Chinese (bilingual model)
6. Test offline (no network) — should still work since it's on-device

**Step 2: Verify model loads correctly**

Check logcat for:
- `Sherpa-ONNX model loaded successfully` — model init OK
- `SherpaOnnxRecordThread` — recognition loop running
- Partial/final results in logcat

```bash
adb logcat -s SherpaOnnxSpeechManager SherpaOnnx SpeechToTextManager
```

**Step 3: Commit final state**

```bash
git add -A
git commit -m "feat: complete sherpa-onnx speech recognition integration"
```

---

## Important Notes

### Model Size
The streaming Paraformer bilingual model is ~200MB. The old Vosk small-cn model was ~50MB. This is a significant increase but justified by the much better accuracy (CER <5% vs ~23%).

### Why Streaming Paraformer
- Real-time partial results (user sees text as they speak)
- Bilingual zh-en support (handles mixed Chinese/English input)
- Endpoint detection (auto-detects when user stops speaking)
- int8 quantized (optimized for mobile inference)

### Fallback Behavior
The dual-layer architecture is preserved:
1. System STT (Google on-device) is tried first
2. If system STT fails, Sherpa-ONNX Paraformer is used as fallback
3. Sherpa-ONNX always works offline — no network dependency

### Cross-Platform
- Android: JNI native libraries + Kotlin API source
- HarmonyOS: OHPM `sherpa_onnx` package (Task 5, can be done in parallel)
- Same Paraformer model works on both platforms
