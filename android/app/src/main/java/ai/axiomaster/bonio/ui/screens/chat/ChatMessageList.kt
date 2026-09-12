package ai.axiomaster.bonio.ui.screens.chat

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.remote.chat.ChatMessage
import ai.axiomaster.bonio.remote.chat.ChatPendingToolCall
import ai.axiomaster.bonio.ui.theme.LocalAppColors
import java.io.File
import java.util.Locale

@Composable
fun ChatMessageList(
    sessionLabel: String,
    messages: List<ChatMessage>,
    pendingRunCount: Int,
    pendingToolCalls: List<ChatPendingToolCall>,
    streamingAssistantText: String?,
    healthOk: Boolean,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size, streamingAssistantText) {
        if (listState.firstVisibleItemIndex <= 1) {
            listState.animateScrollToItem(index = 0)
        }
    }

    val strings = LocalAppStrings.current
    val colors = LocalAppColors.current

    Box(modifier = modifier.fillMaxWidth()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            reverseLayout = true,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(bottom = 12.dp, top = 8.dp),
        ) {
            val stream = streamingAssistantText?.trim()
            if (!stream.isNullOrEmpty()) {
                item(key = "stream") {
                    ChatStreamingAssistantBubble(text = stream)
                }
            }

            if (pendingRunCount > 0 && stream.isNullOrBlank()) {
                item(key = "typing") {
                    TypingIndicator()
                }
            }

            if (pendingToolCalls.isNotEmpty()) {
                item(key = "tools") {
                    ChatPendingToolsBubble(toolCalls = pendingToolCalls)
                }
            }

            items(count = messages.size, key = { idx -> messages[messages.size - 1 - idx].id }) { idx ->
                val msg = messages[messages.size - 1 - idx]
                ChatMessageBubble(message = msg)
            }
        }

        if (messages.isEmpty() && pendingRunCount == 0 && pendingToolCalls.isEmpty() && streamingAssistantText.isNullOrBlank()) {
            if (sessionLabel == "wechat") {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(top = 96.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = strings.emptyWechatTitle,
                        fontSize = 14.sp,
                        color = colors.textSecondary
                    )
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = strings.emptyWechatSubtitle,
                        fontSize = 12.sp,
                        color = colors.textTertiary
                    )
                }
            } else {
                Box(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(32.dp)
                ) {
                    Text(
                        text = if (healthOk) strings.emptyChat else strings.emptyChatOffline,
                        color = colors.textSecondary,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}

@Composable
fun ChatMessageBubble(message: ChatMessage) {
    val colors = LocalAppColors.current
    val role = message.role.trim().lowercase(Locale.US)
    val isUser = role == "user"

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = if (isUser) Color(0xFF1A9E96) else colors.cardBackground,
            border = if (isUser) null else BorderStroke(1.dp, colors.border),
            modifier = Modifier.widthIn(max = 340.dp).fillMaxWidth(0.85f),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                for (part in message.content) {
                    when (part.type) {
                        "text" -> {
                            val text = part.text ?: continue
                            if (text != "[Voice Message]") {
                                ChatMarkdown(
                                    text = text,
                                    textColor = if (isUser) Color.White else colors.textPrimary
                                )
                            }
                        }
                        "audio" -> {
                            val b64 = part.base64 ?: continue
                            VoiceMessagePlayer(base64 = b64, durationMs = part.durationMs)
                        }
                        else -> {
                            val b64 = part.base64 ?: continue
                            ChatBase64Image(base64 = b64, mimeType = part.mimeType)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun ChatStreamingAssistantBubble(text: String) {
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = colors.cardBackground,
            border = BorderStroke(1.dp, colors.border),
            modifier = Modifier.fillMaxWidth(0.92f),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                ChatMarkdown(text = text, textColor = colors.textPrimary)
            }
        }
    }
}

@Composable
fun TypingIndicator() {
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = colors.cardBackground,
            border = BorderStroke(1.dp, colors.border),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Text("●", fontSize = 8.sp, color = colors.textTertiary.copy(alpha = 0.4f))
                Text("●", fontSize = 8.sp, color = colors.textTertiary.copy(alpha = 0.65f))
                Text("●", fontSize = 8.sp, color = colors.textTertiary.copy(alpha = 0.9f))
                Spacer(modifier = Modifier.width(4.dp))
                Text("Thinking…", fontSize = 14.sp, color = colors.textTertiary)
            }
        }
    }
}

