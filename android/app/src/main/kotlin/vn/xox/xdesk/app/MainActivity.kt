package vn.xox.xdesk.app

import android.os.Build
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.fragment.app.FragmentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.luminance
import vn.xox.xdesk.app.ui.LocalAppearance
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import kotlin.math.roundToInt
import vn.xox.xdesk.app.discovery.NsdBrowser
import vn.xox.xdesk.app.ui.HostListScreen
import vn.xox.xdesk.app.ui.PairingScreen
import vn.xox.xdesk.app.ui.SecuritySettingsScreen
import vn.xox.xdesk.app.ui.StreamScreen
import vn.xox.xdesk.app.ui.UpdatePrompt
import vn.xox.xdesk.app.ui.theme.XdeskTheme

class MainActivity : FragmentActivity() {
    private val controller: ViewerController by viewModels {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST") // Factory.create buộc trả T; chỉ tạo ViewerController.
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                ViewerController((application as XdeskApplication).container, Build.MODEL, ::screenSize, ::maxRefreshRateHz) as T
        }
    }
    private lateinit var browser: NsdBrowser

    private fun maxRefreshRateHz(): Int {
        val rate = if (Build.VERSION.SDK_INT >= 30) {
            display?.refreshRate
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay?.refreshRate
        }
        return rate?.roundToInt()?.coerceAtLeast(30) ?: 60
    }

    /**
     * (rộng px, cao px, mật độ) của vùng stream: cửa sổ đã tính chiều xoay, trừ tai thỏ/camera đục lỗ. Thanh hệ thống không trừ vì
     * màn stream ẩn chúng (immersive). Phải khớp [StreamScreen], vốn chỉ chừa đúng phần displayCutout.
     */
    private fun screenSize(): Triple<Int, Int, Float> {
        val metrics = windowManager.currentWindowMetrics
        val cutout = WindowInsetsCompat.toWindowInsetsCompat(metrics.windowInsets).getInsets(WindowInsetsCompat.Type.displayCutout())
        val bounds = metrics.bounds
        return Triple(bounds.width() - cutout.left - cutout.right, bounds.height() - cutout.top - cutout.bottom, resources.displayMetrics.density)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cửa sổ luôn tràn viền (cả Android 13 chưa ép edge-to-edge): nếu không, hệ điều hành tự chừa chỗ thanh trạng thái đã ẩn
        // và vùng video nhỏ hơn cỡ đã xin với host. Vùng an toàn do Compose chừa.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        @Suppress("DEPRECATION") // Android 13: thanh hệ thống phải trong suốt để màu nền giao diện (sáng/tối) lan tới mép.
        window.apply { statusBarColor = android.graphics.Color.TRANSPARENT; navigationBarColor = android.graphics.Color.TRANSPARENT }
        window.attributes = window.attributes.apply { layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES }
        browser = NsdBrowser(this, controller::updateHosts)
        val updates = (application as XdeskApplication).container.updates
        updates.isSessionActive = { controller.streaming || controller.connecting }
        if (savedInstanceState == null) updates.checkOnStart()
        // Các màn danh sách chừa vùng an toàn (tai thỏ, thanh hệ thống, bàn phím); màn stream ẩn thanh hệ thống nên chỉ chừa tai thỏ,
        // và không chừa chỗ cho bàn phím: tự dịch video lên để vùng video giữ nguyên kích thước (đổi kích thước sẽ mở lại phiên).
        setContent {
            val stream = controller.screen == Screen.STREAM
            val insets = if (stream) Modifier.windowInsetsPadding(WindowInsets.displayCutout) else Modifier.safeDrawingPadding()
            val appearance = (application as XdeskApplication).container.appearance
            XdeskTheme(appearance.setting) {
                val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
                SideEffect { WindowCompat.getInsetsController(window, window.decorView).apply { isAppearanceLightStatusBars = !dark; isAppearanceLightNavigationBars = !dark } }
                CompositionLocalProvider(LocalAppearance provides appearance) {
                    Surface(Modifier.fillMaxSize(), color = if (stream) Color.Black else MaterialTheme.colorScheme.background) { Box(insets) { Root() } }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        browser.start()
    }

    override fun onStop() {
        browser.stop()
        super.onStop()
    }

    @Composable
    private fun Root() {
        val view = LocalView.current
        LaunchedEffect(controller.progress.pairingResult) {
            controller.progress.pairingResult?.let { view.performHapticFeedback(if (it.success) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.REJECT) }
        }
        BackHandler(enabled = controller.screen != Screen.HOSTS) {
            if (controller.screen == Screen.STREAM) controller.disconnect() else controller.screen = Screen.HOSTS
        }
        LaunchedEffect(controller.screen) {
            if (controller.screen == Screen.STREAM) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        when (controller.screen) {
            Screen.HOSTS -> HostListScreen(controller) { browser.stop(); browser.start() }
            Screen.PAIR -> PairingScreen(controller)
            Screen.STREAM -> StreamScreen(controller, window)
            Screen.SECURITY -> SecuritySettingsScreen(controller, (application as XdeskApplication).container.updates)
        }
        if (controller.screen == Screen.HOSTS || controller.screen == Screen.SECURITY) UpdatePrompt((application as XdeskApplication).container.updates)
    }
}
