package vn.xox.xdesk.app.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager

/**
 * Tìm host Xdesk trên LAN bằng NSD (`_xdesk._tcp`, TXT `id`/`n`/`v`). Giữ [WifiManager.MulticastLock] trong lúc tìm (nhiều
 * máy Android lọc multicast khi màn hình tắt). NsdManager chỉ cho một `resolveService` tại một thời điểm nên xếp hàng.
 * Callback `onHosts` gọi từ thread của NsdManager: người nhận tự chuyển sang main thread.
 */
class NsdBrowser(context: Context, private val onHosts: (List<DiscoveredHost>) -> Unit) {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val multicastLock = (context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
        .createMulticastLock("xdesk-nsd").apply { setReferenceCounted(false) }
    private val found = LinkedHashMap<String, DiscoveredHost>()
    private val toResolve = ArrayDeque<NsdServiceInfo>()
    private var resolving = false
    private var running = false

    @Synchronized
    fun start() {
        if (running) return
        running = true
        multicastLock.acquire()
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
    }

    @Synchronized
    fun stop() {
        if (!running) return
        running = false
        try { nsd.stopServiceDiscovery(discovery) } catch (e: IllegalArgumentException) { /* chưa/không còn đăng ký */ }
        if (multicastLock.isHeld) multicastLock.release()
        found.clear()
        toResolve.clear()
        resolving = false
    }

    @Synchronized
    private fun enqueue(info: NsdServiceInfo) {
        toResolve.addLast(info)
        resolveNext()
    }

    @Synchronized
    private fun resolveNext() {
        if (resolving || !running) return
        val next = toResolve.removeFirstOrNull() ?: return
        resolving = true
        @Suppress("DEPRECATION") // registerServiceInfoCallback chỉ có từ API 34; minSdk 31.
        nsd.resolveService(next, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = finishResolve(null)
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) = finishResolve(serviceInfo)
        })
    }

    @Synchronized
    private fun finishResolve(info: NsdServiceInfo?) {
        resolving = false
        val host = info?.let(::toHost)
        if (host != null) {
            found[info.serviceName] = host
            onHosts(found.values.toList())
        }
        resolveNext()
    }

    /** Bỏ qua mục thiếu TXT `id` (không phải Xdesk hợp lệ). */
    private fun toHost(info: NsdServiceInfo): DiscoveredHost? {
        val address = info.host?.hostAddress ?: return null
        val id = info.attributes["id"]?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() } ?: return null
        val name = info.attributes["n"]?.toString(Charsets.UTF_8)?.takeIf { it.isNotEmpty() } ?: info.serviceName
        return DiscoveredHost(id, name, address.substringBefore('%'), info.port)
    }

    private val discovery = object : NsdManager.DiscoveryListener {
        override fun onServiceFound(serviceInfo: NsdServiceInfo) = enqueue(serviceInfo)

        override fun onServiceLost(serviceInfo: NsdServiceInfo) {
            synchronized(this@NsdBrowser) { found.remove(serviceInfo.serviceName) }
            onHosts(synchronized(this@NsdBrowser) { found.values.toList() })
        }

        override fun onDiscoveryStarted(serviceType: String) = Unit
        override fun onDiscoveryStopped(serviceType: String) = Unit
        override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) = stop()
        override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
    }

    companion object {
        const val SERVICE_TYPE = "_xdesk._tcp"
    }
}
