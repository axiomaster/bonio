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

