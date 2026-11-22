package vn.xox.xdesk.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import java.net.Inet4Address
import java.net.NetworkInterface

enum class TailscaleState {
    ACTIVE,
    INSTALLED_INACTIVE,
    NOT_INSTALLED;

    val statusBadge: String
        get() = when (this) {
            ACTIVE -> "Đang bật"
            INSTALLED_INACTIVE -> "Đang tắt"
            NOT_INSTALLED -> "Chưa cài"
        }

    val actionLabel: String
        get() = if (this == NOT_INSTALLED) "Cài đặt Tailscale" else "Mở Tailscale"

    val settingsSubtitle: String
        get() = when (this) {
            ACTIVE -> "Đang bật · Sẵn sàng kết nối từ xa"
            INSTALLED_INACTIVE -> "Đang tắt · Chạm để mở và bật"
            NOT_INSTALLED -> "Chưa cài đặt · Chạm để cài đặt"
        }

    val detailDescription: String
        get() = when (this) {
            ACTIVE -> "Tailscale đang bật. Bạn có thể kết nối tới máy Mac từ xa bằng IP 100.x.y.z hoặc tên MagicDNS."
            INSTALLED_INACTIVE -> "Tailscale đã cài nhưng đang tắt. Bật Tailscale để kết nối máy Mac từ xa ngoài mạng Wi-Fi."
            NOT_INSTALLED -> "Chưa cài đặt Tailscale. Cài ứng dụng và đăng nhập cùng tài khoản với máy Mac để kết nối từ xa."
        }

    val inlineHint: String
        get() = when (this) {
            INSTALLED_INACTIVE -> "Tailscale đang tắt. Bật Tailscale để kết nối qua IP 100.x.y.z hoặc *.ts.net."
            NOT_INSTALLED -> "Chưa cài đặt Tailscale. Cài Tailscale để kết nối từ xa qua IP 100.x.y.z."
            ACTIVE -> ""
        }
}

/**
 * Nhận diện địa chỉ Tailscale (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`, `*.ts.net`),
 * kiểm tra trạng thái Tailscale trên Android và mở app hoặc cửa hàng để bật/cài.
 */
object TailscaleSupport {
    const val PACKAGE = "com.tailscale.ipn"

    fun isTailscaleHost(raw: String): Boolean {
        val host = extractHost(raw).lowercase()
        if (host.isEmpty()) return false
        if (host.endsWith(".ts.net")) return true
        if (host.startsWith("fd7a:115c:a1e0:")) return true
        val octets = host.split('.')
        if (octets.size == 4) {
            val a = octets[0].toIntOrNull() ?: return false
            val b = octets[1].toIntOrNull() ?: return false
            val c = octets[2].toIntOrNull() ?: return false
            val d = octets[3].toIntOrNull() ?: return false
            if (a in 0..255 && b in 0..255 && c in 0..255 && d in 0..255) {
                return a == 100 && b in 64..127
            }
        }
        return false
    }

    private fun extractHost(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return ""
        if (trimmed.startsWith("[")) {
            val closeIdx = trimmed.indexOf(']')
            if (closeIdx > 1) return trimmed.substring(1, closeIdx)
        }
        val firstColon = trimmed.indexOf(':')
        val lastColon = trimmed.lastIndexOf(':')
        // Nhiều dấu ':' mà không có dấu ngoặc vuông -> IPv6 trần
        if (firstColon != -1 && firstColon != lastColon) return trimmed.substringBefore('%')
        return (if (firstColon != -1) trimmed.substring(0, firstColon) else trimmed).substringBefore('%')
    }

    fun hasActiveInterface(): Boolean {
        val ifaces = try {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        } catch (_: Throwable) {
            return false
        }
        return ifaces.any { iface ->
            val up = try {
                iface.isUp && !iface.isLoopback
            } catch (_: Throwable) {
                false
            }
            if (!up) return@any false
            iface.inetAddresses.asSequence().any { addr ->
                val raw = addr.hostAddress?.substringBefore('%').orEmpty()
                if (addr is Inet4Address) isTailscaleHost(raw)
                else raw.lowercase().startsWith("fd7a:115c:a1e0:")
            }
        }
    }

    fun isInstalled(context: Context): Boolean =
        context.packageManager.getLaunchIntentForPackage(PACKAGE) != null

    fun detect(context: Context): TailscaleState = when {
        hasActiveInterface() -> TailscaleState.ACTIVE
        isInstalled(context) -> TailscaleState.INSTALLED_INACTIVE
        else -> TailscaleState.NOT_INSTALLED
    }

    fun openApp(context: Context): Boolean {
        val intent = context.packageManager.getLaunchIntentForPackage(PACKAGE) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun openInstall(context: Context) {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$PACKAGE"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$PACKAGE"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(market)
        } catch (_: Throwable) {
            try {
                context.startActivity(web)
            } catch (_: Throwable) {
            }
        }
    }

    fun openOrInstall(context: Context, state: TailscaleState) {
        if (state == TailscaleState.NOT_INSTALLED) {
            openInstall(context)
        } else {
            openApp(context)
        }
    }
}
