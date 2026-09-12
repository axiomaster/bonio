package ai.axiomaster.bonio.ui.screens.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.ai.AgentManager
import ai.axiomaster.bonio.ai.AgentState
import ai.axiomaster.bonio.ui.screens.PendingImageAttachment

@Composable
fun ChatComposer(
    healthOk: Boolean,
    thinkingLevel: String,
    pendingRunCount: Int,
    attachments: List<PendingImageAttachment>,
    isSpeakerEnabled: Boolean = true,
    partialSttText: String? = null,
    onPickImages: () -> Unit,
    onRemoveAttachment: (id: String) -> Unit,
    onSetThinkingLevel: (level: String) -> Unit,
    onRefresh: () -> Unit,
    onAbort: () -> Unit,
    onSend: (text: String) -> Unit,
    onStartVoice: () -> Unit = {},
    onStopVoice: () -> Unit = {},
    onCancelVoice: () -> Unit = {},
) {
    var input by rememberSaveable { mutableStateOf("") }
    var showThinkingMenu by remember { mutableStateOf(false) }
    var showAttachmentMenu by remember { mutableStateOf(false) }

    val agentState by AgentManager.stateManager.currentState.collectAsState()

    val canSend = pendingRunCount == 0 && (input.trim().isNotEmpty() || attachments.isNotEmpty()) && healthOk
    val sendBusy = pendingRunCount > 0

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                color = Color(0xFFF0F4F8),
                shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
            )
            .padding(horizontal = 10.dp, vertical = 6.dp)
            .padding(bottom = 12.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                if (showAttachmentMenu) showAttachmentMenu = false
            },
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        // ── Top Control Row: Thinking Level (Left), Stop Button (Right) ──
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // Thinking level chip (on LEFT)
            Box {
                Surface(
                    onClick = { showThinkingMenu = true },
                    shape = RoundedCornerShape(14.dp),
                    color = Color.White,
                    border = BorderStroke(1.dp, Color(0xFFCCCCCC)),
                    modifier = Modifier.height(28.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = "Thinking: ${thinkingLabel(thinkingLevel)}",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color(0xFF666666)
                        )
                    }
                }

                DropdownMenu(
                    expanded = showThinkingMenu,
                    onDismissRequest = { showThinkingMenu = false }
                ) {
                    ThinkingMenuItem("off", thinkingLevel, onSetThinkingLevel) { showThinkingMenu = false }
                    ThinkingMenuItem("low", thinkingLevel, onSetThinkingLevel) { showThinkingMenu = false }
                    ThinkingMenuItem("medium", thinkingLevel, onSetThinkingLevel) { showThinkingMenu = false }
                    ThinkingMenuItem("high", thinkingLevel, onSetThinkingLevel) { showThinkingMenu = false }
                }
            }

            // Stop / Abort button (on RIGHT)
            if (pendingRunCount > 0) {
                Surface(
                    onClick = onAbort,
                    shape = RoundedCornerShape(14.dp),
                    color = Color(0xFFFFEBEE),
                    border = BorderStroke(1.dp, Color(0xFFFFCDD2)),
                    modifier = Modifier.height(28.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text("■", fontSize = 10.sp, color = Color(0xFFE53935))
                        Text(
                            text = "Stop",
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color(0xFFE53935)
                        )
                    }
                }
            }
        }

        // ── Attachments Strip ──
        if (attachments.isNotEmpty()) {
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                items(attachments.size) { index ->
                    val att = attachments[index]
                    Surface(
                        shape = RoundedCornerShape(14.dp),
                        color = Color(0xFFE3F2FD),
                        border = BorderStroke(1.dp, Color(0xFFCCCCCC)),
                        modifier = Modifier.height(28.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            Text(
                                text = att.fileName,
                                fontSize = 11.sp,
                                color = Color(0xFF333333),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.widthIn(max = 120.dp)
                            )
                            Text(
                                text = "×",
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color(0xFF999999),
                                modifier = Modifier.clickable { onRemoveAttachment(att.id) }
                            )
                        }
                    }
                }
            }
        }

        // ── Input Row ──
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            // Text input or Voice waveform
            if (agentState == AgentState.Listening) {
                Surface(
                    modifier = Modifier.weight(1f).height(36.dp),
                    shape = RoundedCornerShape(12.dp),
                    color = Color.White,
                    border = BorderStroke(1.dp, Color(0xFFE0E0E0))
                ) {
                    Row(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        if (!partialSttText.isNullOrBlank()) {
                            Text(
                                text = partialSttText,
                                fontSize = 13.sp,
                                color = Color(0xFF333333),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1f)
                            )
                        } else {
                            Text(
                                text = "Listening…",
                                fontSize = 13.sp,
                                color = Color(0xFF999999),
                                modifier = Modifier.weight(1f)
                            )
                        }
                        // Waveform animation
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(2.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val infiniteTransition = rememberInfiniteTransition()
                            for (i in 0..5) {
                                val scale by infiniteTransition.animateFloat(
                                    initialValue = 0.3f,
                                    targetValue = 1f,
                                    animationSpec = infiniteRepeatable(
                                        animation = tween(400, delayMillis = i * 60, easing = LinearEasing),
                                        repeatMode = RepeatMode.Reverse
                                    )
                                )
                                Box(
                                    modifier = Modifier
                                        .width(3.dp)
                                        .height(16.dp * scale)
                                        .clip(CircleShape)
                                        .background(Color(0xFF0A59F7))
                                )
                            }
                        }
                    }
                }

                // Cancel voice button
                Surface(
                    onClick = onCancelVoice,
                    shape = RoundedCornerShape(12.dp),
                    color = Color(0xFFFFEBEE),
                    modifier = Modifier.size(36.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Cancel voice",
                            tint = Color(0xFFE53935),
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }
            } else {
                Surface(
                    modifier = Modifier.weight(1f).height(36.dp),
                    shape = RoundedCornerShape(12.dp),
                    color = Color.White,
                    border = BorderStroke(1.dp, Color(0xFFE0E0E0))
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        BasicTextField(
                            value = input,
                            onValueChange = { input = it },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = androidx.compose.ui.text.TextStyle(
                                fontSize = 14.sp,
                                color = Color(0xFF333333)
                            ),
                            cursorBrush = SolidColor(Color(0xFF0A59F7)),
                            maxLines = 4,
                            decorationBox = { innerTextField ->
                                if (input.isEmpty()) {
                                    Text(
                                        text = "Ask anything...",
                                        fontSize = 14.sp,
                                        color = Color(0xFF999999)
                                    )
                                }
                                innerTextField()
                            }
                        )
                    }
                }

                // Add attachment button
                Surface(
                    onClick = { showAttachmentMenu = !showAttachmentMenu },
                    shape = RoundedCornerShape(12.dp),
                    color = Color(0xFFE3F2FD),
                    modifier = Modifier.size(36.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.Add,
                            contentDescription = "Attachments",
                            tint = Color(0xFF0A59F7),
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }

                // Voice mic button
                Surface(
                    onClick = onStartVoice,
                    enabled = healthOk && pendingRunCount == 0,
                    shape = RoundedCornerShape(12.dp),
                    color = Color(0xFFE3F2FD),
                    modifier = Modifier.size(36.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.Mic,
                            contentDescription = "Voice input",
                            tint = Color(0xFF0A59F7),
                            modifier = Modifier.size(20.dp)
                        )
                    }
                }

                // Send button (↑ style matching HarmonyOS)
                Surface(
                    onClick = {
                        if (canSend) {
                            val text = input
                            input = ""
                            onSend(text)
                        }
                    },
                    enabled = canSend,
                    shape = RoundedCornerShape(12.dp),
                    color = if (canSend) Color(0xFF0A59F7) else Color(0xFFE3F2FD),
                    modifier = Modifier.size(36.dp)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        if (sendBusy) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = Color.White
                            )
                        } else {
                            Text(
                                text = "↑",
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Bold,
                                color = if (canSend) Color.White else Color(0xFF0A59F7)
                            )
                        }
                    }
                }
            }
        }

        // ── Attachment Drawer Menu ──
        AnimatedVisibility(
            visible = showAttachmentMenu,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceAround,
                verticalAlignment = Alignment.CenterVertically
            ) {
                AttachmentMenuItem(icon = Icons.Default.PhotoLibrary, label = "Gallery") {
                    onPickImages()
                    showAttachmentMenu = false
                }
            }
        }
    }
}

