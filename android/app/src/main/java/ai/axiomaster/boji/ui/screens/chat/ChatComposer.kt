package ai.axiomaster.boji.ui.screens.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import ai.axiomaster.boji.ai.AgentManager
import ai.axiomaster.boji.ai.AgentState
import androidx.compose.animation.core.*
import ai.axiomaster.boji.ui.screens.PendingImageAttachment
import androidx.compose.ui.platform.LocalContext

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
    val context = LocalContext.current
    var input by rememberSaveable { mutableStateOf("") }
    var showThinkingMenu by remember { mutableStateOf(false) }
    var showAttachmentMenu by remember { mutableStateOf(false) }

    val agentState by AgentManager.stateManager.currentState.collectAsState()


    val canSend = pendingRunCount == 0 && (input.trim().isNotEmpty() || attachments.isNotEmpty()) && healthOk
    val sendBusy = pendingRunCount > 0

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 20.dp) // Lift off the bottom edge
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                if (showAttachmentMenu) showAttachmentMenu = false
            },
        verticalArrangement = Arrangement.spacedBy(6.dp) // Tighter vertical spacing
    ) {
        // --- Top Control Row (Continue, Stop, Thinking Level) ---
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            if (pendingRunCount > 0) {
                ControlChip(
                    label = "Stop",
                    icon = Icons.Default.Stop,
                    onClick = onAbort
                )
            } else {
                ControlChip(
                    label = "Continue",
                    icon = Icons.Default.Refresh,
                    onClick = onRefresh
                )
            }

            Box {
                ControlChip(
                    label = "Thinking: ${thinkingLabel(thinkingLevel)}",
                    icon = Icons.Default.AutoAwesome,
                    onClick = { showThinkingMenu = true }
                )
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
        }

        // --- Attachments List (Small Chips) ---
        if (attachments.isNotEmpty()) {
            AttachmentsStrip(attachments = attachments, onRemoveAttachment = onRemoveAttachment)
        }

        // --- Bottom Input Area ---
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = mobileSurface,
            border = androidx.compose.foundation.BorderStroke(1.dp, mobileBorder)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 2.dp), // Extremely tight vertical padding
                verticalAlignment = Alignment.CenterVertically, // Center vertically for compact look
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                // Auto-growing Basic Text Field or Waveform
                if (agentState == AgentState.Listening) {
                    Column(
                        modifier = Modifier.weight(1f).padding(vertical = 6.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        if (!partialSttText.isNullOrBlank()) {
                            Text(
                                text = partialSttText,
                                style = mobileCallout,
                                color = mobileText,
                                maxLines = 3,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceEvenly,
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val infiniteTransition = rememberInfiniteTransition()
                            for (i in 0..10) {
                                val scale by infiniteTransition.animateFloat(
                                    initialValue = 0.3f,
                                    targetValue = 1f,
                                    animationSpec = infiniteRepeatable(
                                        animation = tween(400, delayMillis = i * 50, easing = LinearEasing),
                                        repeatMode = RepeatMode.Reverse
                                    )
                                )
                                Box(modifier = Modifier.width(4.dp).height(16.dp * scale).clip(CircleShape).background(mobileAccent))
                            }
                        }
                    }
                } else {
                    androidx.compose.foundation.text.BasicTextField(
                        value = input,
                        onValueChange = { input = it },
                        modifier = Modifier
                            .weight(1f)
                            .padding(vertical = 8.dp), // This defines the "2x text height" approx
                        textStyle = mobileCallout.copy(color = mobileText),
                        cursorBrush = androidx.compose.ui.graphics.SolidColor(mobileAccent),
                        maxLines = 6,
                        decorationBox = { innerTextField ->
                            if (input.isEmpty()) {
                                Text("Ask anything...", style = mobileCallout, color = mobileTextTertiary)
                            }
                            innerTextField()
                        }
                    )
                }

                // Dynamic Action Buttons
                val isTyping = input.trim().isNotEmpty()
                if (agentState == AgentState.Listening) {
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(mobileDanger.copy(alpha = 0.15f))
                            .clickable { onCancelVoice() },
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Cancel voice",
                            tint = mobileDanger,
                            modifier = Modifier.size(20.dp)
                        )
                    }
                } else if (isTyping || attachments.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .size(32.dp)
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (canSend) mobileAccent else mobileAccentSoft)
                            .clickable(enabled = canSend) {
                                val text = input
                                input = ""
                                onSend(text)
                            },
                        contentAlignment = Alignment.Center
                    ) {
                        if (sendBusy) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Color.White)
                        } else {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                                contentDescription = "Send",
                                tint = if (canSend) Color.White else mobileAccent,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                } else {
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .background(mobileAccentSoft)
                                .clickable { showAttachmentMenu = !showAttachmentMenu },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Add,
                                contentDescription = "Attachments",
                                tint = mobileAccent,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                        Box(
                            modifier = Modifier
                                .size(32.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .background(if (healthOk && pendingRunCount == 0) mobileAccent else mobileAccentSoft)
                                .clickable(enabled = healthOk && pendingRunCount == 0) { onStartVoice() },
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Mic,
                                contentDescription = "Voice input",
                                tint = if (healthOk && pendingRunCount == 0) Color.White else mobileAccent,
                                modifier = Modifier.size(20.dp)
                            )
                        }
                    }
                }
            }
        }

        // --- Expanded Attachment Menu (Slide-up drawer) ---
        AnimatedVisibility(
            visible = showAttachmentMenu,
            enter = expandVertically() + fadeIn(),
            exit = shrinkVertically() + fadeOut()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 12.dp), // Tighter vertical padding
                horizontalArrangement = Arrangement.SpaceAround,
                verticalAlignment = Alignment.CenterVertically
            ) {
                AttachmentMenuItem(icon = Icons.Default.CameraAlt, label = "Camera") {
                    // TODO: Camera logic
                    showAttachmentMenu = false
                }
                AttachmentMenuItem(icon = Icons.Default.PhotoLibrary, label = "Gallery") {
                    onPickImages()
                    showAttachmentMenu = false
                }
                AttachmentMenuItem(icon = Icons.Default.Description, label = "File") {
                    // TODO: File picker logic
                    showAttachmentMenu = false
                }
            }
        }
    }
}

