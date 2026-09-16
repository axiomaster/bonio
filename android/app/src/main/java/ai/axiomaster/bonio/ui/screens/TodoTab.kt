package ai.axiomaster.bonio.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.remote.todo.TodoItem
import ai.axiomaster.bonio.ui.theme.LocalAppColors

enum class TodoFilter {
    ALL, PENDING, COMPLETED
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodoTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val strings = LocalAppStrings.current
    val colors = LocalAppColors.current
    val context = LocalContext.current
    val todos by viewModel.todoRepository.todos.collectAsState()
    var filter by remember { mutableStateOf(TodoFilter.ALL) }
    var showAddDialog by remember { mutableStateOf(false) }
    var syncing by remember { mutableStateOf(false) }
    var syncTrigger by remember { mutableStateOf(0) }

    val calendarPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) syncTrigger++
        else android.widget.Toast.makeText(context, "未授予日历权限，无法同步待办", android.widget.Toast.LENGTH_SHORT).show()
    }

    LaunchedEffect(syncTrigger) {
        if (syncTrigger == 0) return@LaunchedEffect
        syncing = true
        val result = viewModel.todoRepository.syncFromCalendar()
        syncing = false
        val message = when {
            result.permissionDenied -> "未授予日历权限，无法同步"
            result.error != null -> "日历同步失败：${result.error}"
            result.totalEvents == 0 -> "日历暂无未来 7 天的日程"
            result.added == 0 -> "日历日程已是最新（共 ${result.totalEvents} 项）"
            else -> "已从日历同步 ${result.added} 项待办"
        }
        android.widget.Toast.makeText(context, message, android.widget.Toast.LENGTH_SHORT).show()
    }

    val pendingCount = todos.count { !it.isCompleted }
    val completedCount = todos.count { it.isCompleted }

    val filteredTodos = remember(todos, filter) {
        when (filter) {
            TodoFilter.ALL -> todos
            TodoFilter.PENDING -> todos.filter { !it.isCompleted }
            TodoFilter.COMPLETED -> todos.filter { it.isCompleted }
        }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(colors.background)
    ) {
        // ── 顶部导航栏 ──
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = strings.tabTodo,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary
                )
                Spacer(modifier = Modifier.width(6.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(colors.inputBackground)
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                ) {
                    Text(
                        text = "${todos.size}",
                        fontSize = 11.sp,
                        color = colors.textSecondary
                    )
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = {
                        val granted = androidx.core.content.ContextCompat.checkSelfPermission(
                            context, android.Manifest.permission.READ_CALENDAR
                        ) == PackageManager.PERMISSION_GRANTED
                        if (granted) syncTrigger++
                        else calendarPermissionLauncher.launch(Manifest.permission.READ_CALENDAR)
                    },
                    enabled = !syncing
                ) {
                    if (syncing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = colors.accent
                        )
                    } else {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = "从日历同步待办",
                            tint = colors.accent
                        )
                    }
                }
                IconButton(onClick = { showAddDialog = true }) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = "新增待办",
                        tint = colors.accent
                    )
                }
            }
        }

        // ── 筛选 Tabs ──
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            FilterTabButton(
                text = "全部 (${todos.size})",
                isSelected = filter == TodoFilter.ALL,
                onClick = { filter = TodoFilter.ALL }
            )
            FilterTabButton(
                text = "待处理 ($pendingCount)",
                isSelected = filter == TodoFilter.PENDING,
                onClick = { filter = TodoFilter.PENDING }
            )
            FilterTabButton(
                text = "已完成 ($completedCount)",
                isSelected = filter == TodoFilter.COMPLETED,
                onClick = { filter = TodoFilter.COMPLETED }
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // ── 待办列表 ──
        if (filteredTodos.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = "📝",
                        fontSize = 40.sp
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = when (filter) {
                            TodoFilter.COMPLETED -> "暂无已完成的待办"
                            TodoFilter.PENDING -> "太棒了！所有待办已全部完成"
                            TodoFilter.ALL -> "暂无待办事项"
                        },
                        fontSize = 14.sp,
                        color = colors.textSecondary
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    Text(
                        text = "接收到短信还款、微信开会等通知时会自动提取待办",
                        fontSize = 12.sp,
                        color = colors.textTertiary
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                contentPadding = PaddingValues(bottom = 24.dp)
            ) {
                items(filteredTodos, key = { it.id }) { item ->
                    TodoItemCard(
                        item = item,
                        onToggle = { viewModel.todoRepository.toggleTodo(item.id) },
                        onDelete = { viewModel.todoRepository.deleteTodo(item.id) }
                    )
                }
            }
        }
    }

    // ── 手动添加待办弹窗 ──
    if (showAddDialog) {
        AddTodoDialog(
            onDismiss = { showAddDialog = false },
            onConfirm = { task, time, loc, person ->
                viewModel.todoRepository.addTodo(
                    TodoItem(
                        task = task,
                        time = time.ifBlank { null },
                        location = loc.ifBlank { null },
                        person = person.ifBlank { null },
                        sourceApp = "手动添加"
                    )
                )
                showAddDialog = false
            }
        )
    }
}

