package com.meobrowser.companion.channel

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.meobrowser.companion.R
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.ui.MainActivity
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * 前台服务：维持与 Mac 的长连接。Client 放在 [CompanionSession] 单例中，避免 Service 重建丢 socket。
 */
class CompanionConnectionService : Service() {
    private val executor = CompanionSession.executor
    private val client: CompanionClient get() = CompanionSession.client
    private lateinit var prefs: PairingPrefs

    override fun onCreate() {
        super.onCreate()
        prefs = PairingPrefs(this)
        CompanionSession.service = this
        CompanionSession.attachHandlers(this)
        com.meobrowser.companion.sms.SmsListenCoordinator.start(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val pairingCode = intent.getStringExtra(EXTRA_PAIRING_CODE)
                val hostOverride = intent.getStringExtra(EXTRA_HOST_OVERRIDE)
                startForeground(NOTIF_ID, buildNotification("正在连接…"))
                executor.execute { connectInternal(pairingCode, hostOverride) }
            }
            ACTION_DISCONNECT -> {
                CompanionSession.userRequestedDisconnect = true
                executor.execute {
                    client.disconnect(quiet = true)
                    CompanionSession.statusText = "已断开"
                    CompanionSession.notifyStatus()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
            ACTION_SEND_OTP -> {
                val code = intent.getStringExtra(EXTRA_OTP_CODE) ?: return START_STICKY
                // 若进程里 Service 被拉起但尚无前台，补一次，避免被系统杀掉。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForeground(NOTIF_ID, buildNotification(CompanionSession.statusText))
                }
                CompanionSession.sendOtp(code)
            }
            else -> {
                // 被系统重启时尝试用已保存 token 重连
                if (!prefs.deviceToken.isNullOrBlank() && !client.isConnected) {
                    startForeground(NOTIF_ID, buildNotification("正在重连…"))
                    executor.execute { connectInternal(null, null) }
                }
            }
        }
        return START_STICKY
    }

