package vn.xox.xdesk.app

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import vn.xox.xdesk.app.discovery.NsdBrowser
import vn.xox.xdesk.app.ui.HostListScreen
import vn.xox.xdesk.app.ui.PairingScreen
import vn.xox.xdesk.app.ui.SecuritySettingsScreen
import vn.xox.xdesk.app.ui.StreamScreen

class MainActivity : ComponentActivity() {
    private val controller: ViewerController by viewModels {
        object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST") // Factory.create buộc trả T; chỉ tạo ViewerController.
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                ViewerController((application as XdeskApplication).container, Build.MODEL, ::screenSize) as T
        }
    }
    private lateinit var browser: NsdBrowser

    /** (rộng px, cao px, mật độ) của cửa sổ hiện tại, đã tính chiều xoay. */
    private fun screenSize(): Triple<Int, Int, Float> {
        val bounds = windowManager.currentWindowMetrics.bounds
        return Triple(bounds.width(), bounds.height(), resources.displayMetrics.density)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        browser = NsdBrowser(this, controller::updateHosts)
        // targetSdk 35+ ép edge-to-edge: chừa vùng an toàn (tai thỏ, thanh hệ thống) cho các màn danh sách; màn stream tự lo immersive.
        setContent { MaterialTheme { Surface(Modifier.safeDrawingPadding()) { Root() } } }
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
        BackHandler(enabled = controller.screen != Screen.HOSTS) {
            if (controller.screen == Screen.STREAM) controller.disconnect() else controller.screen = Screen.HOSTS
        }
        LaunchedEffect(controller.screen) {
            if (controller.screen == Screen.STREAM) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        when (controller.screen) {
            Screen.HOSTS -> HostListScreen(controller)
            Screen.PAIR -> PairingScreen(controller)
            Screen.STREAM -> StreamScreen(controller, window)
            Screen.SECURITY -> SecuritySettingsScreen(controller)
        }
    }
}
