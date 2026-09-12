package ai.axiomaster.bonio.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.i18n.AppStrings
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.remote.memory.BonioMemo
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun MemoryTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier
) {
    val strings = LocalAppStrings.current
    val memos by viewModel.memoryRepository.memos.collectAsState()
    val loading by viewModel.memoryRepository.loading.collectAsState()
    val error by viewModel.memoryRepository.error.collectAsState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var searchText by remember { mutableStateOf("") }
    var selectedTag by remember { mutableStateOf("") }
    var selectedMemory by remember { mutableStateOf<BonioMemo?>(null) }
    var pendingDelete by remember { mutableStateOf<BonioMemo?>(null) }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.memoryRepository.refresh()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.memoryRepository.refresh()
    }

    if (selectedMemory != null) {
        MemoryDetailView(
            memory = selectedMemory!!,
            strings = strings,
            onBack = { selectedMemory = null },
            onDelete = { pendingDelete = selectedMemory },
            onOpenSource = { url ->
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                    context.startActivity(intent)
                } catch (_: Throwable) {}
            }
        )
    } else {
        Column(
            modifier = modifier
                .fillMaxSize()
                .background(Color.White)
        ) {
            // ── Search Bar + Refresh Button ──
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 12.dp, top = 12.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                OutlinedTextField(
                    value = searchText,
                    onValueChange = { searchText = it },
                    placeholder = {
                        Text(
                            text = strings.searchMemoryPlaceholder,
                            fontSize = 14.sp,
                            color = Color(0xFF98A2B3)
                        )
                    },
                    singleLine = true,
                    shape = RoundedCornerShape(8.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = Color(0xFFEFF3F8),
                        unfocusedContainerColor = Color(0xFFEFF3F8),
                        disabledContainerColor = Color(0xFFEFF3F8),
                        focusedBorderColor = Color.Transparent,
                        unfocusedBorderColor = Color.Transparent
                    ),
                    modifier = Modifier
                        .weight(1f)
                        .height(48.dp)
                )

                IconButton(
                    onClick = { viewModel.memoryRepository.refresh() },
                    modifier = Modifier
                        .padding(start = 6.dp)
                        .size(40.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Refresh,
                        contentDescription = "Refresh",
                        tint = Color(0xFF0A59F7)
                    )
                }
            }

            // ── Horizontal Tag Chips with Counters ──
            val tags = remember(memos) {
                val counts = mutableMapOf<String, Int>()
                memos.forEach { m ->
                    m.tags.forEach { t ->
                        counts[t] = (counts[t] ?: 0) + 1
                    }
                }
                counts.entries.sortedByDescending { it.value }.map { it.key }
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // "全部" Chip
                TagChip(
                    text = "${strings.memoryTagAll} ${memos.size}",
                    isSelected = selectedTag.isEmpty(),
                    onClick = { selectedTag = "" }
                )

                // Dynamic Category Chips
                tags.forEach { tag ->
                    val count = memos.count { it.tags.contains(tag) }
                    TagChip(
                        text = "$tag $count",
                        isSelected = selectedTag == tag,
                        onClick = {
                            selectedTag = if (selectedTag == tag) "" else tag
                        }
                    )
                }
            }

            if (!error.isNullOrBlank()) {
                Text(
                    text = error!!,
                    fontSize = 12.sp,
                    color = Color(0xFFD92D20),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp)
                )
            }

            // ── Memory Content / List ──
            val filteredMemos = remember(memos, searchText, selectedTag) {
                val query = searchText.trim().lowercase(Locale.getDefault())
                memos.filter { memo ->
                    if (selectedTag.isNotEmpty() && !memo.tags.contains(selectedTag)) return@filter false
                    if (query.isEmpty()) return@filter true
                    val hay = listOfNotNull(
                        memo.title,
                        memo.content,
                        memo.sourceApp,
                        memo.pageTitle,
                        memo.source
                    ).plus(memo.tags).joinToString(" ").lowercase(Locale.getDefault())
                    hay.contains(query)
                }
            }

            when {
                loading && memos.isEmpty() -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(
                            color = Color(0xFF0A59F7),
                            modifier = Modifier.size(28.dp)
                        )
                    }
                }
                filteredMemos.isEmpty() -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text(
                            text = "▤",
                            fontSize = 46.sp,
                            color = Color(0xFFB7C5D9)
                        )
                        Spacer(modifier = Modifier.height(10.dp))
                        Text(
                            text = if (memos.isEmpty()) strings.memoryEmpty else "没有匹配的记忆",
                            fontSize = 16.sp,
                            color = Color(0xFF667085)
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .padding(horizontal = 16.dp)
                    ) {
                        items(filteredMemos, key = { it.id }) { memo ->
                            MemoryRow(
                                memo = memo,
                                strings = strings,
                                onClick = {
                                    scope.launch {
                                        val detailed = viewModel.memoryRepository.get(memo.id) ?: memo
                                        selectedMemory = detailed
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    pendingDelete?.let { memo ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = {
                Text(
                    text = strings.memoryDeleteConfirmTitle,
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF172033)
                )
            },
            text = {
                Text(
                    text = strings.memoryDeleteConfirmMessage,
                    fontSize = 14.sp,
                    color = Color(0xFF667085)
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        viewModel.memoryRepository.delete(memo.id)
                        if (selectedMemory?.id == memo.id) {
                            selectedMemory = null
                        }
                        pendingDelete = null
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFD92D20),
                        contentColor = Color.White
                    ),
                    shape = RoundedCornerShape(8.dp)
                ) {
                    Text(strings.memoryDeleteConfirm)
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) {
                    Text(strings.memoryDeleteCancel, color = Color(0xFF4D5B70))
                }
            },
            containerColor = Color.White,
            shape = RoundedCornerShape(16.dp)
        )
    }
}

