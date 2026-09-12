package ai.axiomaster.bonio.ui.screens

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import ai.axiomaster.bonio.MainViewModel
import ai.axiomaster.bonio.avatar.CustomSkinManager
import ai.axiomaster.bonio.avatar.SkinItem
import ai.axiomaster.bonio.i18n.LocalAppStrings
import ai.axiomaster.bonio.remote.config.ModelConfig
import ai.axiomaster.bonio.remote.skills.SkillInfo
import ai.axiomaster.bonio.ui.screens.chat.*

@Composable
fun PersonalizationTab(
    viewModel: MainViewModel,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val strings = LocalAppStrings.current
    val isConnected by viewModel.isConnected.collectAsState()
    val currentSkin by viewModel.avatarSkin.collectAsState()
    val serverConfig by viewModel.serverConfig.collectAsState()
    val skills by viewModel.skills.collectAsState()
    val skillsLoading by viewModel.skillsLoading.collectAsState()
    val skillsError by viewModel.skillsError.collectAsState()

    var isAddingModel by rememberSaveable { mutableStateOf(false) }
    var newModelId by rememberSaveable { mutableStateOf("") }
    var newModelProvider by rememberSaveable { mutableStateOf("openai") }
    var newModelApiKey by rememberSaveable { mutableStateOf("") }
    var newModelBaseUrl by rememberSaveable { mutableStateOf("") }
    var modelDropdownExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        viewModel.refreshServerConfig()
        if (isConnected) {
            viewModel.refreshSkills()
        }
    }

    LaunchedEffect(isConnected) {
        if (isConnected) {
            viewModel.refreshServerConfig()
            viewModel.refreshSkills()
        }
    }

    // Permission states
    var contactsGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
        )
    }
    val contactsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        contactsGranted = granted
    }

    var smsGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
        )
    }
    val smsLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        smsGranted = granted
    }

    var calendarGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
        )
    }
    val calendarLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        calendarGranted = granted
    }

    val photosPerm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
    var photosGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, photosPerm) == PackageManager.PERMISSION_GRANTED
        )
    }
    val photosLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        photosGranted = granted
    }

    var notificationEnabled by rememberSaveable { mutableStateOf(true) }
    var memoEnabled by rememberSaveable { mutableStateOf(true) }
    var filesEnabled by rememberSaveable { mutableStateOf(true) }

    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .background(Color(0xFFFAFAFA))
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        contentPadding = PaddingValues(top = 16.dp, bottom = 32.dp)
    ) {
        // ── 1. Avatar 皮肤 Section ──
        item { SectionHeader(title = strings.avatarSkinSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column {
                        Text(
                            text = "当前皮肤",
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color(0xFF1D2129)
                        )
                        val activeSkinItem = CustomSkinManager.getSkinById(currentSkin)
                        Text(
                            text = activeSkinItem.subtitle,
                            fontSize = 12.sp,
                            color = Color(0xFF86909C),
                            modifier = Modifier.padding(top = 3.dp)
                        )
                    }

                    // Horizontal Scroll Gallery
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        CustomSkinManager.allSkins.forEach { skin ->
                            val isSelected = skin.id.equals(currentSkin, ignoreCase = true)
                            Surface(
                                onClick = { viewModel.setAvatarSkin(skin.id) },
                                modifier = Modifier.width(115.dp),
                                shape = RoundedCornerShape(10.dp),
                                color = if (isSelected) Color(0xFFE8F0FE) else Color(0xFFF7F8FA),
                                border = BorderStroke(
                                    1.5.dp,
                                    if (isSelected) Color(0xFF0A59F7) else Color.Transparent
                                )
                            ) {
                                Column(
                                    modifier = Modifier.padding(12.dp),
                                    verticalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Text(
                                        text = skin.name.substringBefore(" "),
                                        fontSize = 13.sp,
                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                        color = if (isSelected) Color(0xFF0A59F7) else Color(0xFF1D2129)
                                    )
                                    Text(
                                        text = skin.subtitle,
                                        fontSize = 10.sp,
                                        color = Color(0xFF86909C),
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── 2. 大模型 Section ──
        item { SectionHeader(title = strings.modelSettingsSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    val defaultModel = serverConfig?.defaultModel ?: "glm-4.7"
                    val models = serverConfig?.models ?: emptyList()
                    val presetModelIds = listOf("glm-4.7", "deepseek-v3", "deepseek-r1", "gpt-4o", "claude-3-5-sonnet", "qwen-2.5-72b")
                    val allModelIds = (presetModelIds + models.map { it.id }).distinct()

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "默认大模型",
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color(0xFF333333)
                            )
                            Text(
                                text = "当前智能体使用的模型",
                                fontSize = 12.sp,
                                color = Color(0xFF999999),
                                modifier = Modifier.padding(top = 3.dp)
                            )
                        }

                        Box {
                            Surface(
                                onClick = { modelDropdownExpanded = true },
                                shape = RoundedCornerShape(8.dp),
                                color = Color(0xFFF5F5F5)
                            ) {
                                Text(
                                    text = defaultModel,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color(0xFF333333),
                                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
                                )
                            }
                            DropdownMenu(
                                expanded = modelDropdownExpanded,
                                onDismissRequest = { modelDropdownExpanded = false }
                            ) {
                                allModelIds.forEach { mid ->
                                    DropdownMenuItem(
                                        text = {
                                            Text(
                                                mid,
                                                fontWeight = if (mid == defaultModel) FontWeight.Bold else FontWeight.Normal,
                                                color = if (mid == defaultModel) Color(0xFF0A59F7) else Color(0xFF333333)
                                            )
                                        },
                                        onClick = {
                                            modelDropdownExpanded = false
                                            viewModel.updateServerConfig(defaultModel = mid)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))
                    Text(
                        text = if (isAddingModel) "收起" else "+ 添加自定义模型",
                        fontSize = 13.sp,
                        color = Color(0xFF0A59F7),
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier
                            .clickable { isAddingModel = !isAddingModel }
                            .padding(vertical = 4.dp)
                    )

                    if (isAddingModel) {
                        Column(
                            modifier = Modifier.padding(top = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            OutlinedTextField(
                                value = newModelId,
                                onValueChange = { newModelId = it },
                                placeholder = { Text("Model ID (例如 qwen-max)", fontSize = 13.sp) },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(8.dp)
                            )
                            OutlinedTextField(
                                value = newModelProvider,
                                onValueChange = { newModelProvider = it },
                                placeholder = { Text("Provider (例如 openai / dashscope)", fontSize = 13.sp) },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(8.dp)
                            )
                            OutlinedTextField(
                                value = newModelApiKey,
                                onValueChange = { newModelApiKey = it },
                                placeholder = { Text("API Key (可选)", fontSize = 13.sp) },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(8.dp)
                            )
                            OutlinedTextField(
                                value = newModelBaseUrl,
                                onValueChange = { newModelBaseUrl = it },
                                placeholder = { Text("Base URL (可选)", fontSize = 13.sp) },
                                singleLine = true,
                                modifier = Modifier.fillMaxWidth(),
                                shape = RoundedCornerShape(8.dp)
                            )

                            Button(
                                onClick = {
                                    if (newModelId.isNotBlank()) {
                                        val existing = serverConfig?.models ?: emptyList()
                                        val newModel = ModelConfig(
                                            id = newModelId.trim(),
                                            provider = newModelProvider.trim(),
                                            apiKey = newModelApiKey.trim().ifEmpty { null },
                                            baseUrl = newModelBaseUrl.trim().ifEmpty { null }
                                        )
                                        val updated = existing.filter { it.id != newModel.id } + newModel
                                        viewModel.updateServerConfig(defaultModel = newModel.id, models = updated)
                                        isAddingModel = false
                                        newModelId = ""
                                        newModelApiKey = ""
                                        newModelBaseUrl = ""
                                    }
                                },
                                modifier = Modifier.fillMaxWidth().height(42.dp),
                                shape = RoundedCornerShape(8.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0A59F7))
                            ) {
                                Text("保存并使用此模型", color = Color.White, fontWeight = FontWeight.Medium)
                            }
                        }
                    }
                }
            }
        }

        // ── 3. WeChat 连接 Section ──
        item { SectionHeader(title = strings.wechatBindingSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("微信 iLink", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
                        Text(
                            strings.wechatScanQrCode,
                            fontSize = 12.sp,
                            color = Color(0xFF999999),
                            modifier = Modifier.padding(top = 3.dp)
                        )
                    }
                    Button(
                        onClick = { /* WeChat iLink QR flow */ },
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF07C160)),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp)
                    ) {
                        Text(if (strings == ai.axiomaster.bonio.i18n.AppStrings.ZH) "扫码绑定" else "Bind", color = Color.White, fontSize = 13.sp)
                    }
                }
            }
        }

        // ── 4. Skills 技能列表 Section ──
        item {
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "${strings.skillsSection} (${skills.size})",
                    fontSize = 13.sp,
                    color = Color(0xFF0A59F7),
                    fontWeight = FontWeight.Medium
                )
                IconButton(onClick = { viewModel.refreshSkills() }, enabled = isConnected && !skillsLoading) {
                    Icon(Icons.Default.Refresh, contentDescription = "Refresh", tint = Color(0xFF0A59F7), modifier = Modifier.size(20.dp))
                }
            }
        }

        if (skills.isEmpty()) {
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(14.dp),
                    color = Color.White,
                    border = BorderStroke(1.dp, Color(0xFFE5E6EB))
                ) {
                    Text(
                        text = if (isConnected) (if (strings == ai.axiomaster.bonio.i18n.AppStrings.ZH) "未安装第三方技能" else "No third-party skills installed") else (if (strings == ai.axiomaster.bonio.i18n.AppStrings.ZH) "连接后端后查看技能列表" else "Connect gateway to view skills"),
                        fontSize = 13.sp,
                        color = Color(0xFF999999),
                        modifier = Modifier.padding(20.dp)
                    )
                }
            }
        } else {
            items(skills, key = { it.id }) { skill ->
                SkillRow(skill = skill, onToggle = { enabled -> viewModel.toggleSkill(skill.id, enabled) })
            }
        }

        // ── 5. 系统数据授权访问范围 Section ──
        item { SectionHeader(title = strings.permissionsSection) }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(14.dp),
                color = Color.White,
                border = BorderStroke(1.dp, Color(0xFFE5E6EB))
            ) {
                Column {
                    DataPermissionRow(
                        title = "通讯录",
                        subtitle = "允许智能体读取联系人信息",
                        isOn = contactsGranted,
                        onToggle = { enable ->
                            if (enable) contactsLauncher.launch(Manifest.permission.READ_CONTACTS)
                            else contactsGranted = false
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    DataPermissionRow(
                        title = "短信",
                        subtitle = "允许智能体读取和检索短信内容",
                        isOn = smsGranted,
                        onToggle = { enable ->
                            if (enable) smsLauncher.launch(Manifest.permission.READ_SMS)
                            else smsGranted = false
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    DataPermissionRow(
                        title = "通知",
                        subtitle = "允许智能体感知各应用即时通知",
                        isOn = notificationEnabled,
                        onToggle = { notificationEnabled = it }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    DataPermissionRow(
                        title = "日历",
                        subtitle = "允许智能体读取日程与日历",
                        isOn = calendarGranted,
                        onToggle = { enable ->
                            if (enable) calendarLauncher.launch(Manifest.permission.READ_CALENDAR)
                            else calendarGranted = false
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    DataPermissionRow(
                        title = "备忘录",
                        subtitle = "允许智能体读取和记录便签备忘",
                        isOn = memoEnabled,
                        onToggle = { memoEnabled = it }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    DataPermissionRow(
                        title = "图库",
                        subtitle = "允许智能体读取相册与图片媒体",
                        isOn = photosGranted,
                        onToggle = { enable ->
                            if (enable) photosLauncher.launch(photosPerm)
                            else photosGranted = false
                        }
                    )
                    HorizontalDivider(color = Color(0xFFF2F3F5), thickness = 0.5.dp)
                    DataPermissionRow(
                        title = "文管",
                        subtitle = "允许智能体访问文档与本地文件",
                        isOn = filesEnabled,
                        onToggle = { filesEnabled = it }
                    )
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        fontSize = 13.sp,
        fontWeight = FontWeight.Medium,
        color = Color(0xFF0A59F7),
        modifier = Modifier.padding(top = 10.dp, bottom = 4.dp)
    )
}

@Composable
private fun SkillRow(
    skill: SkillInfo,
    onToggle: (Boolean) -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = Color.White,
        border = BorderStroke(1.dp, Color(0xFFE5E6EB))
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(skill.name, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
                    if (skill.builtin) {
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = Color(0xFFE8F0FE),
                            modifier = Modifier.padding(start = 8.dp)
                        ) {
                            Text(
                                text = "内置",
                                fontSize = 10.sp,
                                color = Color(0xFF0A59F7),
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                            )
                        }
                    }
                }
                if (skill.description.isNotBlank()) {
                    Text(
                        text = skill.description,
                        fontSize = 12.sp,
                        color = Color(0xFF999999),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 3.dp)
                    )
                }
            }

            Switch(
                checked = skill.enabled,
                onCheckedChange = onToggle,
                colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = Color(0xFF0A59F7))
            )
        }
    }
}

@Composable
private fun DataPermissionRow(
    title: String,
    subtitle: String,
    isOn: Boolean,
    onToggle: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color(0xFF333333))
            Text(subtitle, fontSize = 12.sp, color = Color(0xFF999999), modifier = Modifier.padding(top = 2.dp))
        }
        Switch(
            checked = isOn,
            onCheckedChange = onToggle,
            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = Color(0xFF0A59F7))
        )
    }
}
