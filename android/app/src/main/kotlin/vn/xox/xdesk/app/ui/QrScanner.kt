package vn.xox.xdesk.app.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import vn.xox.xdesk.app.ui.theme.extras
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.Alignment
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.NotFoundException
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Quét QR bằng CameraX + ZXing core (chạy cả trên máy không có Google Play Services, không phụ thuộc model tải về).
 * Quyền camera chỉ được xin khi composable này xuất hiện (màn ghép đôi), không xin lúc mở app.
 */
@Composable
fun QrScanner(modifier: Modifier, onResult: (String) -> Unit) {
    val context = LocalContext.current
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var denied by remember { mutableStateOf(false) }
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it; denied = !it }
    LaunchedEffect(Unit) { if (!granted) request.launch(Manifest.permission.CAMERA) }
    if (!granted) {
        Column(modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                if (denied) "Cần quyền Camera để quét mã. Bạn vẫn có thể dán liên kết hoặc so mã 6 số ở dưới." else "Đang xin quyền camera…",
                color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.Center,
            )
            if (denied) Button(
                onClick = { request.launch(Manifest.permission.CAMERA) }, Modifier.heightIn(min = 48.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.extras.primaryFill, contentColor = Color.White),
            ) { Text("Cấp quyền") }
        }
        return
    }
    CameraPreview(modifier, onResult)
}

@Composable
private fun CameraPreview(modifier: Modifier, onResult: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }
    val done = remember { AtomicBoolean(false) }
    val reader = remember {
        MultiFormatReader().apply { setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE))) }
    }
    val bound = remember { AtomicReference<ProcessCameraProvider?>(null) }
    val disposed = remember { AtomicBoolean(false) }
    // Rời màn ghép đôi (đổi tab, điều hướng) → composable bị huỷ → nhả camera ngay, không chờ vòng đời Activity.
    DisposableEffect(Unit) {
        onDispose {
            disposed.set(true)
            bound.getAndSet(null)?.unbindAll()
            executor.shutdown()
        }
    }
    AndroidView(modifier = modifier, factory = { ctx ->
        PreviewView(ctx).also { view ->
            val future = ProcessCameraProvider.getInstance(ctx)
            future.addListener({
                if (disposed.get()) return@addListener
                val provider = future.get()
                val preview = Preview.Builder().build().also { it.setSurfaceProvider(view.surfaceProvider) }
                val analysis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                analysis.setAnalyzer(executor) { image -> decode(reader, image)?.let { if (done.compareAndSet(false, true)) onResult(it) } }
                provider.unbindAll()
                provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
                bound.set(provider)
            }, ContextCompat.getMainExecutor(context))
        }
    })
}

/** Giải mã mặt phẳng Y của khung YUV; QR đối xứng quay nên không cần xoay ảnh. */
private fun decode(reader: MultiFormatReader, image: ImageProxy): String? = image.use {
    val plane = it.planes[0]
    val width = it.width
    val height = it.height
    val rowStride = plane.rowStride
    val buffer = plane.buffer
    val data = ByteArray(width * height)
    for (row in 0 until height) {
        buffer.position(row * rowStride)
        buffer.get(data, row * width, width)
    }
    try {
        reader.decodeWithState(BinaryBitmap(HybridBinarizer(PlanarYUVLuminanceSource(data, width, height, 0, 0, width, height, false)))).text
    } catch (e: NotFoundException) {
        null
    } finally {
        reader.reset()
    }
}
