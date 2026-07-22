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
import com.meobrowser.companion.a11y.WeChatReplyExecutor
import com.meobrowser.companion.browser.BrowserActivity
import com.meobrowser.companion.pairing.CompanionAuthMode
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.call.CallEventPayload
import com.meobrowser.companion.call.CallStateMonitor
import com.meobrowser.companion.sms.OtpNotificationListener
import com.meobrowser.companion.sms.PhoneNotificationPayload
import com.meobrowser.companion.sms.AppIconExporter
import com.meobrowser.companion.sync.SyncEngine
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * 前台服务：维持与 Mac 的长连接。Client 放在 [CompanionSession] 单例中，避免 Service 重建丢 socket。
 */
class CompanionConnectionService : Service() {
    private val executor = CompanionSession.executor
    private val client: CompanionClient get() = CompanionSession.client
    private lateinit var prefs: PairingPrefs
    private var inviteAdvertiser: CompanionInviteAdvertiser? = null

    override fun onCreate() {
        super.onCreate()
        prefs = PairingPrefs(this)
        CompanionSession.service = this
        CompanionSession.attachHandlers(this)
        com.meobrowser.companion.sms.SmsListenCoordinator.start(this)
        CallStateMonitor.start(this)
        refreshInviteAdvertiser()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val pairingCode = intent.getStringExtra(EXTRA_PAIRING_CODE)
                val hostOverride = intent.getStringExtra(EXTRA_HOST_OVERRIDE)
                val forceSecurityCode = intent.getStringExtra(EXTRA_FORCE_SECURITY_CODE)
                CompanionSession.cancelReconnect()
                CompanionSession.userRequestedDisconnect = false
                startForeground(NOTIF_ID, buildNotification("正在连接…"))
                executor.execute { connectInternal(pairingCode, hostOverride, forceSecurityCode) }
            }
            ACTION_DISCONNECT -> {
                CompanionSession.userRequestedDisconnect = true
                CompanionSession.cancelReconnect()
                stopInviteAdvertiser()
                executor.execute {
                    client.disconnect(quiet = true)
                    CompanionSession.clearSessionIconState()
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
                // 被系统重启时尝试重连：优先 deviceToken；安全码模式可回退用安全码
                if (!client.isConnected && canPersistReconnect()) {
                    startForeground(NOTIF_ID, buildNotification("正在重连…"))
                    executor.execute { reconnectOnce(forceRediscover = false) }
                }
            }
        }
        return START_STICKY
    }

    /** 已配对且允许自动连接时，断线后保持 FGS 并持续重试。 */
    private fun canPersistReconnect(): Boolean {
        if (!prefs.autoConnectOnLaunch) return false
        if (!prefs.deviceToken.isNullOrBlank()) return true
        return prefs.authMode == CompanionAuthMode.SECURITY_CODE &&
            !prefs.securityCode.isNullOrBlank()
    }

    private fun connectInternal(
        pairingCode: String?,
        hostOverride: String?,
        forceSecurityCode: String? = null,
        forceRediscover: Boolean = false
    ) {
        try {
            CompanionSession.userRequestedDisconnect = false
            // 已连接且只需保活：不重复建连
            if (client.isConnected && pairingCode.isNullOrBlank()) {
                CompanionSession.resetReconnectBackoff()
                CompanionSession.statusText = "已连接（保持中）"
                CompanionSession.notifyStatus()
                updateNotification(CompanionSession.statusText)
                return
            }
            val (host, port) = resolveTarget(hostOverride, forceRediscover)
            client.connect(host, port)
            prefs.lastHost = host
            prefs.lastPort = port
            prefs.lastHostOverride = "$host:$port"

            val securityMode = prefs.authMode == CompanionAuthMode.SECURITY_CODE
            val codeToSend = when {
                !pairingCode.isNullOrBlank() -> pairingCode
                securityMode && !forceSecurityCode.isNullOrBlank() && prefs.deviceToken.isNullOrBlank() ->
                    forceSecurityCode
                securityMode && prefs.deviceToken.isNullOrBlank() && !prefs.securityCode.isNullOrBlank() ->
                    prefs.securityCode
                else -> null
            }
            if (!codeToSend.isNullOrBlank()) {
                if (securityMode) {
                    prefs.securityCode = codeToSend
                } else {
                    prefs.lastPairingCode = codeToSend
                }
            }

            val hello = JSONObject()
            hello.put("v", 1)
            hello.put("type", "hello")
            hello.put("deviceId", prefs.deviceId)
            val token = prefs.deviceToken
            if (!token.isNullOrBlank() && codeToSend.isNullOrBlank()) {
                hello.put("deviceToken", token)
            } else {
                val code = codeToSend
                if (code.isNullOrBlank()) {
                    throw IllegalStateException(
                        if (securityMode) "需要安全码" else "需要配对码"
                    )
                }
                hello.put("pairingToken", code)
            }
            client.send(hello)
            CompanionSession.statusText = "已连接 $host:$port，等待 hello_ok"
            updateNotification(CompanionSession.statusText)
            CompanionSession.notifyStatus()
            // 已在连 Mac：先停 invite 广告，避免重复唤醒
            stopInviteAdvertiser()
        } catch (e: Exception) {
            Log.e(TAG, "connect failed", e)
            CompanionSession.statusText = "连接失败：${e.message}"
            CompanionSession.notifyStatus()
            client.disconnect(quiet = true)
            if (!CompanionSession.userRequestedDisconnect && canPersistReconnect()) {
                refreshInviteAdvertiser()
                scheduleReconnect(fromFailure = true)
            } else {
                stopInviteAdvertiser()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    /**
     * 解析目标主机。
     * @param forceRediscover true 时优先 Bonjour（Mac 端口/IP 可能已变）；否则先用缓存。
     */
    private fun resolveTarget(hostOverride: String?, forceRediscover: Boolean): Pair<String, Int> {
        if (!hostOverride.isNullOrBlank()) {
            val parts = hostOverride.trim().split(":")
            val host = parts[0]
            val port = parts.getOrNull(1)?.toIntOrNull() ?: 0
            if (port <= 0) throw IllegalArgumentException("手动主机需包含端口，如 192.168.1.10:12345")
            return host to port
        }
        val cachedHost = prefs.lastHost
        val cachedPort = prefs.lastPort
        val hasCache = !cachedHost.isNullOrBlank() && cachedPort > 0

        if (forceRediscover || !hasCache) {
            val discovered = BonjourDiscovery.discover(this)
            if (discovered != null) {
                return discovered.host to discovered.port
            }
            if (hasCache) {
                Log.w(TAG, "Bonjour miss, fallback to cached $cachedHost:$cachedPort")
                return cachedHost!! to cachedPort
            }
            throw IllegalStateException("未发现 MeoBrowser（_meologin._tcp），请确认同 Wi‑Fi 或填写手动主机")
        }

        // 优先已保存的主机，避免每次推码去 Bonjour（慢且可能失败）
        return cachedHost!! to cachedPort
    }

    /** 指数退避：0.5s → 1s → 2s → … 上限 60s。每 3 次失败强制 Bonjour。 */
    private fun scheduleReconnect(fromFailure: Boolean) {
        if (CompanionSession.userRequestedDisconnect) return
        if (!canPersistReconnect()) {
            CompanionSession.statusText = "已断开"
            CompanionSession.notifyStatus()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        if (client.isConnected) return

        if (fromFailure) {
            CompanionSession.consecutiveFailures += 1
        }
        val failures = CompanionSession.consecutiveFailures.coerceAtLeast(1)
        val exp = (failures - 1).coerceAtMost(7)
        val delayMs = (500L * (1L shl exp)).coerceAtMost(60_000L)
        val generation = CompanionSession.nextReconnectGeneration()
        val forceBonjour = failures >= 3 && failures % 3 == 0
        val waitSec = (delayMs + 999) / 1000
        CompanionSession.statusText = "等待 Mac（${waitSec}s 后重试）"
        CompanionSession.notifyStatus()
        updateNotification(CompanionSession.statusText)
        startForeground(NOTIF_ID, buildNotification(CompanionSession.statusText))
        refreshInviteAdvertiser()

        CompanionSession.scheduleReconnectDelay(delayMs) {
            if (generation != CompanionSession.reconnectGeneration) return@scheduleReconnectDelay
            if (CompanionSession.userRequestedDisconnect || client.isConnected) return@scheduleReconnectDelay
            executor.execute { reconnectOnce(forceRediscover = forceBonjour) }
        }
    }

    private fun reconnectOnce(forceRediscover: Boolean) {
        if (CompanionSession.userRequestedDisconnect || client.isConnected) return
        if (!canPersistReconnect()) return
        CompanionSession.statusText = "正在重连…"
        CompanionSession.notifyStatus()
        updateNotification(CompanionSession.statusText)
        val canToken = !prefs.deviceToken.isNullOrBlank()
        connectInternal(
            pairingCode = if (canToken) null else prefs.securityCode,
            hostOverride = null,
            forceSecurityCode = prefs.securityCode,
            forceRediscover = forceRediscover
        )
    }

    /** Mac invite 到达：立刻取消退避并用 Bonjour 找 Mac。 */
    fun onMacInvite() {
        // accept 线程回调：全部切回 IO 线程，避免与 connect 交错
        executor.execute {
            if (CompanionSession.userRequestedDisconnect) return@execute
            if (client.isConnected) return@execute
            if (!canPersistReconnect()) return@execute
            CompanionSession.cancelReconnect()
            CompanionSession.consecutiveFailures = 0
            CompanionSession.statusText = "收到 Mac 邀请，正在连接…"
            CompanionSession.notifyStatus()
            updateNotification(CompanionSession.statusText)
            startForeground(NOTIF_ID, buildNotification(CompanionSession.statusText))
            reconnectOnce(forceRediscover = true)
        }
    }

    private fun refreshInviteAdvertiser() {
        if (CompanionSession.userRequestedDisconnect || client.isConnected || !canPersistReconnect()) {
            stopInviteAdvertiser()
            return
        }
        if (inviteAdvertiser != null) return
        val adv = CompanionInviteAdvertiser(
            context = applicationContext,
            deviceId = prefs.deviceId,
            onInvite = { onMacInvite() }
        )
        inviteAdvertiser = adv
        adv.start()
    }

    private fun stopInviteAdvertiser() {
        inviteAdvertiser?.stop()
        inviteAdvertiser = null
    }

    fun handleMessage(json: JSONObject) {
        when (json.optString("type")) {
            "hello_ok" -> {
                val token = json.optString("deviceToken")
                if (token.isNotBlank()) {
                    prefs.deviceToken = token
                }
                CompanionSession.resetReconnectBackoff()
                val hostName = json.optString("hostName", "MeoBrowser")
                CompanionSession.statusText = "已配对 · $hostName（连接保持中）"
                updateNotification(CompanionSession.statusText)
                CompanionSession.notifyStatus()
                stopInviteAdvertiser()
                SyncEngine.onConnected(applicationContext)
            }
            "otp_ok" -> {
                CompanionSession.notifyStatus()
            }
            "open_url_ok" -> {
                CompanionSession.lastSmsEvent = "已发送到 Mac"
                CompanionSession.notifyStatus()
            }
            "phone_notification_ok" -> {
                val id = json.optString("id")
                CompanionSession.lastSmsEvent =
                    if (id.isNotBlank()) "通知镜像已确认" else "通知镜像已确认"
                CompanionSession.notifyStatus()
            }
            "phone_notification_pull" -> {
                val requestId = json.optString("requestId")
                executor.execute {
                    CompanionSession.performPhoneNotificationPull(requestId)
                }
            }
            "wechat_reply" -> {
                val requestId = json.optString("requestId")
                val contact = json.optString("contact")
                val text = json.optString("text")
                val notificationId = json.optString("notificationId").ifBlank { null }
                val packageName = json.optString("packageName").ifBlank {
                    com.meobrowser.companion.a11y.WeChatReplyIntentCache.WECHAT_PACKAGE
                }
                executor.execute {
                    CompanionSession.handleWeChatReply(
                        requestId = requestId,
                        contact = contact,
                        text = text,
                        notificationId = notificationId,
                        packageName = packageName,
                    )
                }
            }
            "app_icon_ok" -> {
                val pkg = json.optString("packageName")
                val hash = json.optString("iconHash")
                if (pkg.isNotBlank() && hash.isNotBlank()) {
                    CompanionSession.markAppIconPushed(pkg, hash)
                }
            }
            "call_event_ok" -> {
                CompanionSession.lastSmsEvent = "来电提醒已确认"
                CompanionSession.notifyStatus()
            }
            "sync_hello", "sync_pull", "sync_push", "sync_chunk", "sync_ack", "sync_error" -> {
                SyncEngine.handleMessage(applicationContext, json)
            }
            "error" -> {
                val message = json.optString("message")
                CompanionSession.statusText = "错误：$message"
                CompanionSession.notifyStatus()
                CompanionSession.noteAppIconError(message)
                // 安全码模式：token 失效时清掉并用安全码重连
                if (prefs.authMode == CompanionAuthMode.SECURITY_CODE &&
                    message.contains("deviceToken", ignoreCase = true) &&
                    !prefs.securityCode.isNullOrBlank()
                ) {
                    prefs.deviceToken = null
                    executor.execute {
                        try {
                            Thread.sleep(300)
                            if (CompanionSession.userRequestedDisconnect) return@execute
                            connectInternal(
                                pairingCode = prefs.securityCode,
                                hostOverride = null,
                                forceSecurityCode = prefs.securityCode
                            )
                        } catch (e: Exception) {
                            Log.e(TAG, "security re-pair failed", e)
                        }
                    }
                }
            }
        }
    }

    fun onPeerClosed() {
        CompanionSession.clearSessionIconState()
        if (CompanionSession.userRequestedDisconnect) {
            return
        }
        CompanionSession.statusText = "连接中断，尝试重连…"
        CompanionSession.notifyStatus()
        updateNotification(CompanionSession.statusText)
        if (canPersistReconnect()) {
            // 首次断线尽快试一次，再进入指数退避
            CompanionSession.consecutiveFailures = 0
            refreshInviteAdvertiser()
            scheduleReconnect(fromFailure = true)
        } else {
            stopInviteAdvertiser()
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
            Intent(this, BrowserActivity::class.java),
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
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.fgs_channel_name),
            NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(channel)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopInviteAdvertiser()
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
        const val EXTRA_FORCE_SECURITY_CODE = "force_security_code"
        const val EXTRA_OTP_CODE = "otp_code"

        fun startConnect(
            context: Context,
            pairingCode: String?,
            hostOverride: String?,
            forceSecurityCode: String? = null
        ) {
            val intent = Intent(context, CompanionConnectionService::class.java).apply {
                action = ACTION_CONNECT
                putExtra(EXTRA_PAIRING_CODE, pairingCode)
                putExtra(EXTRA_HOST_OVERRIDE, hostOverride)
                putExtra(EXTRA_FORCE_SECURITY_CODE, forceSecurityCode)
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

    /** 作废挂起的退避重连任务。 */
    private val reconnectGenerationCounter = AtomicInteger(0)
    var reconnectGeneration: Int
        get() = reconnectGenerationCounter.get()
        set(value) { reconnectGenerationCounter.set(value) }

    /** 连续连接失败次数（hello_ok 后清零）。 */
    @Volatile
    var consecutiveFailures: Int = 0

    private val reconnectScheduler: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "meo-companion-reconnect").apply { isDaemon = true }
        }
    private val pendingReconnect = AtomicReference<ScheduledFuture<*>?>(null)

    fun nextReconnectGeneration(): Int = reconnectGenerationCounter.incrementAndGet()

    fun cancelReconnect() {
        reconnectGenerationCounter.incrementAndGet()
        pendingReconnect.getAndSet(null)?.cancel(false)
    }

    fun resetReconnectBackoff() {
        consecutiveFailures = 0
        cancelReconnect()
    }

    fun scheduleReconnectDelay(delayMs: Long, block: () -> Unit) {
        pendingReconnect.getAndSet(null)?.cancel(false)
        val future = reconnectScheduler.schedule(block, delayMs, TimeUnit.MILLISECONDS)
        pendingReconnect.set(future)
    }

    /** 本 TCP 会话已成功推送的 package → iconHash */
    private val sessionIconPushed = ConcurrentHashMap<String, String>()

    /** 本会话导出/发送失败后不再重试的 package */
    private val sessionIconFailed = ConcurrentHashMap.newKeySet<String>()

    /** 最近一次成功推图标的时间，用于 ≤2 icons/秒 节流 */
    @Volatile
    private var lastIconPushAtMs: Long = 0L

    /** 等待 ok / 出错时关联的最近推送 package（简单单槽即可） */
    @Volatile
    private var lastIconPushPackage: String = ""

    private val statusListeners = java.util.concurrent.CopyOnWriteArraySet<(String, String) -> Unit>()

    fun clearSessionIconState() {
        sessionIconPushed.clear()
        sessionIconFailed.clear()
        lastIconPushPackage = ""
        lastIconPushAtMs = 0L
    }

    fun markAppIconPushed(packageName: String, iconHash: String) {
        sessionIconPushed[packageName] = iconHash
        Log.i("MeoCompanion", "app_icon_ok pkg=$packageName hash=$iconHash")
    }

    fun noteAppIconError(message: String) {
        val lower = message.lowercase()
        if (!lower.contains("app_icon") &&
            !lower.contains("png") &&
            !lower.contains("decode") &&
            !lower.contains("icon")
        ) {
            return
        }
        val pkg = lastIconPushPackage
        if (pkg.isNotBlank()) {
            sessionIconFailed.add(pkg)
            Log.w("MeoCompanion", "app_icon failed for session pkg=$pkg msg=$message")
        }
    }

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

    /** 将 URL 发到已配对的 Mac，在 Mac 端打开新标签。 */
    fun sendOpenUrl(context: Context, url: String, onResult: (Boolean, String) -> Unit) {
        executor.execute {
            val prefs = PairingPrefs(context.applicationContext)
            val token = prefs.deviceToken
            if (token.isNullOrBlank()) {
                onResult(false, "尚未配对")
                return@execute
            }
            if (!client.isConnected) {
                onResult(false, "未连接 Mac")
                return@execute
            }
            try {
                val json = JSONObject()
                json.put("v", 1)
                json.put("type", "open_url")
                json.put("url", url)
                json.put("ts", System.currentTimeMillis() / 1000L)
                json.put("deviceToken", token)
                client.send(json)
                onResult(true, "已发送到 Mac")
            } catch (e: Exception) {
                Log.e("MeoCompanion", "send open_url failed", e)
                onResult(false, e.message ?: "发送失败")
            }
        }
    }

    @Suppress("UNUSED_PARAMETER")
    fun pushPhoneNotification(
        context: Context,
        payload: PhoneNotificationPayload,
        source: String? = null,
    ) {
        executor.execute {
            pushPhoneNotificationOnWorker(payload, source)
        }
    }

    /**
     * Mac → Android：侧栏微信回复（WR-0）。
     * 在 Companion IO 线程调用；结果回 wechat_reply_ok / wechat_reply_err。
     */
    fun handleWeChatReply(
        requestId: String,
        contact: String,
        text: String,
        notificationId: String?,
        packageName: String,
    ) {
        val svc = service
        val prefs = if (svc != null) PairingPrefs(svc) else null
        val token = prefs?.deviceToken.orEmpty()

        fun sendErr(code: String, message: String) {
            if (requestId.isBlank()) return
            val json = JSONObject().apply {
                put("v", 1)
                put("type", "wechat_reply_err")
                if (token.isNotBlank()) put("deviceToken", token)
                put("requestId", requestId)
                put("code", code)
                put("message", message)
            }
            try {
                if (client.isConnected) client.send(json)
            } catch (e: Exception) {
                Log.e("MeoCompanion", "send wechat_reply_err failed", e)
            }
            lastSmsEvent = "微信回复失败：$message"
            notifyStatus()
        }

        if (svc == null) {
            sendErr("invalid", "服务未就绪")
            return
        }
        if (token.isBlank()) {
            sendErr("invalid", "尚未配对")
            return
        }
        if (requestId.isBlank()) {
            sendErr("invalid", "缺少 requestId")
            return
        }
        if (!client.isConnected) {
            sendErr("invalid", "未连接到 Mac")
            return
        }

        lastSmsEvent = "正在回复微信 · ${contact.trim().take(16)}"
        notifyStatus()

        val result = WeChatReplyExecutor.tryExecute(
            svc,
            WeChatReplyExecutor.Request(
                requestId = requestId,
                contact = contact,
                text = text,
                notificationId = notificationId,
                packageName = packageName,
            ),
        )
        when (result) {
            is WeChatReplyExecutor.Result.Ok -> {
                val json = JSONObject().apply {
                    put("v", 1)
                    put("type", "wechat_reply_ok")
                    put("deviceToken", token)
                    put("requestId", requestId)
                    put("contact", contact.trim())
                    put("elapsedMs", result.elapsedMs)
                    if (!notificationId.isNullOrBlank()) {
                        put("notificationId", notificationId)
                    }
                }
                try {
                    client.send(json)
                    lastSmsEvent = "微信回复已发送 · ${contact.trim().take(16)}"
                    notifyStatus()
                    Log.i(
                        "MeoCompanion",
                        "wechat_reply_ok contactLen=${contact.length} elapsedMs=${result.elapsedMs}",
                    )
                } catch (e: Exception) {
                    Log.e("MeoCompanion", "send wechat_reply_ok failed", e)
                    lastSmsEvent = "微信回复成功但回执失败"
                    notifyStatus()
                }
            }
            is WeChatReplyExecutor.Result.Err -> {
                sendErr(result.code, result.message)
                Log.w("MeoCompanion", "wechat_reply_err code=${result.code} msg=${result.message}")
            }
        }
    }

    @Suppress("UNUSED_PARAMETER")
    fun pushCallEvent(context: Context, payload: CallEventPayload) {
        executor.execute {
            pushCallEventOnWorker(payload)
        }
    }

    private fun pushCallEventOnWorker(payload: CallEventPayload) {
        val svc = service
        val prefs = if (svc != null) {
            PairingPrefs(svc)
        } else {
            noteMirrorSkip("服务未就绪，已跳过来电提醒")
            return
        }
        val token = prefs.deviceToken
        if (token.isNullOrBlank()) {
            noteMirrorSkip("尚未配对，已跳过来电提醒")
            return
        }
        if (!client.isConnected) {
            statusText = "连接已断，正在重连…"
            notifyStatus()
            try {
                val host = prefs.lastHost
                val port = prefs.lastPort
                if (host.isNullOrBlank() || port <= 0) {
                    noteMirrorSkip("未连接，已跳过来电提醒")
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
                Log.e("MeoCompanion", "auto-reconnect for call_event failed", e)
                noteMirrorSkip("重连失败，已跳过来电提醒")
                return
            }
        }
        if (!client.isConnected) {
            noteMirrorSkip("未连接，已跳过来电提醒")
            return
        }
        try {
            client.send(payload.toJson(token))
            val suffix = payload.numberRaw.takeLast(4).ifBlank { "****" }
            lastSmsEvent = "已推送来电 · …$suffix · ${payload.state}"
            notifyStatus()
            Log.i(
                "MeoCompanion",
                "call_event pushed state=${payload.state} idLen=${payload.id.length} numberLen=${payload.number.length}"
            )
        } catch (e: Exception) {
            Log.e("MeoCompanion", "send call_event failed", e)
            statusText = "来电提醒失败：${e.message}"
            notifyStatus()
        }
    }

    private fun pushPhoneNotificationOnWorker(
        payload: PhoneNotificationPayload,
        source: String? = null,
    ): Boolean {
        val svc = service
        val prefs = if (svc != null) {
            PairingPrefs(svc)
        } else {
            noteMirrorSkip("服务未就绪，已跳过通知镜像")
            return false
        }
        val token = prefs.deviceToken
        if (token.isNullOrBlank()) {
            noteMirrorSkip("尚未配对，已跳过通知镜像")
            return false
        }
        if (!client.isConnected) {
            statusText = "连接已断，正在重连…"
            notifyStatus()
            try {
                val host = prefs.lastHost
                val port = prefs.lastPort
                if (host.isNullOrBlank() || port <= 0) {
                    noteMirrorSkip("未连接，已跳过通知镜像")
                    return false
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
                Log.e("MeoCompanion", "auto-reconnect for mirror failed", e)
                noteMirrorSkip("重连失败，已跳过通知镜像")
                return false
            }
        }
        if (!client.isConnected) {
            noteMirrorSkip("未连接，已跳过通知镜像")
            return false
        }
        return try {
            ensureAppIconPushedOnWorker(svc, payload.packageName, prefs)
            client.send(payload.toJson(token, source))
            lastSmsEvent = "已镜像通知 · ${payload.appLabel.ifBlank { payload.packageName }}"
            if (!statusText.contains("连接保持中")) {
                statusText = statusText
                    .substringBefore("（")
                    .trim()
                    .ifEmpty { "已配对" } + "（连接保持中）"
            }
            notifyStatus()
            Log.i(
                "MeoCompanion",
                "phone_notification pushed pkg=${payload.packageName} label=${payload.appLabel} " +
                    "idLen=${payload.id.length} bodyLen=${payload.body.length} " +
                    "inlineIcon=${payload.inlineIconPng != null} source=${source ?: "live"}"
            )
            true
        } catch (e: Exception) {
            Log.e("MeoCompanion", "send phone_notification failed", e)
            statusText = "通知镜像失败：${e.message}"
            notifyStatus()
            false
        }
    }

    /**
     * Mac 侧栏「同步通知」：扫描手机通知栏当前仍可见条目并补推。
     * 已划掉的历史通知系统无法取回。
     */
    fun performPhoneNotificationPull(requestId: String) {
        val reply = JSONObject()
        reply.put("v", 1)
        reply.put("type", "phone_notification_pull_ok")
        if (requestId.isNotBlank()) {
            reply.put("requestId", requestId)
        }
        val ctx = service?.applicationContext
        if (ctx == null) {
            reply.put("pushed", 0)
            reply.put("error", "service_unavailable")
            trySendPullReply(reply)
            return
        }
        try {
            val scan = OtpNotificationListener.collectActiveForMacPull(ctx)
            reply.put("mode", scan.mode)
            if (scan.error != null) {
                reply.put("error", scan.error)
                reply.put("pushed", 0)
            } else {
                var pushed = 0
                for ((index, payload) in scan.payloads.withIndex()) {
                    if (pushPhoneNotificationOnWorker(payload, source = "pull")) {
                        pushed++
                    }
                    if (index > 0 && index % 5 == 0) {
                        Thread.sleep(120)
                    }
                }
                if (scan.otpRescanHits > 0) {
                    pushed += scan.otpRescanHits
                }
                reply.put("pushed", pushed)
                lastSmsEvent = "已补同步通知 $pushed 条"
                notifyStatus()
            }
        } catch (e: Exception) {
            Log.e("MeoCompanion", "phone_notification_pull failed", e)
            reply.put("pushed", 0)
            reply.put("error", e.message ?: "pull_failed")
        }
        trySendPullReply(reply)
    }

    private fun trySendPullReply(reply: JSONObject) {
        try {
            if (client.isConnected) {
                client.send(reply)
            }
        } catch (e: Exception) {
            Log.e("MeoCompanion", "send phone_notification_pull_ok failed", e)
        }
    }

    /**
     * 当前会话内某 package 首次镜像通知前推送小图标。
     * 未连接 / 已推过 / 已失败 / 节流中 → 跳过，不影响通知发送。
     */
    private fun ensureAppIconPushedOnWorker(
        svc: CompanionConnectionService?,
        packageName: String,
        prefs: PairingPrefs
    ) {
        if (svc == null) return
        if (packageName.isBlank() || packageName == "otp") return
        if (!client.isConnected) return
        if (sessionIconPushed.containsKey(packageName)) return
        if (sessionIconFailed.contains(packageName)) return

        val token = prefs.deviceToken
        if (token.isNullOrBlank()) return

        val now = System.currentTimeMillis()
        val elapsed = now - lastIconPushAtMs
        if (elapsed in 0 until 500L) {
            try {
                Thread.sleep(500L - elapsed)
            } catch (_: InterruptedException) {
            }
        }

        val exported = AppIconExporter.export(svc, packageName)
        if (exported == null) {
            sessionIconFailed.add(packageName)
            Log.w("MeoCompanion", "app_icon export skipped pkg=$packageName")
            return
        }

        try {
            lastIconPushPackage = packageName
            val json = JSONObject()
            json.put("v", 1)
            json.put("type", "app_icon")
            json.put("deviceToken", token)
            json.put("packageName", packageName)
            json.put("appLabel", exported.appLabel)
            json.put("iconHash", exported.iconHash)
            json.put("mime", "image/png")
            json.put("width", exported.width)
            json.put("height", exported.height)
            json.put("pngBase64", AppIconExporter.toBase64(exported.pngBytes))
            json.put("ts", System.currentTimeMillis() / 1000L)
            client.send(json)
            lastIconPushAtMs = System.currentTimeMillis()
            // 乐观写入：即使 ok 稍后到，同会话也不重复发
            sessionIconPushed[packageName] = exported.iconHash
            Log.i(
                "MeoCompanion",
                "app_icon pushed pkg=$packageName hash=${exported.iconHash} bytes=${exported.pngBytes.size} size=${exported.width}"
            )
        } catch (e: Exception) {
            sessionIconFailed.add(packageName)
            Log.e("MeoCompanion", "send app_icon failed pkg=$packageName", e)
        }
    }

    @Volatile
    private var lastMirrorSkipAt: Long = 0L

    private fun noteMirrorSkip(message: String) {
        val now = System.currentTimeMillis()
        if (now - lastMirrorSkipAt < 8_000L) {
            Log.i("MeoCompanion", "mirror skip (throttled): $message")
            return
        }
        lastMirrorSkipAt = now
        noteSmsEvent(message)
    }
}
