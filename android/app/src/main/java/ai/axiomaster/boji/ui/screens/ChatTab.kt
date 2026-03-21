package ai.axiomaster.boji.ui.screens

import android.content.ContentResolver
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.boji.MainViewModel
import ai.axiomaster.boji.remote.chat.ChatSessionEntry
import ai.axiomaster.boji.remote.chat.OutgoingAttachment
import ai.axiomaster.boji.ui.screens.chat.*
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withTimeoutOrNull
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.animateLottieCompositionAsState
import com.airbnb.lottie.compose.rememberLottieComposition
import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class PendingImageAttachment(
    val id: String,
    val fileName: String,
    val mimeType: String,
    val base64: String,
)

@Composable
fun ChatTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    
    val messages by viewModel.chatMessages.collectAsState()
    val errorText by viewModel.chatError.collectAsState()
    val pendingRunCount by viewModel.pendingRunCount.collectAsState()
    val healthOk by viewModel.chatHealthOk.collectAsState()
    val sessionKey by viewModel.chatSessionKey.collectAsState()
    val mainSessionKey by viewModel.mainSessionKey.collectAsState()
    val thinkingLevel by viewModel.chatThinkingLevel.collectAsState()
    val streamingAssistantText by viewModel.chatStreamingAssistantText.collectAsState()
    val pendingToolCalls by viewModel.chatPendingToolCalls.collectAsState()
    val sessions by viewModel.chatSessions.collectAsState()

    LaunchedEffect(mainSessionKey) {
        viewModel.loadChat(mainSessionKey)
        viewModel.refreshChatSessions(limit = 200)
    }
    LaunchedEffect(Unit) {
        viewModel.refreshInstalledThemes()
    }

    val resolver = context.contentResolver
    val scope = rememberCoroutineScope()

    val attachments = remember { mutableStateListOf<PendingImageAttachment>() }
    val isSpeakerEnabled by viewModel.isSpeakerEnabled.collectAsState()
    val partialSttText by viewModel.partialSttText.collectAsState()

    val micPermissionLauncher =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) {
                viewModel.startVoiceInput()
            }
        }

    val startVoiceWithPermission = {
        val hasMic = androidx.core.content.ContextCompat.checkSelfPermission(
            context, android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (hasMic) {
            viewModel.startVoiceInput()
        } else {
            micPermissionLauncher.launch(android.Manifest.permission.RECORD_AUDIO)
        }
    }

    val pickImages =
        rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
            if (uris.isNullOrEmpty()) return@rememberLauncherForActivityResult
            scope.launch(Dispatchers.IO) {
                val next =
                    uris.take(8).mapNotNull { uri ->
                        try {
                            loadImageAttachment(resolver, uri)
                        } catch (_: Throwable) {
                            null
                        }
                    }
                withContext(Dispatchers.Main) {
                    attachments.addAll(next)
                }
            }
        }

    Box(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 0.dp), // Reduce vertical padding to accommodate top tabs
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
        Spacer(modifier = Modifier.height(12.dp)) // Managed spacing
        ChatThreadSelector(
            sessionKey = sessionKey,
            sessions = sessions,
            mainSessionKey = mainSessionKey,
            healthOk = healthOk,
            isSpeakerEnabled = isSpeakerEnabled,
            onToggleSpeaker = { viewModel.setSpeakerEnabled(!isSpeakerEnabled) },
            onSelectSession = { key -> viewModel.switchChatSession(key) },
        )

        if (!errorText.isNullOrBlank()) {
            ChatErrorRail(errorText = errorText!!)
        }

        ChatMessageList(
            messages = messages,
            pendingRunCount = pendingRunCount,
            pendingToolCalls = pendingToolCalls,
            streamingAssistantText = streamingAssistantText,
            healthOk = healthOk,
            modifier = Modifier.weight(1f, fill = true),
        )

        Row(modifier = Modifier.fillMaxWidth().imePadding()) {
            ChatComposer(
                healthOk = healthOk,
                thinkingLevel = thinkingLevel,
                pendingRunCount = pendingRunCount,
                attachments = attachments,
                isSpeakerEnabled = isSpeakerEnabled,
                partialSttText = partialSttText,
                onPickImages = { pickImages.launch("image/*") },
                onRemoveAttachment = { id -> attachments.removeAll { it.id == id } },
                onSetThinkingLevel = { level -> viewModel.setChatThinkingLevel(level) },
                onRefresh = {
                    viewModel.refreshChat()
                    viewModel.refreshChatSessions(limit = 200)
                },
                onAbort = { viewModel.abortChat() },
                onSend = { text ->
                    val outgoing =
                        attachments.map { att ->
                            OutgoingAttachment(
                                type = "image",
                                mimeType = att.mimeType,
                                fileName = att.fileName,
                                base64 = att.base64,
                            )
                        }
                    viewModel.sendChat(message = text, thinking = thinkingLevel, attachments = outgoing)
                    attachments.clear()
                },
                onStartVoice = { startVoiceWithPermission() },
                onStopVoice = { viewModel.stopVoiceInput() },
                onCancelVoice = { viewModel.cancelVoiceInput() },
            )
        }
    }
    
    val agentState by AgentManager.stateManager.currentState.collectAsState()
    val installedThemes by viewModel.installedThemes.collectAsState()
    val assetPath = remember(installedThemes, agentState) {
        viewModel.getThemeAssetPath(agentState)
    }
    FloatingDraggableAvatar(
        agentState = agentState,
        assetPath = assetPath,
        isSpeakerEnabled = isSpeakerEnabled,
        pendingRunCount = pendingRunCount,
        partialSttText = partialSttText,
        onStartVoice = { startVoiceWithPermission() },
        onStopVoice = { viewModel.stopVoiceInput() },
        onCancelVoice = { viewModel.cancelVoiceInput() },
    )
}
}

