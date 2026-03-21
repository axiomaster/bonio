package ai.axiomaster.boji.ui.screens.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.boji.remote.chat.ChatMessage
import ai.axiomaster.boji.remote.chat.ChatPendingToolCall
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import androidx.compose.material3.Icon
import androidx.compose.runtime.*

@Composable
fun ChatMessageList(
    messages: List<ChatMessage>,
    pendingRunCount: Int,
    pendingToolCalls: List<ChatPendingToolCall>,
    streamingAssistantText: String?,
    healthOk: Boolean,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    LaunchedEffect(messages.size, streamingAssistantText) {
        // In reverseLayout, index 0 is the bottom. 
        // We only auto-scroll if the user is already at the bottom or if the content is new.
        if (listState.firstVisibleItemIndex <= 1) {
            listState.animateScrollToItem(index = 0)
        }
    }

    Box(modifier = modifier.fillMaxWidth()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            reverseLayout = true,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 16.dp, top = 16.dp),
        ) {
            val stream = streamingAssistantText?.trim()
            if (!stream.isNullOrEmpty()) {
                item(key = "stream") {
                    ChatStreamingAssistantBubble(text = stream)
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
            Box(modifier = Modifier.align(Alignment.Center).padding(32.dp)) {
                Text(
                    if (healthOk) "No messages yet. Send a prompt!" else "Gateway offline. Please connect in Settings.",
                    color = mobileTextTertiary,
                    style = mobileCallout,
                    fontWeight = FontWeight.Medium
                )
            }
        }
    }
}

@Composable
fun ChatMessageBubble(message: ChatMessage) {
    val role = message.role.trim().lowercase(java.util.Locale.US)
    val isUser = role == "user"
    val containerColor = if (isUser) mobileAccentSoft else Color.White
    val borderColor = if (isUser) mobileAccent else mobileBorderStrong
    val roleColor = if (isUser) mobileAccent else mobileTextSecondary

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(12.dp),
            border = androidx.compose.foundation.BorderStroke(1.dp, borderColor),
            color = containerColor,
            modifier = Modifier.fillMaxWidth(0.90f),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 11.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Text(
                    text = if (isUser) "USER" else "ASSISTANT",
                    style = mobileCaption2.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
                    color = roleColor,
                )
                
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (part in message.content) {
                        when (part.type) {
                            "text" -> {
                                val text = part.text ?: continue
                                if (text != "[Voice Message]") { // Hide placeholder text if it's a voice message
                                    ChatMarkdown(text = text, textColor = mobileText)
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
}

@Composable
fun ChatStreamingAssistantBubble(text: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(12.dp),
            border = androidx.compose.foundation.BorderStroke(1.dp, mobileAccent),
            color = Color.White,
            modifier = Modifier.fillMaxWidth(0.90f),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 11.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Text(
                    text = "ASSISTANT · LIVE",
                    style = mobileCaption2.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
                    color = mobileAccent,
                )
                ChatMarkdown(text = text, textColor = mobileText)
            }
        }
    }
}

@Composable
fun ChatPendingToolsBubble(toolCalls: List<ChatPendingToolCall>) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            shape = RoundedCornerShape(12.dp),
            border = androidx.compose.foundation.BorderStroke(1.dp, mobileBorderStrong),
            color = Color.White,
            modifier = Modifier.fillMaxWidth(0.90f),
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 11.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = "TOOLS",
                    style = mobileCaption2.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.6.sp),
                    color = mobileTextSecondary,
                )
                Text("Running tools: ${toolCalls.joinToString { it.name }}...", style = mobileCallout, color = mobileTextSecondary)
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
            border = androidx.compose.foundation.BorderStroke(1.dp, mobileBorder),
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
        Text("Unsupported attachment", style = mobileCaption1, color = mobileTextSecondary)
    }
}

@Composable
fun VoiceMessagePlayer(base64: String, durationMs: Long?) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var isPlaying by remember { mutableStateOf(false) }
    var mediaPlayer by remember { mutableStateOf<android.media.MediaPlayer?>(null) }
    var audioFile by remember { mutableStateOf<java.io.File?>(null) }
    
    // Cleanup on unmount
    DisposableEffect(Unit) {
        onDispose {
            mediaPlayer?.release()
            try { audioFile?.delete() } catch(e: Exception) {}
        }
    }
    
    val formattedDuration = remember(durationMs) {
        if (durationMs == null || durationMs <= 0) "0:00"
        else {
            val totalSeconds = durationMs / 1000
            val m = totalSeconds / 60
            val s = totalSeconds % 60
            String.format(java.util.Locale.US, "%d:%02d", m, s)
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
                    val file = java.io.File.createTempFile("voice_playback_", ".m4a", context.cacheDir)
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
                } catch (e: Exception) {
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
            .background(mobileSurface)
            .clickable { togglePlayback() }
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Icon(
            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
            contentDescription = if (isPlaying) "Pause" else "Play",
            tint = mobileAccent,
            modifier = Modifier.size(24.dp)
        )
        // Simple waveform visualizer placeholder
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.height(24.dp).padding(horizontal = 4.dp)
        ) {
            val heights = listOf(12, 16, 20, 14, 18, 10, 14, 20, 16, 12)
            heights.forEach { h ->
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .height(if (isPlaying) h.dp else (h/2).dp)
                        .clip(CircleShape)
                        .background(if (isPlaying) mobileAccent else mobileBorderStrong)
                )
            }
        }
        Text(formattedDuration, color = mobileTextSecondary, style = mobileCaption1)
    }
}
