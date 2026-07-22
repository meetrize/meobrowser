package com.meobrowser.companion.channel

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import org.json.JSONObject
import java.io.DataInputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 已配对且未连 Mac 时广告 `_meocompanion._tcp`，接受 Mac 的短连接 `invite` 帧。
 * 服务名：`MeoC-<deviceId>`，便于 Mac 在无 TXT 时也能过滤。
 */
class CompanionInviteAdvertiser(
    private val context: Context,
    private val deviceId: String,
    private val onInvite: () -> Unit
) {
    private val running = AtomicBoolean(false)
    private var serverSocket: ServerSocket? = null
    private var acceptThread: Thread? = null
    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var registeredInfo: NsdServiceInfo? = null

    @Volatile
    private var lastInviteAtMs: Long = 0L

    fun start() {
        if (!running.compareAndSet(false, true)) return
        try {
            val server = ServerSocket(0)
            server.reuseAddress = true
            serverSocket = server
            val port = server.localPort
            acceptThread = Thread({ acceptLoop(server) }, "meo-invite-accept").apply {
                isDaemon = true
                start()
            }
            registerNsd(port)
            Log.i(TAG, "invite advertiser listening port=$port deviceId=$deviceId")
        } catch (e: Exception) {
            Log.e(TAG, "invite advertiser start failed", e)
            stop()
        }
    }

    fun stop() {
        if (!running.getAndSet(false)) {
            // 仍尝试清理，避免半初始化残留
        }
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        acceptThread = null
        unregisterNsd()
    }

    private fun acceptLoop(server: ServerSocket) {
        while (running.get()) {
            try {
                val client = server.accept()
                Thread({ handleClient(client) }, "meo-invite-client").apply {
                    isDaemon = true
                    start()
                }
            } catch (_: Exception) {
                if (!running.get()) break
            }
        }
    }

    private fun handleClient(socket: Socket) {
        try {
            socket.soTimeout = 5000
            val input = DataInputStream(socket.getInputStream())
            val length = input.readInt()
            if (length <= 0 || length > 64 * 1024) return
            val payload = ByteArray(length)
            input.readFully(payload)
            val json = JSONObject(String(payload, Charsets.UTF_8))
            if (json.optString("type") != "invite") return
            if (json.optString("from") != "mac") return
            val target = json.optString("deviceId")
            if (target.isNotBlank() && target != deviceId) {
                Log.i(TAG, "invite ignored: target=$target self=$deviceId")
                return
            }
            val now = System.currentTimeMillis()
            if (now - lastInviteAtMs < INVITE_DEBOUNCE_MS) {
                Log.i(TAG, "invite debounced")
                return
            }
            lastInviteAtMs = now
            Log.i(TAG, "invite received from=${json.optString("hostName")}")
            onInvite()
        } catch (e: Exception) {
            Log.w(TAG, "invite handle failed", e)
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun registerNsd(port: Int) {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsdManager = nsd
        val info = NsdServiceInfo().apply {
            serviceName = serviceNameForDevice(deviceId)
            serviceType = SERVICE_TYPE
            setPort(port)
            try {
                setAttribute("deviceId", deviceId)
            } catch (e: Exception) {
                Log.w(TAG, "setAttribute deviceId failed", e)
            }
        }
        val listener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                registeredInfo = serviceInfo
                Log.i(TAG, "NSD registered name=${serviceInfo.serviceName}")
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "NSD register failed: $errorCode")
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                Log.i(TAG, "NSD unregistered")
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "NSD unregister failed: $errorCode")
            }
        }
        registrationListener = listener
        try {
            nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: Exception) {
            Log.e(TAG, "registerService throw", e)
        }
    }

    private fun unregisterNsd() {
        val nsd = nsdManager
        val listener = registrationListener
        if (nsd != null && listener != null) {
            try {
                nsd.unregisterService(listener)
            } catch (_: Exception) {
            }
        }
        nsdManager = null
        registrationListener = null
        registeredInfo = null
    }

    companion object {
        private const val TAG = "MeoInviteAdv"
        const val SERVICE_TYPE = "_meocompanion._tcp."
        private const val INVITE_DEBOUNCE_MS = 1500L

        fun serviceNameForDevice(deviceId: String): String {
            // Bonjour 服务名 ≤63 字节；UUID 36 + 前缀足够
            return "MeoC-$deviceId"
        }
    }
}