@Composable
private fun FilterTabButton(
    text: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    val colors = LocalAppColors.current
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(if (isSelected) colors.accent else colors.inputBackground)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        Text(
            text = text,
            fontSize = 12.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isSelected) Color.White else colors.textSecondary
        )
    }
}

@Composable
private fun TodoItemCard(
    item: TodoItem,
    onToggle: () -> Unit,
    onDelete: () -> Unit
) {
    val colors = LocalAppColors.current
    var showRaw by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(colors.surface)
            .border(1.dp, colors.border.copy(alpha = 0.6f), RoundedCornerShape(12.dp))
            .padding(12.dp)
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.Top
            ) {
                // 圆形 Checkbox
                Box(
                    modifier = Modifier
                        .size(24.dp)
                        .clip(CircleShape)
                        .background(if (item.isCompleted) Color(0xFF10B981) else Color.Transparent)
                        .border(
                            2.dp,
                            if (item.isCompleted) Color(0xFF10B981) else colors.border,
                            CircleShape
                        )
                        .clickable(onClick = onToggle),
                    contentAlignment = Alignment.Center
                ) {
                    if (item.isCompleted) {
                        Icon(
                            imageVector = Icons.Default.Check,
                            contentDescription = "已完成",
                            tint = Color.White,
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }

                Spacer(modifier = Modifier.width(10.dp))

                // 核心内容
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = item.task,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = if (item.isCompleted) colors.textTertiary else colors.textPrimary,
                        textDecoration = if (item.isCompleted) TextDecoration.LineThrough else TextDecoration.None
                    )

                    // 标签行
                    Row(
                        modifier = Modifier.padding(top = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        item.time?.let { time ->
                            DetailTag(text = "⏰ $time", color = Color(0xFF3B82F6))
                        }
                        item.location?.let { loc ->
                            DetailTag(text = "📍 $loc", color = Color(0xFF10B981))
                        }
                        item.person?.let { person ->
                            DetailTag(text = "👤 $person", color = Color(0xFFF59E0B))
                        }
                        item.sourceApp?.let { app ->
                            DetailTag(text = app, color = colors.textTertiary)
                        }
                    }

                    // 展开原文
                    if (!item.rawText.isNullOrBlank()) {
                        Spacer(modifier = Modifier.height(4.dp))
                        Row(
                            modifier = Modifier.clickable { showRaw = !showRaw },
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = if (showRaw) "收起通知原文 ▲" else "查看通知原文 ▼",
                                fontSize = 11.sp,
                                color = colors.accent
                            )
                        }

                        AnimatedVisibility(visible = showRaw) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 4.dp)
                                    .clip(RoundedCornerShape(6.dp))
                                    .background(colors.inputBackground)
                                    .padding(8.dp)
                            ) {
                                Text(
                                    text = item.rawText,
                                    fontSize = 11.sp,
                                    color = colors.textSecondary,
                                    lineHeight = 16.sp
                                )
                            }
                        }
                    }
                }

                // 删除按钮
                IconButton(
                    onClick = onDelete,
                    modifier = Modifier.size(28.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = "删除",
                        tint = colors.textTertiary,
                        modifier = Modifier.size(16.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailTag(text: String, color: Color) {
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(4.dp))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 6.dp, vertical = 2.dp)
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

@Composable
private fun AddTodoDialog(
    onDismiss: () -> Unit,
    onConfirm: (task: String, time: String, loc: String, person: String) -> Unit
) {
    val colors = LocalAppColors.current
    var task by remember { mutableStateOf("") }
    var time by remember { mutableStateOf("") }
    var loc by remember { mutableStateOf("") }
    var person by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = "新建待办",
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary
            )
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = task,
                    onValueChange = { task = it },
                    label = { Text("待办任务 (必填)") },
                    placeholder = { Text("例: 招行信用卡还款 5000元") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = time,
                    onValueChange = { time = it },
                    label = { Text("时间 (选填)") },
                    placeholder = { Text("例: 09月25日 / 明早10点") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = loc,
                    onValueChange = { loc = it },
                    label = { Text("地点 (选填)") },
                    placeholder = { Text("例: A座302会议室") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = person,
                    onValueChange = { person = it },
                    label = { Text("相关人/机构 (选填)") },
                    placeholder = { Text("例: 招商银行 / 张总") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { if (task.isNotBlank()) onConfirm(task, time, loc, person) },
                enabled = task.isNotBlank()
            ) {
                Text("确定", color = if (task.isNotBlank()) colors.accent else colors.textTertiary)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("取消", color = colors.textSecondary)
            }
        },
        containerColor = colors.surface
    )
}
