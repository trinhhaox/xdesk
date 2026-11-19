package vn.xox.xdesk.app.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** Biểu tượng quét mã QR (bộ icons-core không có sẵn): ba ô định vị và vài điểm ảnh. */
internal val QrScanIcon: ImageVector = ImageVector.Builder("QrScan", 24.dp, 24.dp, 24f, 24f).apply {
    path(fill = SolidColor(Color.Black), pathFillType = PathFillType.EvenOdd) {
        finder(3f, 3f)
        finder(14f, 3f)
        finder(3f, 14f)
        square(14f, 14f, 3f)
        square(18f, 18f, 3f)
        square(18f, 14f, 3f)
        square(14f, 18f, 3f)
    }
}.build()

private fun PathBuilder.square(x: Float, y: Float, size: Float) {
    moveTo(x, y); horizontalLineToRelative(size); verticalLineToRelative(size); horizontalLineToRelative(-size); close()
}

/** Ô định vị 7x7 có lỗ giữa 3x3. */
private fun PathBuilder.finder(x: Float, y: Float) {
    square(x, y, 7f)
    square(x + 2f, y + 2f, 3f)
}
