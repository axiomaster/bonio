package ai.axiomaster.BoJi.ui.screens

import ai.axiomaster.BoJi.ai.AgentManager
import ai.axiomaster.BoJi.ai.AgentState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.airbnb.lottie.compose.LottieAnimation
import com.airbnb.lottie.compose.LottieCompositionSpec
import com.airbnb.lottie.compose.LottieConstants
import com.airbnb.lottie.compose.animateLottieCompositionAsState
import com.airbnb.lottie.compose.rememberLottieComposition

@Composable
fun VoiceTab(modifier: Modifier = Modifier) {
    val agentState by AgentManager.stateManager.currentState.collectAsState()
    val textBubble by AgentManager.stateManager.currentTextBubble.collectAsState()

    // Load Lottie Composition for Idle state (Phase 2 placeholder for all states)
    val composition by rememberLottieComposition(LottieCompositionSpec.Asset("Cat playing animation.lottie"))
    val progress by animateLottieCompositionAsState(
        composition,
        iterations = LottieConstants.IterateForever,
        isPlaying = agentState == AgentState.Idle // Simple logic for MVP Phase 2.5
    )

    Box(
        modifier = modifier
            .fillMaxSize()
            .clickable {
                // Cycle states on click similar to the floating window
                when (agentState) {
                    AgentState.Idle -> AgentManager.stateManager.transitionTo(AgentState.Listening)
                    AgentState.Listening -> AgentManager.stateManager.transitionTo(AgentState.Thinking)
                    AgentState.Thinking -> AgentManager.stateManager.transitionTo(AgentState.Idle)
                    else -> AgentManager.stateManager.transitionTo(AgentState.Idle)
                }
            },
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            if (!textBubble.isNullOrEmpty()) {
                Card(
                    shape = RoundedCornerShape(16.dp),
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White)
                ) {
                    Text(
                        text = textBubble!!,
                        modifier = Modifier.padding(16.dp),
                        color = Color.Black,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                Spacer(modifier = Modifier.height(16.dp))
            }

            LottieAnimation(
                composition = composition,
                progress = { progress },
                modifier = Modifier.fillMaxSize(0.6f)
            )
        }
    }
}
