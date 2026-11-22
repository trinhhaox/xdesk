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
import vn.xox.xdesk.app.AppearanceSetting

/** Bảng màu theo docs/design-tokens.md (cùng giá trị với BrandPalette.swift). Sửa một nơi thì sửa cả hai. */
private val PrimaryFill = Color(0xFF2F6BFF)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF2457E6), onPrimary = Color.White,
    primaryContainer = Color(0xFFDCE6FF), onPrimaryContainer = Color(0xFF0B2A78),
    secondary = Color(0xFF6C6C70), onSecondary = Color.White,
    secondaryContainer = Color(0xFFEEEEF0), onSecondaryContainer = Color(0xFF1B2030),
    tertiary = Color(0xFF0B7A63), onTertiary = Color.White,
    tertiaryContainer = Color(0xFFC4F3E5), onTertiaryContainer = Color(0xFF00382B),
    background = Color(0xFFF6F7FA), onBackground = Color.Black,
    surface = Color(0xFFF6F7FA), onSurface = Color.Black,
    surfaceVariant = Color(0xFFE6E9F1), onSurfaceVariant = Color(0xFF6C6C70),
    surfaceContainerLowest = Color.White, surfaceContainerLow = Color.White, surfaceContainer = Color.White,
    surfaceContainerHigh = Color(0xFFEDEFF6), surfaceContainerHighest = Color(0xFFE6E9F1),
    outline = Color(0xFF6C6C70), outlineVariant = Color(0xFFD8D8DC),
    error = Color(0xFFC62828), onError = Color.White, errorContainer = Color(0xFFFCE1DE), onErrorContainer = Color(0xFF5C0A05),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF5B8CFF), onPrimary = Color(0xFF08142E),
    primaryContainer = PrimaryFill, onPrimaryContainer = Color.White,
    secondary = Color(0xFF98989F), onSecondary = Color(0xFF1B2030),
    secondaryContainer = Color(0xFF2C2C2E), onSecondaryContainer = Color(0xFFDFE3F0),
    tertiary = Color(0xFF18C29C), onTertiary = Color(0xFF062B22),
    tertiaryContainer = Color(0xFF0B4B3C), onTertiaryContainer = Color(0xFFBFF2E4),
    background = Color(0xFF101218), onBackground = Color.White,
    surface = Color(0xFF101218), onSurface = Color.White,
    surfaceVariant = Color(0xFF252A38), onSurfaceVariant = Color(0xFF98989F),
    surfaceContainerLowest = Color(0xFF0C0E13), surfaceContainerLow = Color(0xFF181B23), surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerHigh = Color(0xFF232733), surfaceContainerHighest = Color(0xFF2A2F3D),
    outline = Color(0xFF98989F), outlineVariant = Color(0xFF38383A),
    error = Color(0xFFFF6B6B), onError = Color(0xFF540C07), errorContainer = Color(0xFF7A1E17), onErrorContainer = Color(0xFFFFDAD6),
)

/** Token ngoài Material 3: cảnh báo, nhãn phụ/ba, nền nút phân đoạn, viên thuốc toolbar và nền nút chính. */
data class XdeskExtraColors(
    val warning: Color, val warningContainer: Color, val onWarningContainer: Color,
    val tertiaryLabel: Color, val separator: Color, val segmentTrack: Color, val segmentSelected: Color, val toolbarPill: Color,
    val primaryFill: Color,
)

private val LightExtras = XdeskExtraColors(
    Color(0xFF8A5A00), Color(0xFFFFEBC8), Color(0xFF5B3A00), Color(0xFFB4B4B9), Color(0xFFD8D8DC),
    Color(0xFFEEEEF0), Color.White, Color(0xFFE4E7F0), PrimaryFill,
)
private val DarkExtras = XdeskExtraColors(
    Color(0xFFF5A524), Color(0xFF5B3A00), Color(0xFFFFE2B0), Color(0xFF5C5C61), Color(0xFF38383A),
    Color(0xFF2C2C2E), Color(0xFF636366), Color(0xFF2B2E38), PrimaryFill,
)
private val LocalExtras = staticCompositionLocalOf { DarkExtras }

val MaterialTheme.extras: XdeskExtraColors @Composable @ReadOnlyComposable get() = LocalExtras.current

/**
 * Màu của các lớp nổi trên video (nút nổi, thanh phím phụ, lớp phủ kết nối): luôn tối và chữ sáng ở cả hai giao diện vì nền là video của Mac,
 * lấy từ bảng màu tối để cùng một nguồn.
 */
object XdeskOverlay {
    /** overlay #101218: nút nổi, menu và thẻ trên video (iOS `overlaySurface`). */
    val panel = DarkScheme.background
    /** Thanh phím phụ (iOS `secondarySystemBackground`). */
    val bar = DarkScheme.surfaceContainer
    val key = DarkScheme.secondaryContainer
    val content = Color.White
    val contentMuted = DarkScheme.onSurfaceVariant
    val contentDisabled = DarkScheme.onSurface.copy(alpha = 0.5f)
    val outline = Color(0x8CFFFFFF)
    val divider = DarkScheme.outlineVariant
    val accent = PrimaryFill
    /** Vòng xoay tiến trình trên nền đen: cần sáng hơn #2F6BFF để đủ tương phản (cùng primaryOnOverlay của iOS). */
    val accentLight = DarkScheme.primary
    val danger = DarkScheme.error
    val warning = DarkExtras.warning
    val good = DarkScheme.tertiary
    val scrim = Color(0xE6000000)
}

/** Nền cửa sổ lúc khởi động và khi giao diện tối: cùng `background` tối. */
val XdeskDarkBackground: Color = DarkScheme.background

/** Giao diện Xdesk: mặc định Tối, người dùng đổi trong Cài đặt → Giao diện. */
@Composable
fun XdeskTheme(appearance: AppearanceSetting = AppearanceSetting.DARK, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        AppearanceSetting.DARK -> true
        AppearanceSetting.LIGHT -> false
        AppearanceSetting.SYSTEM -> isSystemInDarkTheme()
    }
    val scheme: ColorScheme = if (dark) DarkScheme else LightScheme
    CompositionLocalProvider(LocalExtras provides if (dark) DarkExtras else LightExtras) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
