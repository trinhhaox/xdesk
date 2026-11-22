package vn.xox.xdesk.app.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** Biểu tượng tương ứng SF Symbol của iOS (bảng ở docs/design-tokens.md); bộ icons-core của Material không có sẵn. Tô màu bằng `tint` của Icon. */
internal object XdeskIcons {
    internal fun build(name: String, block: ImageVector.Builder.() -> Unit) =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply(block).build()

    internal fun ImageVector.Builder.stroke(width: Float = 1.8f, block: PathBuilder.() -> Unit) = path(
        fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = width, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round, pathBuilder = block,
    )

    internal fun ImageVector.Builder.fill(block: PathBuilder.() -> Unit) = path(fill = SolidColor(Color.Black), pathFillType = PathFillType.EvenOdd, pathBuilder = block)

    internal fun PathBuilder.rect(x: Float, y: Float, w: Float, h: Float) {
        moveTo(x, y); horizontalLineToRelative(w); verticalLineToRelative(h); horizontalLineToRelative(-w); close()
    }

    internal fun PathBuilder.circle(cx: Float, cy: Float, r: Float) {
        moveTo(cx - r, cy); arcToRelative(r, r, 0f, true, true, 2 * r, 0f); arcToRelative(r, r, 0f, true, true, -2 * r, 0f); close()
    }

    internal fun PathBuilder.roundRect(x: Float, y: Float, w: Float, h: Float, r: Float) {
        moveTo(x + r, y); horizontalLineTo(x + w - r); arcTo(r, r, 0f, false, true, x + w, y + r)
        verticalLineTo(y + h - r); arcTo(r, r, 0f, false, true, x + w - r, y + h)
        horizontalLineTo(x + r); arcTo(r, r, 0f, false, true, x, y + h - r)
        verticalLineTo(y + r); arcTo(r, r, 0f, false, true, x + r, y); close()
    }

    val Monitor = build("Monitor") {
        fill { roundRect(2.5f, 3.5f, 19f, 12.5f, 2f); rect(10.5f, 16f, 3f, 2.5f); roundRect(7.5f, 18.5f, 9f, 2f, 1f) }
    }
    val Chevron = build("Chevron") { stroke(2.4f) { moveTo(9f, 5f); lineTo(16f, 12f); lineTo(9f, 19f) } }
    val EllipsisCircle = build("EllipsisCircle") {
        stroke(1.7f) { circle(12f, 12f, 9.5f) }
        fill { circle(7.8f, 12f, 1.3f); circle(12f, 12f, 1.3f); circle(16.2f, 12f, 1.3f) }
    }
    val Globe = build("Globe") {
        stroke(1.6f) {
            circle(12f, 12f, 9.5f); moveTo(2.5f, 12f); horizontalLineTo(21.5f)
            moveTo(12f, 2.5f); arcToRelative(4.6f, 9.5f, 0f, false, false, 0f, 19f); arcToRelative(4.6f, 9.5f, 0f, false, false, 0f, -19f)
            moveTo(4.5f, 7f); curveTo(8.5f, 9f, 15.5f, 9f, 19.5f, 7f); moveTo(4.5f, 17f); curveTo(8.5f, 15f, 15.5f, 15f, 19.5f, 17f)
        }
    }
    val Cable = build("Cable") {
        fill { roundRect(9.2f, 2.5f, 5.6f, 11.5f, 1.4f) }
        stroke(1.8f) { moveTo(12f, 14f); verticalLineTo(21.5f) }
    }
    val Laptop = build("Laptop") {
        stroke(1.6f) { roundRect(4.5f, 4.5f, 15f, 10.5f, 1.8f); moveTo(1.8f, 18.5f); horizontalLineTo(22.2f) }
    }
    val Phone = build("Phone") {
        stroke(1.6f) { roundRect(6.5f, 2.2f, 11f, 19.6f, 2.6f); moveTo(10.5f, 18.6f); horizontalLineTo(13.5f) }
    }
    val HandTap = build("HandTap") {
        stroke(1.6f) {
            moveTo(8.5f, 12.5f); verticalLineTo(5f); arcToRelative(1.5f, 1.5f, 0f, false, true, 3f, 0f); verticalLineTo(10.5f); horizontalLineToRelative(4.5f)
            arcToRelative(2.2f, 2.2f, 0f, false, true, 2.2f, 2.2f); verticalLineToRelative(3f); arcToRelative(5.5f, 5.5f, 0f, false, true, -5.5f, 5.5f)
            horizontalLineToRelative(-1.2f); arcToRelative(5.5f, 5.5f, 0f, false, true, -4.4f, -2.2f); lineToRelative(-3f, -4.3f)
            arcToRelative(1.3f, 1.3f, 0f, false, true, 2f, -1.6f); lineToRelative(1.9f, 2f)
        }
    }
    val Moon = build("Moon") {
        stroke(1.7f) { moveTo(20f, 14.5f); arcTo(8.5f, 8.5f, 0f, true, true, 9.5f, 4f); arcToRelative(7f, 7f, 0f, false, false, 10.5f, 10.5f); close() }
    }
    val Sun = build("Sun") {
        stroke(1.7f) {
            circle(12f, 12f, 4f)
            for (a in 0 until 8) {
                val t = Math.toRadians(a * 45.0)
                moveTo(12f + 7f * Math.cos(t).toFloat(), 12f + 7f * Math.sin(t).toFloat())
                lineTo(12f + 9.5f * Math.cos(t).toFloat(), 12f + 9.5f * Math.sin(t).toFloat())
            }
        }
    }
    val HalfCircle = build("HalfCircle") {
        stroke(1.7f) { circle(12f, 12f, 9f) }
        fill { moveTo(12f, 3f); arcToRelative(9f, 9f, 0f, false, false, 0f, 18f); close() }
    }

