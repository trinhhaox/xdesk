package vn.xox.xdesk.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import vn.xox.xdesk.app.ui.theme.extras

/** Nút phân đoạn kiểu iOS (nền rãnh, đoạn chọn sáng hơn), bo tròn hết, mỗi đoạn cao ≥ 48 và có vai trò radio cho TalkBack. */
@Composable
internal fun <T> SegmentedPicker(options: List<Pair<T, String>>, selected: T, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    Row(modifier.fillMaxWidth().clip(CircleShape).background(MaterialTheme.extras.segmentTrack).padding(3.dp).selectableGroup()) {
        options.forEach { (value, label) -> Segment(label, value == selected) { onSelect(value) } }
    }
}

@Composable
private fun RowScope.Segment(label: String, selected: Boolean, onClick: () -> Unit) {
    val fill = if (selected) MaterialTheme.extras.segmentSelected else Color.Transparent
    Box(
        Modifier.weight(1f).heightIn(min = 42.dp).clip(CircleShape).background(fill).selectable(selected, onClick = onClick, role = Role.RadioButton),
        contentAlignment = Alignment.Center,
    ) { Text(label, fontSize = 15.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal, color = MaterialTheme.colorScheme.onSurface) }
}