@Composable
private fun ChatThreadSelector(
    sessionKey: String,
    sessions: List<ChatSessionEntry>,
    mainSessionKey: String,
    healthOk: Boolean,
    isSpeakerEnabled: Boolean,
    onToggleSpeaker: () -> Unit,
    onSelectSession: (String) -> Unit,
) {
    val sessionOptions = resolveSessionChoices(sessionKey, sessions, mainSessionKey = mainSessionKey)

    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        // Scrollable area for sessions and status
        Row(
            modifier = Modifier.weight(1f).horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (entry in sessionOptions) {
                val active = entry.key == sessionKey
                Surface(
                    onClick = { onSelectSession(entry.key) },
                    shape = RoundedCornerShape(8.dp), // Rounded rectangle
                    color = if (active) mobileAccent else Color.White,
                    border = BorderStroke(1.dp, if (active) Color(0xFF154CAD) else mobileBorderStrong),
                    tonalElevation = 0.dp,
                    shadowElevation = 0.dp,
                ) {
                    Text(
                        text = friendlySessionName(entry.displayName ?: entry.key),
                        style = mobileCaption1.copy(fontWeight = if (active) FontWeight.Bold else FontWeight.SemiBold),
                        color = if (active) Color.White else mobileText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    )
                }

                if (active) {
                    ChatConnectionPill(healthOk = healthOk)
                }
            }
        }

        // Speaker Toggle Button
        Surface(
            onClick = onToggleSpeaker,
            shape = RoundedCornerShape(8.dp),
            color = if (isSpeakerEnabled) mobileAccentSoft else Color(0xFFF0F0F0),
            border = BorderStroke(1.dp, if (isSpeakerEnabled) mobileAccent.copy(alpha = 0.2f) else mobileBorder),
        ) {
            Box(
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = if (isSpeakerEnabled) Icons.Default.VolumeUp else Icons.Default.VolumeOff,
                    contentDescription = "Speaker Toggle",
                    modifier = Modifier.size(18.dp),
                    tint = if (isSpeakerEnabled) mobileAccent else Color(0xFF99A0AE)
                )
            }
        }
    }
}

@Composable
private fun ChatConnectionPill(healthOk: Boolean) {
    Surface(
        shape = RoundedCornerShape(8.dp), // Rounded rectangle
        color = if (healthOk) mobileSuccessSoft else mobileWarningSoft,
        border = BorderStroke(1.dp, if (healthOk) mobileSuccess.copy(alpha = 0.35f) else mobileWarning.copy(alpha = 0.35f)),
    ) {
        Text(
            text = if (healthOk) "Connected" else "Offline",
            style = mobileCaption2.copy(fontWeight = FontWeight.Bold), // Smaller text for compactness
            color = if (healthOk) mobileSuccess else mobileWarning,
            modifier = Modifier.padding(horizontal = 6.dp, vertical = 3.dp),
        )
    }
}

@Composable
private fun ChatErrorRail(errorText: String) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = Color.White,
        shape = RoundedCornerShape(12.dp),
        border = BorderStroke(1.dp, mobileDanger),
    ) {
        Column(modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = "CHAT ERROR",
                style = mobileCaption2.copy(letterSpacing = 0.6.sp),
                color = mobileDanger,
            )
            Text(text = errorText, style = mobileCallout, color = mobileText)
        }
    }
}

private suspend fun loadImageAttachment(resolver: ContentResolver, uri: Uri): PendingImageAttachment {
    val mimeType = resolver.getType(uri) ?: "image/*"
    val fileName = (uri.lastPathSegment ?: "image").substringAfterLast('/')
    val bytes =
        withContext(Dispatchers.IO) {
            resolver.openInputStream(uri)?.use { input ->
                val out = ByteArrayOutputStream()
                input.copyTo(out)
                out.toByteArray()
            } ?: ByteArray(0)
        }
    if (bytes.isEmpty()) throw IllegalStateException("empty attachment")
    val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
    return PendingImageAttachment(
        id = uri.toString() + "#" + System.currentTimeMillis().toString(),
        fileName = fileName,
        mimeType = mimeType,
        base64 = base64,
    )
}

