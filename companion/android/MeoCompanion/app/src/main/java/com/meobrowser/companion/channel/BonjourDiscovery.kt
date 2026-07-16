package com.meobrowser.companion.channel

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

data class DiscoveredHost(val host: String, val port: Int, val name: String)

object BonjourDiscovery {
    private const val TAG = "MeoBonjour"
    private const val SERVICE_TYPE = "_meologin._tcp."

    fun discover(context: Context, timeoutMs: Long = 6000): DiscoveredHost? {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        val found = AtomicReference<DiscoveredHost?>(null)
        val latch = CountDownLatch(1)
        var discoveryListener: NsdManager.DiscoveryListener? = null
        var resolveListener: NsdManager.ResolveListener? = null

        resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "resolve failed: $errorCode")
                latch.countDown()
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                val host = serviceInfo.host?.hostAddress
                if (!host.isNullOrBlank() && serviceInfo.port > 0) {
                    found.set(DiscoveredHost(host, serviceInfo.port, serviceInfo.serviceName ?: "MeoBrowser"))
                }
                latch.countDown()
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
                try {
                    nsd.resolveService(serviceInfo, resolveListener)
                } catch (e: Exception) {
                    Log.w(TAG, "resolve throw", e)
                    latch.countDown()
                }
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {}
        }

        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
            latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: Exception) {
            Log.w(TAG, "discover error", e)
        } finally {
            try {
                discoveryListener?.let { nsd.stopServiceDiscovery(it) }
            } catch (_: Exception) {
            }
        }
        return found.get()
    }
}
