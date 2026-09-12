package ai.axiomaster.bonio.ui.screens

import android.content.ContentResolver
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.VolumeOff
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.remote.chat.ChatSessionEntry
import ai.axiomaster.bonio.remote.chat.OutgoingAttachment
import ai.axiomaster.bonio.remote.memory.CompanionMemoryController
import ai.axiomaster.bonio.ui.screens.chat.*
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

private const val WECHAT_SESSION_PREFIX = "wechat:"

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

    val sessionLabel = remember(sessionKey) {
        labelForSessionKey(sessionKey)
    }

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

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFFAFAFA))
    ) {
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            // ── Header Bar (Connection Status + Session Capsules + Speaker) ──
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Connection status pill
                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = Color(0xFFE8ECF0),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = "●",
                            fontSize = 8.sp,
                            color = if (healthOk) Color(0xFF2ECC71) else Color(0xFFF39C12)
                        )
                        Text(
                            text = if (healthOk) "Connected" else "Offline",
                            fontSize = 11.sp,
                            color = Color(0xFF999999)
                        )
                    }
                }

                Spacer(modifier = Modifier.width(6.dp))

                // Session capsules (chat, memory, wechat)
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    listOf("chat", "memory", "wechat").forEach { label ->
                        val active = sessionLabel == label
                        Surface(
                            onClick = {
                                when (label) {
                                    "memory" -> viewModel.switchChatSession(CompanionMemoryController.SESSION_KEY)
                                    "wechat" -> {
                                        viewModel.refreshChatSessions(limit = 200)
                                        val key = latestWechatSessionKey(sessions) ?: "${WECHAT_SESSION_PREFIX}pending"
                                        viewModel.switchChatSession(key)
                                    }
                                    else -> viewModel.switchChatSession(mainSessionKey.ifEmpty { "main" })
                                }
                            },
                            shape = RoundedCornerShape(14.dp),
                            color = if (active) Color(0xFF0A59F7) else Color(0xFFE8ECF0),
                        ) {
                            Text(
                                text = label,
                                fontSize = 13.sp,
                                color = if (active) Color.White else Color(0xFF333333),
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 5.dp)
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.width(6.dp))

                // Speaker toggle button
                Surface(
                    onClick = { viewModel.setSpeakerEnabled(!isSpeakerEnabled) },
                    shape = RoundedCornerShape(14.dp),
                    color = if (isSpeakerEnabled) Color(0xFFE3F2FD) else Color(0xFFF0F0F0),
                    modifier = Modifier.size(width = 36.dp, height = 28.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = if (isSpeakerEnabled) Icons.Default.VolumeUp else Icons.Default.VolumeOff,
                            contentDescription = "Speaker Toggle",
                            modifier = Modifier.size(16.dp),
                            tint = if (isSpeakerEnabled) Color(0xFF0A59F7) else Color(0xFF888888)
                        )
                    }
                }
            }

            if (!errorText.isNullOrBlank()) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp, vertical = 4.dp),
                    shape = RoundedCornerShape(8.dp),
                    color = Color(0xFFFFEBEE)
                ) {
                    Text(
                        text = errorText!!,
                        fontSize = 12.sp,
                        color = Color(0xFFE53935),
                        modifier = Modifier.padding(8.dp)
                    )
                }
            }

            // ── Messages Area ──
            ChatMessageList(
                sessionLabel = sessionLabel,
                messages = messages,
                pendingRunCount = pendingRunCount,
                pendingToolCalls = pendingToolCalls,
                streamingAssistantText = streamingAssistantText,
                healthOk = healthOk,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp),
            )

            // ── Bottom Composer (Only shown in 'chat' session, matching HarmonyOS) ──
            if (sessionLabel == "chat") {
                Box(modifier = Modifier.fillMaxWidth().imePadding()) {
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
}

private fun labelForSessionKey(key: String): String {
    if (key == CompanionMemoryController.SESSION_KEY) return "memory"
    if (key.startsWith(WECHAT_SESSION_PREFIX)) return "wechat"
    return "chat"
}

private fun latestWechatSessionKey(sessions: List<ChatSessionEntry>): String? {
    return sessions
        .filter { it.key.startsWith(WECHAT_SESSION_PREFIX) }
        .maxByOrNull { it.updatedAtMs ?: 0L }
        ?.key
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
