package com.meobrowser.companion.channel

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.util.Log
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * 局域网同端口 TCP 探测：DHCP 换 IP 后用上次 sticky 端口扫同 /24。
 * 仅做 connect，不发业务帧，避免多连接抢握手。
 */
object LanSubnetProbe {
    private const val TAG = "MeoLanProbe"
    private const val DEFAULT_TIMEOUT_MS = 250
    private const val PARALLELISM = 32

    fun probeOne(host: String, port: Int, timeoutMs: Int = DEFAULT_TIMEOUT_MS): Boolean {
        if (host.isBlank() || port <= 0) return false
        return try {
            Socket().use { s ->
                s.connect(InetSocketAddress(host, port), timeoutMs)
                true
            }
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 扫描本机 /24，对 [port] 做并发 TCP 探测；命中即取消其余。
     * @param preferHost 优先试该主机附近末段
     * @param cancelled 外部竞速取消时置 true
     */
    fun scan(
        context: Context,
        port: Int,
        preferHost: String? = null,
        timeoutMs: Int = DEFAULT_TIMEOUT_MS,
        overallTimeoutMs: Long = 4500,
        cancelled: AtomicBoolean? = null
    ): DiscoveredHost? {
        if (port <= 0) return null
        val self = localIpv4(context) ?: return null
        val prefix = self.substringBeforeLast('.', missingDelimiterValue = "")
        if (prefix.isBlank()) return null
        val selfLast = self.substringAfterLast('.').toIntOrNull() ?: return null

        val candidates = orderedCandidates(prefix, selfLast, preferHost)
        if (candidates.isEmpty()) return null

        val found = AtomicReference<DiscoveredHost?>(null)
        val done = AtomicBoolean(false)
        val pool = Executors.newFixedThreadPool(PARALLELISM)
        val futures = ArrayList<Future<*>>(candidates.size)
        try {
            for (ip in candidates) {
                futures.add(pool.submit {
                    if (done.get() || cancelled?.get() == true) return@submit
                    if (!probeOne(ip, port, timeoutMs)) return@submit
                    if (cancelled?.get() == true) return@submit
                    if (found.compareAndSet(null, DiscoveredHost(ip, port, "lan-probe"))) {
                        done.set(true)
                        Log.i(TAG, "hit $ip:$port")
                    }
                })
            }
            val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(overallTimeoutMs)
            for (f in futures) {
                if (found.get() != null || cancelled?.get() == true) break
                val remain = deadline - System.nanoTime()
                if (remain <= 0) break
                try {
                    f.get(remain, TimeUnit.NANOSECONDS)
                } catch (_: Exception) {
                }
            }
        } finally {
            done.set(true)
            for (f in futures) f.cancel(true)
            pool.shutdownNow()
        }
        // 已命中则返回；仅在无结果且被外部取消时放弃
        return found.get()
    }

    /** 扫描本机 /24，收集同端口全部可达主机（用于多设备列表）。 */
    fun scanAll(
        context: Context,
        port: Int,
        preferHost: String? = null,
        timeoutMs: Int = DEFAULT_TIMEOUT_MS,
        overallTimeoutMs: Long = 4500
    ): List<DiscoveredHost> {
        if (port <= 0) return emptyList()
        val self = localIpv4(context) ?: return emptyList()
        val prefix = self.substringBeforeLast('.', missingDelimiterValue = "")
        if (prefix.isBlank()) return emptyList()
        val selfLast = self.substringAfterLast('.').toIntOrNull() ?: return emptyList()
        val candidates = orderedCandidates(prefix, selfLast, preferHost)
        if (candidates.isEmpty()) return emptyList()

        val hits = java.util.concurrent.ConcurrentHashMap<String, DiscoveredHost>()
        val pool = Executors.newFixedThreadPool(PARALLELISM)
        val futures = ArrayList<Future<*>>(candidates.size)
        try {
            for (ip in candidates) {
                futures.add(pool.submit {
                    if (!probeOne(ip, port, timeoutMs)) return@submit
                    hits[ip] = DiscoveredHost(ip, port, "lan-probe")
                    Log.i(TAG, "hit $ip:$port")
                })
            }
            val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(overallTimeoutMs)
            for (f in futures) {
                val remain = deadline - System.nanoTime()
                if (remain <= 0) break
                try {
                    f.get(remain, TimeUnit.NANOSECONDS)
                } catch (_: Exception) {
                }
            }
        } finally {
            for (f in futures) f.cancel(true)
            pool.shutdownNow()
        }
        return hits.values.sortedBy { it.host }
    }

    private fun orderedCandidates(prefix: String, selfLast: Int, preferHost: String?): List<String> {
        val preferLast = preferHost
            ?.takeIf { it.startsWith("$prefix.") }
            ?.substringAfterLast('.')
            ?.toIntOrNull()
        val near = LinkedHashSet<Int>()
        if (preferLast != null) {
            for (d in 0..16) {
                addLast(near, preferLast + d)
                if (d > 0) addLast(near, preferLast - d)
            }
        }
        for (i in 1..254) near.add(i)
        return near
            .filter { it != selfLast }
            .map { "$prefix.$it" }
    }

    private fun addLast(set: LinkedHashSet<Int>, v: Int) {
        if (v in 1..254) set.add(v)
    }

    fun localIpv4(context: Context): String? {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val network = cm.activeNetwork ?: return fallbackInterfaceIpv4()
            val caps = cm.getNetworkCapabilities(network) ?: return fallbackInterfaceIpv4()
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
            ) {
                return fallbackInterfaceIpv4()
            }
            val props = cm.getLinkProperties(network)
            val fromLink = props?.linkAddresses
                ?.mapNotNull { it.address as? Inet4Address }
                ?.firstOrNull { !it.isLoopbackAddress }
                ?.hostAddress
            if (!fromLink.isNullOrBlank()) return fromLink
        }
        return fallbackInterfaceIpv4()
    }

    private fun fallbackInterfaceIpv4(): String? {
        return try {
            NetworkInterface.getNetworkInterfaces()?.toList()
                ?.flatMap { it.inetAddresses.toList() }
                ?.mapNotNull { it as? Inet4Address }
                ?.firstOrNull { !it.isLoopbackAddress && !it.isLinkLocalAddress }
                ?.hostAddress
        } catch (_: Exception) {
            null
        }
    }
}
