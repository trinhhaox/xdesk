package vn.xox.xdesk.app.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Thẻ Xdesk: nền surfaceContainer có viền mảnh (thẻ mặc định của Material 3 là surfaceContainerHighest, trông như nền thứ hai). */
@Composable
fun XdeskCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)
    val border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    if (onClick == null) Card(modifier, colors = colors, border = border, content = content)
    else Card(onClick, modifier, colors = colors, border = border, content = content)
}