@Composable
private fun AttachmentMenuItem(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.clickable { onClick() }
    ) {
        Surface(
            shape = RoundedCornerShape(14.dp),
            color = Color.White,
            border = BorderStroke(1.dp, Color(0xFFE0E0E0)),
            modifier = Modifier.size(48.dp)
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    icon,
                    contentDescription = label,
                    modifier = Modifier.size(22.dp),
                    tint = Color(0xFF333333)
                )
            }
        }
        Text(text = label, fontSize = 11.sp, color = Color(0xFF666666))
    }
}

@Composable
private fun ThinkingMenuItem(
    value: String,
    current: String,
    onSet: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(thinkingLabel(value), color = Color(0xFF333333), fontSize = 13.sp) },
        onClick = {
            onSet(value)
            onDismiss()
        },
        trailingIcon = {
            if (value == current.trim().lowercase()) {
                Icon(
                    Icons.Default.Check,
                    contentDescription = null,
                    tint = Color(0xFF0A59F7),
                    modifier = Modifier.size(16.dp)
                )
            }
        },
    )
}

private fun thinkingLabel(raw: String): String {
    return when (raw.trim().lowercase()) {
        "low" -> "Low"
        "medium" -> "Medium"
        "high" -> "High"
        else -> "Off"
    }
}
