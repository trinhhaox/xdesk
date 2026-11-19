package vn.xox.xdesk.app.ui.theme

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Bo góc thẻ nhóm kiểu inset-grouped của iOS (docs/design-tokens.md). */
val XdeskCardShape = RoundedCornerShape(26.dp)

/** Thẻ Xdesk: nền `surface` nhóm (#1C1C1E tối / trắng sáng), bo 26, không viền. Có `onClick` thì cả thẻ bấm được. */
@Composable
fun XdeskCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        if (onClick == null) modifier else modifier.clickable(onClick = onClick),
        shape = XdeskCardShape, color = MaterialTheme.colorScheme.surfaceContainer,
    ) { Column(content = content) }
}