    private fun connectInternal(pairingCode: String?, hostOverride: String?) {
        try {
            CompanionSession.userRequestedDisconnect = false
            // 已连接且只需保活：不重复建连
            if (client.isConnected && pairingCode.isNullOrBlank()) {
                CompanionSession.statusText = "已连接（保持中）"
                CompanionSession.notifyStatus()
                updateNotification(CompanionSession.statusText)
                return
            }
            val (host, port) = resolveTarget(hostOverride)
            client.connect(host, port)
            prefs.lastHost = host
            prefs.lastPort = port
            prefs.lastHostOverride = "$host:$port"
            if (!pairingCode.isNullOrBlank()) {
                prefs.lastPairingCode = pairingCode
            }

            val hello = JSONObject()
            hello.put("v", 1)
            hello.put("type", "hello")
            hello.put("deviceId", prefs.deviceId)
            val token = prefs.deviceToken
            if (!token.isNullOrBlank() && pairingCode.isNullOrBlank()) {
                hello.put("deviceToken", token)
            } else {
                if (pairingCode.isNullOrBlank()) {
                    throw IllegalStateException("需要配对码")
                }
                hello.put("pairingToken", pairingCode)
            }
            client.send(hello)
            CompanionSession.statusText = "已连接 $host:$port，等待 hello_ok"
            updateNotification(CompanionSession.statusText)
            CompanionSession.notifyStatus()
        } catch (e: Exception) {
            Log.e(TAG, "connect failed", e)
            CompanionSession.statusText = "连接失败：${e.message}"
            CompanionSession.notifyStatus()
            client.disconnect(quiet = true)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun resolveTarget(hostOverride: String?): Pair<String, Int> {
        if (!hostOverride.isNullOrBlank()) {
            val parts = hostOverride.trim().split(":")
            val host = parts[0]
            val port = parts.getOrNull(1)?.toIntOrNull() ?: 0
            if (port <= 0) throw IllegalArgumentException("手动主机需包含端口，如 192.168.1.10:12345")
            return host to port
        }
        // 优先已保存的主机，避免每次推码去 Bonjour（慢且可能失败）
        if (!prefs.lastHost.isNullOrBlank() && prefs.lastPort > 0) {
            return prefs.lastHost!! to prefs.lastPort
        }
        val discovered = BonjourDiscovery.discover(this)
            ?: throw IllegalStateException("未发现 MeoBrowser（_meologin._tcp），请确认同 Wi‑Fi 或填写手动主机")
        return discovered.host to discovered.port
    }

    fun handleMessage(json: JSONObject) {
        when (json.optString("type")) {
            "hello_ok" -> {
                val token = json.optString("deviceToken")
                if (token.isNotBlank()) {
                    prefs.deviceToken = token
                }
                val hostName = json.optString("hostName", "MeoBrowser")
                CompanionSession.statusText = "已配对 · $hostName（连接保持中）"
                updateNotification(CompanionSession.statusText)
                CompanionSession.notifyStatus()
            }
            "otp_ok" -> {
                CompanionSession.notifyStatus()
            }
            "error" -> {
                CompanionSession.statusText = "错误：${json.optString("message")}"
                CompanionSession.notifyStatus()
            }
        }
    }

    fun onPeerClosed() {
        if (CompanionSession.userRequestedDisconnect) {
            return
        }
        CompanionSession.statusText = "连接中断，尝试重连…"
        CompanionSession.notifyStatus()
        updateNotification(CompanionSession.statusText)
        // 有 deviceToken 时自动重连，不 stopSelf，保持前台服务
        if (!prefs.deviceToken.isNullOrBlank()) {
            executor.execute {
                try {
                    Thread.sleep(400)
                    if (CompanionSession.userRequestedDisconnect || client.isConnected) return@execute
                    connectInternal(null, null)
                } catch (e: Exception) {
                    Log.e(TAG, "reconnect failed", e)
                    CompanionSession.statusText = "重连失败：${e.message}"
                    CompanionSession.notifyStatus()
                }
            }
        } else {
            CompanionSession.statusText = "已断开"
            CompanionSession.notifyStatus()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun buildNotification(text: String): Notification {
        ensureChannel()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    fun updateNotification(text: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(text))
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(CHANNEL_ID, "Companion", NotificationManager.IMPORTANCE_LOW)
        nm.createNotificationChannel(channel)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        if (CompanionSession.service === this) {
            CompanionSession.service = null
        }
        // 不销毁单例 client：若仅服务重建，可继续用；用户主动断开时已 quiet disconnect
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MeoCompanionSvc"
        private const val CHANNEL_ID = "meo_companion"
        private const val NOTIF_ID = 42
        const val ACTION_CONNECT = "com.meobrowser.companion.CONNECT"
        const val ACTION_DISCONNECT = "com.meobrowser.companion.DISCONNECT"
        const val ACTION_SEND_OTP = "com.meobrowser.companion.SEND_OTP"
        const val EXTRA_PAIRING_CODE = "pairing_code"
        const val EXTRA_HOST_OVERRIDE = "host_override"
        const val EXTRA_OTP_CODE = "otp_code"

        fun startConnect(context: Context, pairingCode: String?, hostOverride: String?) {
            val intent = Intent(context, CompanionConnectionService::class.java).apply {
                action = ACTION_CONNECT
                putExtra(EXTRA_PAIRING_CODE, pairingCode)
                putExtra(EXTRA_HOST_OVERRIDE, hostOverride)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun disconnect(context: Context) {
            val intent = Intent(context, CompanionConnectionService::class.java).apply {
                action = ACTION_DISCONNECT
            }
            context.startService(intent)
        }

        fun sendOtp(context: Context, code: String) {
            val intent = Intent(context, CompanionConnectionService::class.java).apply {
                action = ACTION_SEND_OTP
                putExtra(EXTRA_OTP_CODE, code)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && CompanionSession.service == null) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}

object CompanionSession {
    val client = CompanionClient()
    val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "meo-companion-io").apply { isDaemon = true }
    }

    @Volatile
    var service: CompanionConnectionService? = null

    @Volatile
    var statusText: String = "未连接"

    @Volatile
    var lastOtpHint: String = "无"

    /** 最近一次解析到的完整验证码（界面大号展示，不打码） */
    @Volatile
    var lastOtpCode: String = ""

    @Volatile
    var lastOtpSource: String = ""

    @Volatile
    var lastSmsEvent: String = ""

    @Volatile
    var userRequestedDisconnect: Boolean = false

    private val statusListeners = java.util.concurrent.CopyOnWriteArraySet<(String, String) -> Unit>()

    fun addStatusListener(listener: (String, String) -> Unit) {
        statusListeners.add(listener)
        listener(statusText, displayOtpLine())
    }

    fun removeStatusListener(listener: (String, String) -> Unit) {
        statusListeners.remove(listener)
    }

    fun displayOtpLine(): String {
        return if (lastOtpCode.isNotBlank()) lastOtpCode else lastOtpHint
    }

    fun notifyStatus() {
        val status = statusText
        val otp = displayOtpLine()
        for (listener in statusListeners) {
            try {
                listener(status, otp)
            } catch (_: Exception) {
            }
        }
        service?.updateNotification(status)
    }

    /** 短信监听过程提示（未解析出码时也会更新，便于排查「广播有没有进 App」） */
    fun noteSmsEvent(message: String) {
        lastSmsEvent = message
        // 已有完整验证码时，不覆盖大号展示；事件只放 lastSmsEvent
        if (lastOtpCode.isBlank()) {
            if (lastOtpHint == "无" || lastOtpHint.startsWith("监听") || lastOtpHint.startsWith("收到") ||
                lastOtpHint.startsWith("已收到") || lastOtpHint.startsWith("短信") ||
                lastOtpHint.startsWith("通知")
            ) {
                lastOtpHint = message
            }
        }
        notifyStatus()
    }

    /** 已解析出验证码：立刻刷新 UI（完整明文），再异步推送 */
    fun markOtpDetected(code: String, source: String) {
        lastOtpCode = code
        lastOtpSource = source
        lastOtpHint = code
        lastSmsEvent = "已解析（$source）"
        notifyStatus()
    }

    fun attachHandlers(svc: CompanionConnectionService) {
        client.onMessage = { json -> svc.handleMessage(json) }
        client.onClosed = { svc.onPeerClosed() }
    }

    fun sendOtp(code: String) {
        executor.execute { sendOtpOnWorker(code) }
    }

    private fun sendOtpOnWorker(code: String) {
        val svc = service
        val prefs = if (svc != null) {
            PairingPrefs(svc)
        } else {
            statusText = "服务未就绪，请先点「连接 / 配对」"
            notifyStatus()
            return
        }
        val token = prefs.deviceToken
        if (token.isNullOrBlank()) {
            statusText = "尚未配对，无法推码"
            notifyStatus()
            return
        }
        // 掉线则用已保存 host + deviceToken 自动重连（保持单例 socket）
        if (!client.isConnected) {
            statusText = "连接已断，正在重连…"
            notifyStatus()
            try {
                val host = prefs.lastHost
                val port = prefs.lastPort
                if (host.isNullOrBlank() || port <= 0) {
                    statusText = "未连接，请先点「连接 / 配对」"
                    notifyStatus()
                    return
                }
                client.connect(host, port)
                val hello = JSONObject()
                hello.put("v", 1)
                hello.put("type", "hello")
                hello.put("deviceId", prefs.deviceId)
                hello.put("deviceToken", token)
                client.send(hello)
                Thread.sleep(350)
            } catch (e: Exception) {
                Log.e("MeoCompanion", "auto-reconnect failed", e)
                statusText = "重连失败，无法推码：${e.message}"
                notifyStatus()
                return
            }
        }
        if (!client.isConnected) {
            statusText = "未连接，无法推码"
            notifyStatus()
            return
        }
        try {
            val json = JSONObject()
            json.put("v", 1)
            json.put("type", "otp")
            json.put("code", code)
            json.put("ts", System.currentTimeMillis() / 1000L)
            json.put("deviceToken", token)
            client.send(json)
            lastOtpCode = code
            lastOtpHint = code
            lastSmsEvent = "已推送到 Mac"
            if (!statusText.contains("连接保持中")) {
                statusText = statusText
                    .substringBefore("（")
                    .trim()
                    .ifEmpty { "已配对" } + "（连接保持中）"
            }
            notifyStatus()
            Log.i("MeoCompanion", "otp pushed length=${code.length}")
        } catch (e: Exception) {
            Log.e("MeoCompanion", "send otp failed", e)
            statusText = "推码失败：${e.message}"
            notifyStatus()
        }
    }

    fun pushOtp(context: Context, code: String) {
        if (service != null && client.isConnected) {
            sendOtp(code)
        } else {
            CompanionConnectionService.sendOtp(context.applicationContext, code)
        }
    }
}