@Composable
private fun TagChip(
    text: String,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(15.dp),
        color = if (isSelected) Color(0xFF0A59F7) else Color.White,
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            if (isSelected) Color(0xFF0A59F7) else Color(0xFFD8E1EF)
        ),
        modifier = Modifier.height(30.dp)
    ) {
        Box(
            modifier = Modifier.padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = text,
                fontSize = 12.sp,
                fontWeight = if (isSelected) FontWeight.Medium else FontWeight.Normal,
                color = if (isSelected) Color.White else Color(0xFF4D5B70)
            )
        }
    }
}

@Composable
private fun MemoryRow(
    memo: BonioMemo,
    strings: AppStrings,
    onClick: () -> Unit
) {
    val coverBitmap = rememberBase64Image(memo.coverImage)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // 50x50 Thumbnail / Icon
        if (coverBitmap != null) {
            Image(
                bitmap = coverBitmap,
                contentDescription = "Cover",
                modifier = Modifier
                    .size(50.dp)
                    .clip(RoundedCornerShape(6.dp)),
                contentScale = ContentScale.Crop
            )
        } else {
            val isMsdp = memo.source.startsWith("msdp_")
            Box(
                modifier = Modifier
                    .size(50.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFFE8F1FF)),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = if (isMsdp) "◇" else "▤",
                    fontSize = 22.sp,
                    color = Color(0xFF0A59F7),
                    textAlign = TextAlign.Center
                )
            }
        }

        Spacer(modifier = Modifier.width(12.dp))

        Column(modifier = Modifier.weight(1f)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = memo.title.ifBlank { "无标题" },
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(0xFF1D2939),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = formatMemoryDate(memo.createdAt, strings),
                    fontSize = 11.sp,
                    color = Color(0xFF8A97A9),
                    modifier = Modifier.padding(start = 8.dp)
                )
            }

            Text(
                text = memo.content,
                fontSize = 13.sp,
                color = Color(0xFF667085),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 4.dp)
            )

            // Tags row
            val visibleTags = memo.tags.take(3)
            if (visibleTags.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    visibleTags.forEach { tag ->
                        val isBehavior = tag.startsWith("行为:")
                        Surface(
                            shape = RoundedCornerShape(3.dp),
                            color = if (isBehavior) Color(0xFFECFDF3) else Color(0xFFE8F1FF)
                        ) {
                            Text(
                                text = tag,
                                fontSize = 11.sp,
                                color = if (isBehavior) Color(0xFF027A48) else Color(0xFF0A59F7),
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                }
            }
        }
    }
    HorizontalDivider(thickness = 1.dp, color = Color(0xFFE8EDF5))
}