@Composable
fun ChatPendingToolsBubble(toolCalls: List<ChatPendingToolCall>) {
    val colors = LocalAppColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(16.dp),
            color = colors.cardBackground,
            border = BorderStroke(1.dp, colors.border),
            modifier = Modifier.fillMaxWidth(0.85f),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = "Running tools: ${toolCalls.joinToString { it.name }}...",
                    fontSize = 13.sp,
                    color = colors.textSecondary
                )
            }
        }
    }
}

@Composable
private fun ChatBase64Image(base64: String, mimeType: String?) {
    val imageState = rememberBase64ImageState(base64)
    val image = imageState.image

    if (image != null) {
        Surface(
            shape = RoundedCornerShape(10.dp),
            color = Color.White,
            modifier = Modifier.fillMaxWidth(),
        ) {
            androidx.compose.foundation.Image(
                bitmap = image,
                contentDescription = mimeType ?: "attachment",
                modifier = Modifier.fillMaxWidth(),
                contentScale = androidx.compose.ui.layout.ContentScale.Fit
            )
        }
    } else if (imageState.failed) {
        Text("Unsupported attachment", fontSize = 12.sp, color = Color(0xFF999999))
    }
}

@Composable
fun VoiceMessagePlayer(base64: String, durationMs: Long?) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var isPlaying by remember { mutableStateOf(false) }
    var mediaPlayer by remember { mutableStateOf<android.media.MediaPlayer?>(null) }
    var audioFile by remember { mutableStateOf<File?>(null) }

    DisposableEffect(Unit) {
        onDispose {
            mediaPlayer?.release()
            try { audioFile?.delete() } catch (_: Exception) {}
        }
    }

    val formattedDuration = remember(durationMs) {
        if (durationMs == null || durationMs <= 0) "0:00"
        else {
            val totalSeconds = durationMs / 1000
            val m = totalSeconds / 60
            val s = totalSeconds % 60
            String.format(Locale.US, "%d:%02d", m, s)
        }
    }

    fun togglePlayback() {
        if (isPlaying) {
            mediaPlayer?.pause()
            isPlaying = false
        } else {
            if (mediaPlayer == null) {
                try {
                    val bytes = android.util.Base64.decode(base64, android.util.Base64.DEFAULT)
                    val file = File.createTempFile("voice_playback_", ".m4a", context.cacheDir)
                    file.writeBytes(bytes)
                    audioFile = file

                    val mp = android.media.MediaPlayer()
                    mp.setDataSource(file.absolutePath)
                    mp.setOnCompletionListener {
                        isPlaying = false
                        it.seekTo(0)
                        it.pause()
                    }
                    mp.prepare()
                    mediaPlayer = mp
                } catch (_: Exception) {
                    android.widget.Toast.makeText(context, "Failed to load audio", android.widget.Toast.LENGTH_SHORT).show()
                    return
                }
            }
            mediaPlayer?.start()
            isPlaying = true
        }
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(Color.White.copy(alpha = 0.8f))
            .clickable { togglePlayback() }
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Icon(
            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
            contentDescription = if (isPlaying) "Pause" else "Play",
            tint = Color(0xFF0A59F7),
            modifier = Modifier.size(20.dp)
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.height(20.dp).padding(horizontal = 4.dp)
        ) {
            val heights = listOf(10, 14, 18, 12, 16, 8, 12, 18, 14, 10)
            heights.forEach { h ->
                Box(
                    modifier = Modifier
                        .width(2.5.dp)
                        .height(if (isPlaying) h.dp else (h / 2).dp)
                        .clip(CircleShape)
                        .background(if (isPlaying) Color(0xFF0A59F7) else Color(0xFFCCCCCC))
                )
            }
        }
        Text(formattedDuration, color = Color(0xFF666666), fontSize = 12.sp)
    }
}
