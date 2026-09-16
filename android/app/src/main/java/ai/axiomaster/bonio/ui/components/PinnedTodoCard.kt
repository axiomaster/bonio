package ai.axiomaster.bonio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.remote.todo.TodoItem
import ai.axiomaster.bonio.ui.theme.LocalAppColors

/**
 * 记忆 (Memory) 顶部的固定置顶待办卡片
 */
@Composable
fun PinnedTodoCard(
    todos: List<TodoItem>,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val colors = LocalAppColors.current
    val pendingTodos = todos.filter { !it.isCompleted }
    val pendingCount = pendingTodos.size

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(colors.surface)
            .border(1.dp, colors.border.copy(alpha = 0.8f), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick)
            .padding(14.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            // Header Row: 图标 + 标题 + 状态 Badge + 查看全部 >
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // 图标背景
                    Box(
                        modifier = Modifier
                            .size(28.dp)
                            .clip(CircleShape)
                            .background(colors.accent.copy(alpha = 0.15f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "📌",
                            fontSize = 14.sp
                        )
                    }

                    Spacer(modifier = Modifier.width(8.dp))

                    Text(
                        text = "备忘提醒",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.textPrimary
                    )

                    Spacer(modifier = Modifier.width(8.dp))

                    // 状态徽标
                    val badgeText = when {
                        todos.isEmpty() -> "暂无待办"
                        pendingCount > 0 -> "$pendingCount 项待处理"
                        else -> "全部已完成 ✓"
                    }
                    val badgeBg = when {
                        pendingCount > 0 -> colors.accent.copy(alpha = 0.15f)
                        todos.isEmpty() -> colors.inputBackground
                        else -> Color(0xFF10B981).copy(alpha = 0.15f)
                    }
                    val badgeColor = when {
                        pendingCount > 0 -> colors.accent
                        todos.isEmpty() -> colors.textTertiary
                        else -> Color(0xFF10B981)
                    }

                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(12.dp))
                            .background(badgeBg)
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                    ) {
                        Text(
                            text = badgeText,
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            color = badgeColor
                        )
                    }
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = "查看全部",
                        fontSize = 12.sp,
                        color = colors.accent
                    )
                    Text(
                        text = " ›",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = colors.accent
                    )
                }
            }

            Spacer(modifier = Modifier.height(10.dp))

            // Body: 预览最近待办或提示
            if (pendingTodos.isNotEmpty()) {
                val previewItems = pendingTodos.take(2)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    previewItems.forEach { item ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(colors.inputBackground.copy(alpha = 0.6f))
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = item.task,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = colors.textPrimary,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )

                                // 要素胶囊
                                Row(
                                    modifier = Modifier.padding(top = 3.dp),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    item.time?.let { time ->
                                        TagBadge(text = "⏰ $time", color = Color(0xFF3B82F6))
                                    }
                                    item.location?.let { loc ->
                                        TagBadge(text = "📍 $loc", color = Color(0xFF10B981))
                                    }
                                    item.person?.let { person ->
                                        TagBadge(text = "👤 $person", color = Color(0xFFF59E0B))
                                    }
                                    item.sourceApp?.let { app ->
                                        TagBadge(text = app, color = colors.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text(
                    text = "自动提取短信还款、微信开会、日程等通知中的待办事项",
                    fontSize = 12.sp,
                    color = colors.textTertiary,
                    modifier = Modifier.padding(vertical = 2.dp)
                )
            }
        }
    }
}

@Composable
private fun TagBadge(text: String, color: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 5.dp, vertical = 1.5.dp)
    ) {
        Text(
            text = text,
            fontSize = 10.sp,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}
