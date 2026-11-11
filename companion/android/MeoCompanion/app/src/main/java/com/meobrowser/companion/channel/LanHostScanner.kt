package com.meobrowser.companion.channel

import android.content.Context
import com.meobrowser.companion.pairing.KnownLanHost
import com.meobrowser.companion.pairing.PairingPrefs
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** 合并 Bonjour 与同端口子网探测，供互联页多设备列表使用。 */
object LanHostScanner {
    fun scan(context: Context, prefs: PairingPrefs): List<KnownLanHost> {
        val bonjourRef = AtomicReference<List<DiscoveredHost>>(emptyList())
        val subnetRef = AtomicReference<List<DiscoveredHost>>(emptyList())
        val pool = Executors.newFixedThreadPool(2)
        try {
            pool.execute {
                bonjourRef.set(BonjourDiscovery.discoverAll(context, timeoutMs = 4500))
            }
            val ports = LinkedHashSet<Int>()
            if (prefs.lastPort > 0) ports.add(prefs.lastPort)
            for (h in prefs.knownHosts()) {
                if (h.port > 0) ports.add(h.port)
            }
            if (ports.isNotEmpty()) {
                pool.execute {
                    val all = LinkedHashMap<String, DiscoveredHost>()
                    for (port in ports) {
                        for (hit in LanSubnetProbe.scanAll(
                            context = context,
                            port = port,
                            preferHost = prefs.lastHost
                        )) {
                            all[hit.endpoint()] = hit
                        }
                    }
                    subnetRef.set(all.values.toList())
                }
            }
            pool.shutdown()
            pool.awaitTermination(6, TimeUnit.SECONDS)
        } finally {
            pool.shutdownNow()
        }

        val now = System.currentTimeMillis()
        val merged = LinkedHashMap<String, KnownLanHost>()
        fun put(d: DiscoveredHost) {
            val prev = merged[d.endpoint()]
            val name = when {
                d.name.isNotBlank() && d.name != "lan-probe" -> d.name
                prev != null -> prev.name
                else -> "局域网主机"
            }
            merged[d.endpoint()] = KnownLanHost(d.host, d.port, name, now)
        }
        for (d in bonjourRef.get()) put(d)
        for (d in subnetRef.get()) put(d)
        val list = merged.values.sortedBy { it.name.lowercase() + it.endpoint() }
        prefs.mergeDiscoveredHosts(list)
        return prefs.knownHosts()
    }
}