@Composable
private fun ControlChip(
    label: String,
    icon: ImageVector,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(10.dp), // Tighter rounded corners
        color = Color.White,
        border = androidx.compose.foundation.BorderStroke(1.dp, mobileBorderStrong)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp), // Slimmer chip padding
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Icon(icon, contentDescription = null, size = 14.dp, tint = if (enabled) mobileTextSecondary else mobileTextTertiary)
            Text(
                text = label,
                style = mobileCaption1.copy(fontWeight = FontWeight.SemiBold),
                color = if (enabled) mobileTextSecondary else mobileTextTertiary
            )
        }
    }
}

@Composable
private fun Icon(icon: ImageVector, contentDescription: String?, size: androidx.compose.ui.unit.Dp, tint: Color) {
    Icon(icon, contentDescription, modifier = Modifier.size(size), tint = tint)
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
            shape = RoundedCornerShape(16.dp), // Rounded rectangle instead of circle
            color = Color.White,
            border = androidx.compose.foundation.BorderStroke(1.dp, mobileBorder),
            modifier = Modifier.size(52.dp) // Slightly smaller
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(24.dp), tint = mobileText)
            }
        }
        Text(text = label, style = mobileCaption2, color = mobileTextSecondary) // Smaller text
    }
}

@Composable
private fun SecondaryActionButton(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    compact: Boolean = false,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = if (compact) Modifier.size(44.dp) else Modifier.height(44.dp),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.White,
            contentColor = mobileTextSecondary,
            disabledContainerColor = Color.White,
            disabledContentColor = mobileTextTertiary,
        ),
        border = BorderStroke(1.dp, mobileBorderStrong),
        contentPadding = if (compact) PaddingValues(0.dp) else ButtonDefaults.ContentPadding,
    ) {
        Icon(icon, contentDescription = label, modifier = Modifier.size(14.dp))
        if (!compact) {
            Spacer(modifier = Modifier.width(5.dp))
            Text(
                text = label,
                style = mobileCallout.copy(fontWeight = FontWeight.SemiBold),
                color = if (enabled) mobileTextSecondary else mobileTextTertiary,
            )
        }
    }
}

@Composable
private fun AttachmentsStrip(
    attachments: List<PendingImageAttachment>,
    onRemoveAttachment: (id: String) -> Unit,
) {
    androidx.compose.foundation.lazy.LazyRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(attachments.size) { index ->
            val att = attachments[index]
            AttachmentChip(
                fileName = att.fileName,
                onRemove = { onRemoveAttachment(att.id) },
            )
        }
    }
}

@Composable
private fun AttachmentChip(fileName: String, onRemove: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(999.dp),
        color = mobileAccentSoft,
        border = BorderStroke(1.dp, mobileBorderStrong),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = fileName,
                style = mobileCaption1,
                color = mobileText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Surface(
                onClick = onRemove,
                shape = androidx.compose.foundation.shape.CircleShape,
                color = Color.White,
                border = BorderStroke(1.dp, mobileBorderStrong),
            ) {
                Text(
                    text = "×",
                    style = mobileCaption1.copy(fontWeight = FontWeight.Bold),
                    color = mobileTextSecondary,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
                )
            }
        }
    }
}

@Composable
private fun SecondaryIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(44.dp),
        shape = RoundedCornerShape(14.dp),
        color = Color.White,
        border = BorderStroke(1.dp, mobileBorderStrong),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(18.dp), tint = if (enabled) mobileTextSecondary else mobileTextTertiary)
        }
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
        text = { Text(thinkingLabel(value), color = mobileText) },
        onClick = {
            onSet(value)
            onDismiss()
        },
        trailingIcon = {
            if (value == current.trim().lowercase()) {
                Icon(Icons.Default.Check, contentDescription = null, tint = mobileAccent, modifier = Modifier.size(16.dp))
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
