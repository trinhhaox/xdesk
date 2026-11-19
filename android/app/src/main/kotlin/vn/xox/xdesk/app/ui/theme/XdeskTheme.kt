package vn.xox.xdesk.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Bảng màu Xdesk theo docs/brand-guide.md (chính #2F6BFF, nền sáng #F6F7FA, nền tối #101218, nhấn #18C29C, cảnh báo #F5A524).
 * Chữ xanh chính phải đạt tương phản 4.5:1 trên nền, mà #2F6BFF chỉ đạt 4.2:1 trên #F6F7FA và 4.2:1 trên #101218, nên:
 * sáng dùng primary đậm hơn một chút (#2A60EC), tối dùng primary sáng hơn (#6B96FF) và để #2F6BFF làm primaryContainer.
 */
private val Brand = Color(0xFF2F6BFF)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF2A60EC), onPrimary = Color.White,
    primaryContainer = Color(0xFFDCE6FF), onPrimaryContainer = Color(0xFF0B2A78),
    secondary = Color(0xFF4B5470), onSecondary = Color.White,
    secondaryContainer = Color(0xFFE3E6F0), onSecondaryContainer = Color(0xFF1B2030),
    tertiary = Color(0xFF0B7A62), onTertiary = Color.White,
    tertiaryContainer = Color(0xFFC4F3E5), onTertiaryContainer = Color(0xFF00382B),
    background = Color(0xFFF6F7FA), onBackground = Color(0xFF14171F),
    surface = Color(0xFFF6F7FA), onSurface = Color(0xFF14171F),
    surfaceVariant = Color(0xFFE6E9F1), onSurfaceVariant = Color(0xFF454B5C),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color.White, surfaceContainer = Color.White,
    surfaceContainerHigh = Color(0xFFEDEFF6), surfaceContainerHighest = Color(0xFFE6E9F1),
    outline = Color(0xFF6B7285), outlineVariant = Color(0xFFD3D7E3),
    error = Color(0xFFB3261E), onError = Color.White, errorContainer = Color(0xFFFCE1DE), onErrorContainer = Color(0xFF5C0A05),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF6B96FF), onPrimary = Color(0xFF08142E),
    primaryContainer = Brand, onPrimaryContainer = Color.White,
    secondary = Color(0xFFB4BCD6), onSecondary = Color(0xFF1B2030),
    secondaryContainer = Color(0xFF2A3042), onSecondaryContainer = Color(0xFFDFE3F0),
    tertiary = Color(0xFF18C29C), onTertiary = Color(0xFF062B22),
    tertiaryContainer = Color(0xFF0B4B3C), onTertiaryContainer = Color(0xFFBFF2E4),
    background = Color(0xFF101218), onBackground = Color(0xFFE6E8F0),
    surface = Color(0xFF101218), onSurface = Color(0xFFE6E8F0),
    surfaceVariant = Color(0xFF252A38), onSurfaceVariant = Color(0xFFC3C8D6),
    surfaceContainerLowest = Color(0xFF0C0E13), surfaceContainerLow = Color(0xFF181B23), surfaceContainer = Color(0xFF1B1E27),
    surfaceContainerHigh = Color(0xFF232733), surfaceContainerHighest = Color(0xFF2A2F3D),
    outline = Color(0xFF8C93A6), outlineVariant = Color(0xFF3A4052),
    error = Color(0xFFFFB4AB), onError = Color(0xFF540C07), errorContainer = Color(0xFF7A1E17), onErrorContainer = Color(0xFFFFDAD6),
)

/** Cảnh báo (#F5A524) không có trong Material 3 nên đi kèm riêng: dùng cho "Khoá đã đổi" và lỗi cần người dùng cân nhắc. */
data class XdeskExtraColors(val warningContainer: Color, val onWarningContainer: Color, val warning: Color)

private val LightExtras = XdeskExtraColors(Color(0xFFFFEBC8), Color(0xFF5B3A00), Color(0xFFF5A524))
private val DarkExtras = XdeskExtraColors(Color(0xFF5B3A00), Color(0xFFFFE2B0), Color(0xFFF5A524))
private val LocalExtras = staticCompositionLocalOf { LightExtras }

val MaterialTheme.extras: XdeskExtraColors @Composable @ReadOnlyComposable get() = LocalExtras.current

/**
 * Màu của các lớp nổi trên video (nút nổi, thanh phím phụ, lớp phủ kết nối): luôn tối và chữ sáng ở cả hai giao diện vì nền là video của Mac,
 * lấy từ bảng màu tối để cùng một nguồn.
 */
object XdeskOverlay {
    val panel = DarkScheme.surfaceContainer
    val key = DarkScheme.secondaryContainer
    val content = Color.White
    val contentMuted = DarkScheme.onSurfaceVariant
    val contentDisabled = DarkScheme.onSurface.copy(alpha = 0.5f)
    val outline = Color(0x8CFFFFFF)
    val divider = DarkScheme.outlineVariant
    val accent = Brand
    /** Vòng xoay tiến trình trên nền đen: cần sáng hơn #2F6BFF để đủ tương phản. */
    val accentLight = DarkScheme.primary
    val scrim = Color(0xE6000000)
}

/** Giao diện Xdesk, theo cài đặt Sáng/Tối của hệ thống. */
@Composable
fun XdeskTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val scheme: ColorScheme = if (dark) DarkScheme else LightScheme
    CompositionLocalProvider(LocalExtras provides if (dark) DarkExtras else LightExtras) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
