package ai.axiomaster.bonio.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.remote.memory.BonioMemo
import ai.axiomaster.bonio.ui.screens.chat.*
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun MemoryTab(
  viewModel: MainViewModel,
  modifier: Modifier = Modifier
) {
  val memos by viewModel.memoryRepository.memos.collectAsState()
  val loading by viewModel.memoryRepository.loading.collectAsState()
  val error by viewModel.memoryRepository.error.collectAsState()
  val isConnected by viewModel.isConnected.collectAsState()

  var showAddDialog by remember { mutableStateOf(false) }
  var pendingDelete by remember { mutableStateOf<BonioMemo?>(null) }

  val dateFormat = remember { SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()) }

  LaunchedEffect(Unit) { viewModel.memoryRepository.refresh() }

  Box(modifier = modifier.fillMaxSize().background(mobileBackgroundGradient)) {
    Column(modifier = Modifier.fillMaxSize()) {
      // Header
      Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
      ) {
        Row(
          modifier = Modifier.fillMaxWidth(),
          verticalAlignment = Alignment.CenterVertically,
          horizontalArrangement = Arrangement.SpaceBetween
        ) {
          Text("记一记", style = mobileTitle2, color = mobileText)
          Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IconButton(onClick = { viewModel.memoryRepository.refresh() }, enabled = isConnected) {
              Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = mobileAccent)
            }
            Button(
              onClick = { showAddDialog = true },
              enabled = isConnected,
              shape = RoundedCornerShape(12.dp),
              colors = ButtonDefaults.buttonColors(containerColor = mobileAccent, contentColor = Color.White),
              contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
            ) {
              Text("记一笔", style = mobileCallout.copy(fontWeight = FontWeight.Bold))
            }
          }
        }
        Text(
          if (isConnected) "头像双击也会自动保存重要页面" else "连接后端后可查看与保存记忆",
          style = mobileCallout,
          color = mobileTextSecondary
        )
      }

      when {
        !isConnected -> EmptyMemoryHint("未连接后端")
        loading && memos.isEmpty() -> EmptyMemoryHint("加载中…")
        error != null && memos.isEmpty() -> EmptyMemoryHint("加载失败：$error")
        memos.isEmpty() -> EmptyMemoryHint("还没有记忆。双击头像或点「记一笔」保存第一条。")
        else -> {
          LazyColumn(
            state = rememberLazyListState(),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
          ) {
            items(memos.size) { index ->
              val memo = memos[index]
              MemoCard(
                memo = memo,
                createdAtText = memo.createdAt?.let { dateFormat.format(Date(it)) }.orEmpty(),
                onDelete = { pendingDelete = memo },
              )
            }
            item { Spacer(modifier = Modifier.height(24.dp)) }
          }
        }
      }
    }

    if (showAddDialog) {
      AddMemoDialog(
        onDismiss = { showAddDialog = false },
        onSave = { title, content ->
          showAddDialog = false
          viewModel.memoryRepository.save(
            ai.axiomaster.bonio.remote.memory.MemoryService.SaveParams(
              title = title,
              content = content,
              source = "manual",
            ),
          )
        },
      )
    }

    pendingDelete?.let { memo ->
      AlertDialog(
        onDismissRequest = { pendingDelete = null },
        title = { Text("删除这条记忆？", style = mobileHeadline, color = mobileText) },
        text = { Text(memo.title, style = mobileCallout, color = mobileTextSecondary, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        confirmButton = {
          Button(
            onClick = {
              viewModel.memoryRepository.delete(memo.id)
              pendingDelete = null
            },
            colors = ButtonDefaults.buttonColors(containerColor = mobileDanger, contentColor = Color.White),
          ) { Text("删除") }
        },
        dismissButton = {
          TextButton(onClick = { pendingDelete = null }) { Text("取消", color = mobileAccent) }
        },
        containerColor = Color.White,
      )
    }
  }
}

@Composable
private fun MemoCard(memo: BonioMemo, createdAtText: String, onDelete: () -> Unit) {
  Card(
    modifier = Modifier.fillMaxWidth().border(1.dp, mobileBorder, RoundedCornerShape(16.dp)),
    shape = RoundedCornerShape(16.dp),
    colors = CardDefaults.cardColors(containerColor = Color.White),
  ) {
    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
      ) {
        Text(
          memo.title.ifBlank { "未命名" },
          style = mobileHeadline,
          fontWeight = FontWeight.SemiBold,
          color = mobileText,
          maxLines = 1,
          overflow = TextOverflow.Ellipsis,
          modifier = Modifier.weight(1f),
        )
        IconButton(onClick = onDelete) {
          Icon(Icons.Default.Delete, contentDescription = "Delete", tint = mobileTextSecondary)
        }
      }
      Text(
        memo.content,
        style = mobileCallout,
        color = mobileTextSecondary,
        maxLines = 3,
        overflow = TextOverflow.Ellipsis,
      )
      Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
      ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
          memo.tags.take(3).forEach { tag ->
            Text(
              tag,
              style = mobileCaption1.copy(fontSize = 10.sp),
              color = mobileAccent,
              modifier = Modifier
                .background(mobileAccentSoft, RoundedCornerShape(6.dp))
                .padding(horizontal = 6.dp, vertical = 2.dp),
            )
          }
          memo.sourceApp?.takeIf { it.isNotEmpty() }?.let { app ->
            Text(
              app,
              style = mobileCaption1.copy(fontSize = 10.sp),
              color = mobileTextSecondary,
              modifier = Modifier
                .background(mobileBorder, RoundedCornerShape(6.dp))
                .padding(horizontal = 6.dp, vertical = 2.dp),
            )
          }
        }
        if (createdAtText.isNotEmpty()) {
          Text(createdAtText, style = mobileCaption1.copy(fontSize = 10.sp), color = mobileTextSecondary)
        }
      }
    }
  }
}

@Composable
private fun EmptyMemoryHint(text: String) {
  Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
    Text(text, style = mobileCallout, color = mobileTextSecondary)
  }
}

@Composable
private fun AddMemoDialog(onDismiss: () -> Unit, onSave: (String, String) -> Unit) {
  var title by remember { mutableStateOf("") }
  var content by remember { mutableStateOf("") }

  AlertDialog(
    onDismissRequest = onDismiss,
    title = { Text("记一笔", style = mobileHeadline, color = mobileText) },
    text = {
      Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        OutlinedTextField(
          value = title,
          onValueChange = { title = it },
          label = { Text("标题", style = mobileCaption1) },
          singleLine = true,
          modifier = Modifier.fillMaxWidth(),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = mobileAccent,
            unfocusedBorderColor = mobileBorder,
            cursorColor = mobileAccent,
          ),
        )
        OutlinedTextField(
          value = content,
          onValueChange = { content = it },
          label = { Text("内容", style = mobileCaption1) },
          minLines = 3,
          modifier = Modifier.fillMaxWidth(),
          colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = mobileAccent,
            unfocusedBorderColor = mobileBorder,
            cursorColor = mobileAccent,
          ),
        )
      }
    },
    confirmButton = {
      Button(
        onClick = { onSave(title.trim(), content.trim()) },
        enabled = title.isNotBlank() && content.isNotBlank(),
        colors = ButtonDefaults.buttonColors(containerColor = mobileAccent, contentColor = Color.White),
      ) { Text("保存") }
    },
    dismissButton = {
      TextButton(onClick = onDismiss) { Text("取消", color = mobileAccent) }
    },
    containerColor = Color.White,
  )
}