@Composable
fun FloatingDraggableAvatar(
    agentState: AgentState,
    assetPath: String,
    isSpeakerEnabled: Boolean,
    pendingRunCount: Int,
    partialSttText: String?,
    onStartVoice: () -> Unit,
    onStopVoice: () -> Unit,
    onCancelVoice: () -> Unit,
) {
    val density = LocalDensity.current

    var offsetX by remember { mutableFloatStateOf(0f) }
    var offsetY by remember { mutableFloatStateOf(0f) }

    val maxOffsetX = with(density) { 150.dp.toPx() }

    fun snapToEdge() {
        val targetX = if (offsetX > 0) maxOffsetX else -maxOffsetX
        offsetX = targetX
    }

    val composition by rememberLottieComposition(LottieCompositionSpec.Asset(assetPath))
    val progress by animateLottieCompositionAsState(
        composition,
        iterations = LottieConstants.IterateForever,
        isPlaying = true
    )

    val effectiveProgress = if (agentState == AgentState.Speaking && !isSpeakerEnabled) {
        0f
    } else {
        progress
    }

    val currentAgentState by rememberUpdatedState(agentState)
    val currentPendingRunCount by rememberUpdatedState(pendingRunCount)
    val currentOnStartVoice by rememberUpdatedState(onStartVoice)
    val currentOnStopVoice by rememberUpdatedState(onStopVoice)
    val currentOnCancelVoice by rememberUpdatedState(onCancelVoice)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(bottom = 120.dp),
        contentAlignment = Alignment.BottomEnd
    ) {
        Box(
            modifier = Modifier
                .offset { IntOffset(offsetX.roundToInt(), offsetY.roundToInt()) }
                .size(192.dp)
                .pointerInput(Unit) {
                    val dragThreshold = 10.dp.toPx()
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        android.util.Log.d("CatGesture", "DOWN state=${currentAgentState} pending=${currentPendingRunCount}")
                        var isDragging = false
                        var sttStarted = false
                        var totalDragX = 0f
                        var totalDragY = 0f

                        val canStartVoice = currentPendingRunCount == 0 && currentAgentState == AgentState.Idle
                        android.util.Log.d("CatGesture", "canStartVoice=$canStartVoice")

                        if (canStartVoice) {
                            val movedDuringWait = withTimeoutOrNull(300L) {
                                while (true) {
                                    val event = awaitPointerEvent(PointerEventPass.Main)
                                    val pointer = event.changes.firstOrNull() ?: return@withTimeoutOrNull false
                                    if (pointer.changedToUp()) return@withTimeoutOrNull false
                                    val change = pointer.positionChange()
                                    totalDragX += change.x
                                    totalDragY += change.y
                                    if (kotlin.math.abs(totalDragX) > dragThreshold || kotlin.math.abs(totalDragY) > dragThreshold) {
                                        return@withTimeoutOrNull true
                                    }
                                }
                                @Suppress("UNREACHABLE_CODE")
                                false
                            }
                            android.util.Log.d("CatGesture", "movedDuringWait=$movedDuringWait")
                            when (movedDuringWait) {
                                null -> {
                                    sttStarted = true
                                    android.util.Log.d("CatGesture", "LONG_PRESS -> calling onStartVoice")
                                    currentOnStartVoice()
                                }
                                true -> {
                                    isDragging = true
                                    offsetX += totalDragX
                                    offsetY += totalDragY
                                }
                                false -> {
                                    android.util.Log.d("CatGesture", "TAP (lifted within 300ms)")
                                    return@awaitEachGesture
                                }
                            }
                        }

                        // Main event loop for drag or waiting for voice release
                        while (true) {
                            val event = awaitPointerEvent()
                            val pointer = event.changes.firstOrNull() ?: break

                            if (pointer.changedToUp()) {
                                pointer.consume()
                                if (isDragging) {
                                    snapToEdge()
                                } else if (sttStarted) {
                                    currentOnStopVoice()
                                }
                                break
                            }

                            if (!pointer.pressed) break

                            val change = pointer.positionChange()
                            totalDragX += change.x
                            totalDragY += change.y

                            if (!isDragging && (kotlin.math.abs(totalDragX) > dragThreshold || kotlin.math.abs(totalDragY) > dragThreshold)) {
                                isDragging = true
                                if (sttStarted) {
                                    currentOnCancelVoice()
                                    sttStarted = false
                                }
                            }

                            if (isDragging) {
                                pointer.consume()
                                offsetX += change.x
                                offsetY += change.y
                            }
                        }
                    }
                },
            contentAlignment = Alignment.Center
        ) {
            LottieAnimation(
                composition = composition,
                progress = { effectiveProgress },
                modifier = Modifier.fillMaxSize()
            )

            if (agentState == AgentState.Listening || agentState == AgentState.Thinking) {
                Surface(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .offset(y = (-20).dp)
                        .widthIn(max = 200.dp),
                    shape = RoundedCornerShape(16.dp),
                    color = Color.White,
                    shadowElevation = 4.dp,
                ) {
                    Column(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = if (agentState == AgentState.Listening) "Listening..." else "Thinking...",
                            style = mobileCaption2,
                            color = if (agentState == AgentState.Listening) mobileAccent else mobileTextSecondary,
                        )
                        if (agentState == AgentState.Listening && !partialSttText.isNullOrBlank()) {
                            Text(
                                text = partialSttText,
                                style = mobileCaption2,
                                color = mobileText,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}