@Composable
private fun MemoryDetailView(
    memory: BonioMemo,
    strings: AppStrings,
    onBack: () -> Unit,
    onDelete: () -> Unit,
    onOpenSource: (String) -> Unit
) {
    val originalBitmap = rememberBase64Image(memory.originalImage ?: memory.coverImage)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
    ) {
        // ── Detail Top Bar ──
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(58.dp)
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                    contentDescription = "Back",
                    tint = Color(0xFF0A59F7)
                )
            }

            Text(
                text = strings.memoryDetailTitle,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF172033),
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp)
            )

            TextButton(onClick = onDelete) {
                Text(
                    text = strings.memoryDelete,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(0xFFD92D20)
                )
            }
        }

        // ── Scrollable Detail Body ──
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
        ) {
            Text(
                text = memory.title.ifBlank { "无标题" },
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF172033)
            )

            val sourceName = memory.pageTitle ?: memory.sourceApp ?: memory.source.ifBlank { "屏幕内容" }
            Text(
                text = "${strings.memorySourceLabel}: $sourceName",
                fontSize = 13.sp,
                color = Color(0xFF667085),
                modifier = Modifier.padding(top = 8.dp)
            )

            Text(
                text = formatMemoryDate(memory.createdAt, strings),
                fontSize = 12.sp,
                color = Color(0xFF98A2B3),
                modifier = Modifier.padding(top = 4.dp)
            )

            if (originalBitmap != null) {
                Spacer(modifier = Modifier.height(16.dp))
                Image(
                    bitmap = originalBitmap,
                    contentDescription = "Memory Image",
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 360.dp)
                        .clip(RoundedCornerShape(8.dp)),
                    contentScale = ContentScale.Fit
                )
            }

            if (memory.tags.isNotEmpty()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState())
                        .padding(top = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    memory.tags.forEach { tag ->
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = Color(0xFFE8F1FF)
                        ) {
                            Text(
                                text = tag,
                                fontSize = 12.sp,
                                color = Color(0xFF0A59F7),
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
                            )
                        }
                    }
                }
            }

            HorizontalDivider(
                modifier = Modifier.padding(vertical = 20.dp),
                thickness = 1.dp,
                color = Color(0xFFE8EDF5)
            )

            Text(
                text = memory.content,
                fontSize = 16.sp,
                color = Color(0xFF344054),
                lineHeight = 24.sp
            )

            if (!memory.pageLink.isNullOrBlank()) {
                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = { onOpenSource(memory.pageLink) },
                    shape = RoundedCornerShape(6.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color(0xFFE8F1FF),
                        contentColor = Color(0xFF0A59F7)
                    )
                ) {
                    Text(strings.memoryOpenSource, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                }

                Text(
                    text = memory.pageLink,
                    fontSize = 12.sp,
                    color = Color(0xFF667085),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 8.dp)
                )
            }
        }
    }
}

@Composable
fun rememberBase64Image(base64: String?): ImageBitmap? {
    return remember(base64) {
        if (base64.isNullOrEmpty()) null
        else {
            try {
                val clean = if (base64.contains(",")) base64.substringAfter(",") else base64
                val bytes = android.util.Base64.decode(clean, android.util.Base64.DEFAULT)
                android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
            } catch (_: Throwable) {
                null
            }
        }
    }
}

private fun formatMemoryDate(timestamp: Long?, strings: AppStrings): String {
    if (timestamp == null || timestamp <= 0) return ""
    val now = System.currentTimeMillis()
    val diff = now - timestamp
    return when {
        diff < 60 * 1000 -> strings.memoryTimeJustNow
        diff < 60 * 60 * 1000 -> "${diff / 60000} ${strings.memoryTimeMinutesAgo}"
        diff < 24 * 60 * 60 * 1000 -> "${diff / 3600000} ${strings.memoryTimeHoursAgo}"
        diff < 48 * 60 * 60 * 1000 -> strings.memoryTimeYesterday
        else -> {
            val date = Date(timestamp)
            val sdf = SimpleDateFormat("MM-dd", Locale.getDefault())
            sdf.format(date)
        }
    }
}