    val Ellipsis = build("Ellipsis") { fill { circle(5f, 12f, 2.1f); circle(12f, 12f, 2.1f); circle(19f, 12f, 2.1f) } }
    val Keyboard = build("Keyboard") {
        stroke(1.6f) {
            roundRect(2.5f, 5.5f, 19f, 13f, 2.4f)
            moveTo(6.5f, 9.5f); horizontalLineToRelative(0.01f); moveTo(10.5f, 9.5f); horizontalLineToRelative(0.01f); moveTo(14.5f, 9.5f); horizontalLineToRelative(0.01f)
            moveTo(17.5f, 9.5f); horizontalLineToRelative(0.01f); moveTo(6.5f, 13.5f); horizontalLineToRelative(0.01f); moveTo(17.5f, 13.5f); horizontalLineToRelative(0.01f)
            moveTo(9f, 15.2f); horizontalLineToRelative(6f)
        }
    }
    val Cursor = build("Cursor") {
        stroke(1.7f) { moveTo(5f, 3f); lineTo(5f, 19f); lineTo(9.2f, 15f); lineTo(12f, 21f); lineTo(14.4f, 19.9f); lineTo(11.7f, 14f); lineTo(17.5f, 14f); close() }
    }
    val Sliders = build("Sliders") {
        stroke(1.7f) { moveTo(3f, 7f); horizontalLineTo(21f); moveTo(3f, 17f); horizontalLineTo(21f) }
        fill { circle(9f, 7f, 2.6f); circle(15f, 17f, 2.6f) }
    }
    val FitScreen = build("FitScreen") {
        stroke(1.8f) {
            moveTo(14f, 10f); lineTo(20f, 4f); moveTo(14f, 5.5f); verticalLineTo(10f); horizontalLineTo(18.5f)
            moveTo(10f, 14f); lineTo(4f, 20f); moveTo(10f, 18.5f); verticalLineTo(14f); horizontalLineTo(5.5f)
        }
    }
    val Stop = build("Stop") { stroke(1.8f) { circle(12f, 12f, 9.5f); moveTo(8.5f, 8.5f); lineTo(15.5f, 15.5f); moveTo(15.5f, 8.5f); lineTo(8.5f, 15.5f) } }
    val Search = build("Search") {
        stroke(1.8f) { circle(10.5f, 10.5f, 6.5f); moveTo(15.2f, 15.2f); lineTo(21f, 21f) }
    }
    val Layers = build("Layers") {
        stroke(1.8f) {
            moveTo(12f, 3f); lineTo(21f, 7.5f); lineTo(12f, 12f); lineTo(3f, 7.5f); close()
            moveTo(3f, 12f); lineTo(12f, 16.5f); lineTo(21f, 12f)
            moveTo(3f, 16.5f); lineTo(12f, 21f); lineTo(21f, 16.5f)
        }
    }
    val AppWindow = build("AppWindow") {
        stroke(1.8f) {
            roundRect(3f, 4f, 18f, 16f, 2f)
            moveTo(3f, 9f); horizontalLineTo(21f)
            circle(6f, 6.5f, 0.8f); circle(9f, 6.5f, 0.8f); circle(12f, 6.5f, 0.8f)
        }
    }
    val Undo = build("Undo") {
        stroke(1.8f) {
            moveTo(8f, 7f); lineTo(3f, 12f); lineTo(8f, 17f)
            moveTo(3f, 12f); horizontalLineTo(14f); arcTo(6f, 6f, 0f, false, true, 20f, 18f)
        }
    }
    val Lock = build("Lock") {
        stroke(1.8f) {
            roundRect(5f, 10f, 14f, 11f, 2f)
            moveTo(8f, 10f); verticalLineTo(7f); arcTo(4f, 4f, 0f, false, true, 16f, 7f); verticalLineTo(10f)
        }
    }
    val Camera = build("Camera") {
        stroke(1.8f) {
            roundRect(3f, 6f, 18f, 14f, 2f)
            circle(12f, 13f, 3.5f)
            moveTo(8f, 6f); lineTo(9.5f, 3.5f); horizontalLineTo(14.5f); lineTo(16f, 6f)
        }
    }
    val Unlock = build("Unlock") {
        stroke(1.8f) {
            roundRect(5f, 10f, 14f, 11f, 2f)
            moveTo(8f, 10f); verticalLineTo(7f); arcTo(4f, 4f, 0f, false, true, 16f, 7f)
        }
    }
    val FileTransfer = build("FileTransfer") {
        stroke(1.8f) {
            roundRect(4f, 3f, 16f, 18f, 2f)
            moveTo(12f, 15f); verticalLineTo(8f)
            moveTo(9f, 11f); lineTo(12f, 8f); lineTo(15f, 11f)
        }
    }
    val SecondDisplay = build("SecondDisplay") {
        stroke(1.7f) {
            roundRect(2.5f, 5f, 11f, 12f, 1.8f)
            roundRect(15.5f, 7f, 6f, 10f, 1.4f)
            moveTo(5.5f, 19.5f); horizontalLineTo(10.5f)
        }
    }
    val Presentation = build("Presentation") {
        stroke(1.7f) {
            roundRect(3f, 4.5f, 18f, 12.5f, 2f)
            moveTo(12f, 17f); verticalLineTo(20.5f)
            moveTo(8f, 20.5f); horizontalLineTo(16f)
        }
        fill {
            moveTo(10.2f, 8.2f); lineTo(15.2f, 10.75f); lineTo(10.2f, 13.3f); close()
        }
    }
    val Tailscale = build("Tailscale") {
        stroke(1.6f) {
            circle(10f, 10f, 7.5f)
            moveTo(2.5f, 10f); horizontalLineTo(17.5f)
            moveTo(10f, 2.5f); arcToRelative(3.6f, 7.5f, 0f, false, false, 0f, 15f)
            arcToRelative(3.6f, 7.5f, 0f, false, false, 0f, -15f)
        }
        fill {
            moveTo(17.5f, 12.2f); lineTo(22f, 13.8f); verticalLineTo(17f)
            curveTo(22f, 19.6f, 19.9f, 21.4f, 17.5f, 22.3f)
            curveTo(15.1f, 21.4f, 13f, 19.6f, 13f, 17f)
            verticalLineTo(13.8f); close()
        }
    }
    val Mouse = build("Mouse") {
        stroke(1.7f) {
            roundRect(6.5f, 2.5f, 11f, 19f, 5.5f)
            moveTo(12f, 6.2f); verticalLineTo(10f)
        }
    }
    val ExitSlide = build("ExitSlide") {
        stroke(1.7f) {
            roundRect(3f, 4.5f, 18f, 15f, 2.2f)
            moveTo(9.2f, 9.2f); lineTo(14.8f, 14.8f)
            moveTo(14.8f, 9.2f); lineTo(9.2f, 14.8f)
        }
    }
    val ChevronLeftCircle = build("ChevronLeftCircle") {
        stroke(1.7f) {
            circle(12f, 12f, 9.2f)
            moveTo(13.6f, 8.2f); lineTo(9.8f, 12f); lineTo(13.6f, 15.8f)
        }
    }
    val ChevronRightCircle = build("ChevronRightCircle") {
        stroke(1.7f) {
            circle(12f, 12f, 9.2f)
            moveTo(10.4f, 8.2f); lineTo(14.2f, 12f); lineTo(10.4f, 15.8f)
        }
    }
    val SpaceBar = build("SpaceBar") {
        stroke(1.8f) {
            moveTo(3.5f, 10.5f); verticalLineTo(15.5f); horizontalLineTo(20.5f); verticalLineTo(10.5f)
        }
    }
}
