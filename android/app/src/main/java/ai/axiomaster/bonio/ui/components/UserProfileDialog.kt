package ai.axiomaster.bonio.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import ai.axiomaster.bonio.remote.memory.UserProfile
import ai.axiomaster.bonio.ui.theme.AppColors
import ai.axiomaster.bonio.ui.theme.LocalAppColors

@Composable
fun UserProfileDialog(
    profile: UserProfile,
    onDismiss: () -> Unit,
    onSave: (UserProfile) -> Unit,
    onExtractFromMemos: (() -> Unit)? = null,
    isExtracting: Boolean = false,
) {
    val colors = LocalAppColors.current

    var name by remember(profile) { mutableStateOf(profile.name) }
    var gender by remember(profile) { mutableStateOf(profile.gender) }
    var ageOrBirthday by remember(profile) { mutableStateOf(profile.ageOrBirthday) }
    var phone by remember(profile) { mutableStateOf(profile.phone) }

    var occupation by remember(profile) { mutableStateOf(profile.occupation) }
    var familyAndFriends by remember(profile) { mutableStateOf(profile.familyAndFriends) }
    var addresses by remember(profile) { mutableStateOf(profile.addresses) }
    var customFacts by remember(profile) { mutableStateOf(profile.customFacts) }

    val scrollState = rememberScrollState()

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .fillMaxHeight(0.85f)
                .clip(RoundedCornerShape(20.dp)),
            colors = CardDefaults.cardColors(containerColor = colors.cardBackground),
            elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(horizontal = 20.dp, vertical = 18.dp)
            ) {
                // ── 顶部标题栏 ──
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            text = "用户基础档案",
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold,
                            color = colors.textPrimary
                        )
                        Text(
                            text = "L0 基础固定信息 & L1 长期稳定信息",
                            fontSize = 11.sp,
                            color = colors.textTertiary
                        )
                    }
                    IconButton(onClick = onDismiss) {
                        Icon(
                            Icons.Default.Close,
                            contentDescription = "关闭",
                            tint = colors.textSecondary
                        )
                    }
                }

                // ── 提示说明横条 ──
                Surface(
                    color = colors.accent.copy(alpha = 0.08f),
                    shape = RoundedCornerShape(8.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 10.dp)
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            imageVector = Icons.Default.Refresh,
                            contentDescription = null,
                            tint = colors.accent,
                            modifier = Modifier.size(16.dp)
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "⚡ 手机充电时自动从记忆中萃取提炼，问答时自动注入大模型",
                            fontSize = 11.sp,
                            color = colors.accent,
                            lineHeight = 15.sp
                        )
                    }
                }

                // ── 文本行列表内容 ──
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .verticalScroll(scrollState)
                        .padding(vertical = 4.dp)
                ) {
                    // ── L0 基础固定信息 ──
                    Text(
                        text = "L0 基础固定信息",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.accent,
                        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                    )

                    ProfileTextLine(
                        label = "姓名",
                        value = name,
                        onValueChange = { name = it },
                        placeholder = "点击填写姓名",
                        colors = colors
                    )

                    ProfileTextLine(
                        label = "性别",
                        value = gender,
                        onValueChange = { gender = it },
                        placeholder = "点击填写性别 (如: 男 / 女)",
                        colors = colors
                    )

                    ProfileTextLine(
                        label = "年龄/生日",
                        value = ageOrBirthday,
                        onValueChange = { ageOrBirthday = it },
                        placeholder = "点击填写年龄或生日 (如: 28岁 或 08-15)",
                        colors = colors
                    )

                    ProfileTextLine(
                        label = "手机号",
                        value = phone,
                        onValueChange = { phone = it },
                        placeholder = "点击填写手机号",
                        colors = colors
                    )

                    Spacer(modifier = Modifier.height(14.dp))

                    // ── L1 长期稳定信息 ──
                    Text(
                        text = "L1 长期稳定信息",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = colors.accent,
                        modifier = Modifier.padding(top = 8.dp, bottom = 4.dp)
                    )

                    ProfileTextLine(
                        label = "职业身份",
                        value = occupation,
                        onValueChange = { occupation = it },
                        placeholder = "点击填写职业或身份 (如: 软件架构师)",
                        colors = colors
                    )

                    ProfileTextLine(
                        label = "亲友关系",
                        value = familyAndFriends,
                        onValueChange = { familyAndFriends = it },
                        placeholder = "例: 母亲: 李华；配偶: 王丽；好友: 赵刚",
                        isMultiLine = true,
                        colors = colors
                    )

                    ProfileTextLine(
                        label = "常住地点",
                        value = addresses,
                        onValueChange = { addresses = it },
                        placeholder = "例: 家: 杭州市西湖区文三路；公司: 阿里西溪园区",
                        isMultiLine = true,
                        colors = colors
                    )

                    ProfileTextLine(
                        label = "长期事实",
                        value = customFacts,
                        onValueChange = { customFacts = it },
                        placeholder = "例: 海鲜过敏；习惯早起晨跑；常用招商银行卡",
                        isMultiLine = true,
                        colors = colors
                    )
                }

                Spacer(modifier = Modifier.height(12.dp))

                // ── 底部操作按钮 ──
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (onExtractFromMemos != null) {
                        OutlinedButton(
                            onClick = onExtractFromMemos,
                            enabled = !isExtracting,
                            shape = RoundedCornerShape(10.dp),
                            modifier = Modifier.weight(1f)
                        ) {
                            if (isExtracting) {
                                CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                                Spacer(modifier = Modifier.width(6.dp))
                                Text("萃取中...", fontSize = 12.sp)
                            } else {
                                Icon(Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(14.dp))
                                Spacer(modifier = Modifier.width(4.dp))
                                Text("从记忆提炼", fontSize = 12.sp)
                            }
                        }
                    }

                    Button(
                        onClick = {
                            val newProfile = profile.copy(
                                name = name.trim(),
                                gender = gender.trim(),
                                ageOrBirthday = ageOrBirthday.trim(),
                                phone = phone.trim(),
                                occupation = occupation.trim(),
                                familyAndFriends = familyAndFriends.trim(),
                                addresses = addresses.trim(),
                                customFacts = customFacts.trim(),
                            )
                            onSave(newProfile)
                            onDismiss()
                        },
                        shape = RoundedCornerShape(10.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                        modifier = Modifier.weight(1f)
                    ) {
                        Text("保存", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    }
                }
            }
        }
    }
}

/**
 * 单条极简文本行组件：左侧为固定宽度标签，右侧为内联可编辑纯文本行
 */
@Composable
private fun ProfileTextLine(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String = "点击填写",
    isMultiLine: Boolean = false,
    colors: AppColors
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 9.dp),
            verticalAlignment = if (isMultiLine) Alignment.Top else Alignment.CenterVertically
        ) {
            Text(
                text = label,
                fontSize = 13.sp,
                fontWeight = FontWeight.Normal,
                color = colors.textSecondary,
                modifier = Modifier.width(76.dp)
            )
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                textStyle = TextStyle(
                    fontSize = 14.sp,
                    color = colors.textPrimary,
                    lineHeight = 20.sp
                ),
                singleLine = !isMultiLine,
                modifier = Modifier.weight(1f),
                decorationBox = { innerTextField ->
                    if (value.isBlank()) {
                        Text(
                            text = placeholder,
                            fontSize = 13.sp,
                            color = colors.textTertiary
                        )
                    }
                    innerTextField()
                }
            )
        }
        HorizontalDivider(
            color = colors.divider.copy(alpha = 0.6f),
            thickness = 0.5.dp
        )
    }
}
