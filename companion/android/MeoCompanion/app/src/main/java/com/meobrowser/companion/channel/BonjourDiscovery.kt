package com.meobrowser.companion.channel

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

data class DiscoveredHost(val host: String, val port: Int, val name: String) {
    fun endpoint(): String = "$host:$port"
}

object BonjourDiscovery {
    private const val TAG = "MeoBonjour"
    private const val SERVICE_TYPE = "_meologin._tcp."

    fun discover(context: Context, timeoutMs: Long = 6000): DiscoveredHost? =
        discoverAll(context, timeoutMs).firstOrNull()

    /** 收集超时内解析到的全部 `_meologin` 服务（串行 resolve，兼容 NSD 限制）。 */
    fun discoverAll(context: Context, timeoutMs: Long = 5000): List<DiscoveredHost> {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val results = LinkedHashMap<String, DiscoveredHost>()
        val pending = ConcurrentLinkedQueue<NsdServiceInfo>()
        val resolving = AtomicBoolean(false)
        val stopped = AtomicBoolean(false)
        val latch = CountDownLatch(1)
        var discoveryListener: NsdManager.DiscoveryListener? = null

        fun remember(info: NsdServiceInfo) {
            val host = info.host?.hostAddress ?: return
            val port = info.port
            if (host.isBlank() || port <= 0) return
            val name = info.serviceName?.takeIf { it.isNotBlank() } ?: "MeoBrowser"
            synchronized(results) {
                results["$host:$port"] = DiscoveredHost(host, port, name)
            }
        }

        fun pumpResolve() {
            if (stopped.get() || !resolving.compareAndSet(false, true)) return
            val next = pending.poll()
            if (next == null) {
                resolving.set(false)
                return
            }
            try {
                nsd.resolveService(next, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        Log.w(TAG, "resolve failed: $errorCode")
                        resolving.set(false)
                        pumpResolve()
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        remember(serviceInfo)
                        resolving.set(false)
                        pumpResolve()
                    }
                })
            } catch (e: Exception) {
                Log.w(TAG, "resolve throw", e)
                resolving.set(false)
                pumpResolve()
            }
        }

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "start discovery failed: $errorCode")
                latch.countDown()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (!serviceInfo.serviceType.contains("meologin")) return
                pending.offer(serviceInfo)
                pumpResolve()
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
        }

        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            Log.w(TAG, "discover error", e)
        } finally {
            stopped.set(true)
            try {
                discoveryListener?.let { nsd.stopServiceDiscovery(it) }
            } catch (_: Exception) {
            }
            // 再等片刻让进行中的 resolve 收尾
            try {
                Thread.sleep(200)
            } catch (_: Exception) {
            }
        }
        return synchronized(results) { results.values.toList() }
    }
}
