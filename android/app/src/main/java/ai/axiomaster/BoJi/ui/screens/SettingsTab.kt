package ai.axiomaster.BoJi.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsTab(modifier: Modifier = Modifier) {
    var manualHost by remember { mutableStateOf("192.168.43.4") }
    var manualPort by remember { mutableStateOf("18789") }
    var manualToken by remember { mutableStateOf("lism") }
    var manualTls by remember { mutableStateOf(false) }

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Settings & Gateway", fontSize = 24.sp, fontWeight = FontWeight.Bold)
        Spacer(modifier = Modifier.height(24.dp))

        TextField(
            value = manualHost,
            onValueChange = { manualHost = it },
            label = { Text("Gateway Host") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(8.dp))
        
        TextField(
            value = manualPort,
            onValueChange = { manualPort = it },
            label = { Text("Port") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(8.dp))

        TextField(
            value = manualToken,
            onValueChange = { manualToken = it },
            label = { Text("Token") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(modifier = Modifier.height(16.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text("Enable TLS", fontSize = 16.sp)
            Switch(
                checked = manualTls,
                onCheckedChange = { manualTls = it }
            )
        }

        Spacer(modifier = Modifier.height(24.dp))
        
        Button(
            onClick = { /* TODO: Implement Connection Logic */ },
            modifier = Modifier.fillMaxWidth().height(48.dp)
        ) {
            Text("Connect")
        }
    }
}
