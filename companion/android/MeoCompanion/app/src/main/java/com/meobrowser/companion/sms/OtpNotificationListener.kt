package com.meobrowser.companion.sms

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import com.meobrowser.companion.a11y.WeChatReplyIntentCache
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.pairing.NotificationMirrorMode
import com.meobrowser.companion.pairing.PairingPrefs

/**
 * 通知使用权监听：
 * - 仅验证码：筛 OTP 相关通知并推码（小米服务号等）
 * - 全部通知：过滤噪音后镜像到 Mac，若像验证码再推 otp
 *
 * 注意：设置里「已开启」≠ 服务已连接。重装 App 后常需 requestRebind。
 */
class OtpNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        instance = this
        Log.i(TAG, "notification listener connected")
        CompanionSession.noteSmsEvent("通知监听已连接")
        val pending = pendingRescan
        pendingRescan = false
        if (pending) {
            Handler(Looper.getMainLooper()).post {
                val hits = scanActiveNotifications(force = true)
                Log.i(TAG, "pending rescan hits=$hits")
                CompanionSession.noteSmsEvent(
                    when {
                        hits > 0 -> "重连后已从通知读取并推送"
                        hits == 0 -> "重连成功，但通知栏没有验证码"
                        else -> "重连后扫描失败"
                    }
                )
            }
        }
    }

    override fun onListenerDisconnected() {
        Log.w(TAG, "notification listener disconnected")
        if (instance === this) instance = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestRebind(ComponentName(this, OtpNotificationListener::class.java))
            }
        } catch (e: Exception) {
            Log.w(TAG, "requestRebind on disconnect failed", e)
        }
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        handleSbn(sbn, force = false)
    }

    /** 手动扫描当前通知栏，返回命中并推送的条数（验证码兴趣） */
    fun scanActiveNotifications(force: Boolean = true): Int {
        val list = try {
            activeNotifications ?: emptyArray()
        } catch (e: Exception) {
            Log.e(TAG, "activeNotifications failed", e)
            return -1
        }
        var hits = 0
        val sorted = list.sortedByDescending { it.postTime }
        for (sbn in sorted) {
            if (handleSbn(sbn, force = force, otpScanOnly = true)) {
                hits++
                if (force) break
            }
        }
        return hits
    }

    /**
     * Mac 侧栏补拉：收集当前通知栏可镜像载荷（不直接发送）。
     * 仅验证码模式则现场推 otp，返回 hits。
     */
    fun collectActiveForMacPullLocal(): MacPullScanResult {
        val mode = PairingPrefs(applicationContext).notificationMirrorMode
        val modeName = when (mode) {
            NotificationMirrorMode.ALL -> "all"
            else -> "otp_only"
        }
        val list = try {
            activeNotifications ?: emptyArray()
        } catch (e: Exception) {
            Log.e(TAG, "activeNotifications failed", e)
            return MacPullScanResult(emptyList(), 0, modeName, "scan_failed")
        }
        val sorted = list.sortedByDescending { it.postTime }
        if (mode != NotificationMirrorMode.ALL) {
            var otpHits = 0
            for (sbn in sorted) {
                if (handleSbn(sbn, force = true, otpScanOnly = true)) {
                    otpHits++
                }
            }
            return MacPullScanResult(emptyList(), otpHits, modeName, null)
        }

        val payloads = ArrayList<PhoneNotificationPayload>()
        val seenIds = HashSet<String>()
        for (sbn in sorted) {
            if (sbn.packageName == packageName) continue
            if (NotificationNoiseFilter.shouldSkip(sbn, packageName)) continue
            val payload = NotificationPayloadBuilder.build(applicationContext, sbn) ?: continue
            WeChatReplyIntentCache.remember(sbn, payload.title)
            if (!seenIds.add(payload.id)) continue
            NotificationMirrorGate.forceAdmit(payload.id)
            payloads.add(payload)
        }
        return MacPullScanResult(payloads, 0, modeName, null)
    }

    /**
     * @param otpScanOnly 手动「重新读取」时只走验证码路径，不刷全部镜像
     * @return 是否作为验证码候选处理成功（镜像推送不计入）
     */
    private fun handleSbn(
        sbn: StatusBarNotification,
        force: Boolean,
        otpScanOnly: Boolean = false,
    ): Boolean {
        if (sbn.packageName == packageName) return false

        // 缓存微信通知 contentIntent，供 Mac 侧栏回复打开对应会话
        run {
            val title = sbn.notification?.extras
                ?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            WeChatReplyIntentCache.remember(sbn, title)
        }

        val mode = PairingPrefs(applicationContext).notificationMirrorMode
        val mirrorAll = !otpScanOnly && mode == NotificationMirrorMode.ALL

        if (mirrorAll) {
            if (NotificationNoiseFilter.shouldSkip(sbn, packageName)) {
                return false
            }
            val payload = NotificationPayloadBuilder.build(applicationContext, sbn)
            if (payload != null) {
                WeChatReplyIntentCache.remember(sbn, payload.title)
                if (NotificationMirrorGate.tryAdmit(payload.id)) {
                    CompanionSession.pushPhoneNotification(applicationContext, payload)
                } else {
                    Log.i(TAG, "mirror gated id=${payload.id}")
                }
            }
            // 全部模式：仍尝试 OTP
            val body = combinedBody(sbn)
            if (body.isNotBlank() && looksInterestingForOtp(body)) {
                Log.i(TAG, "notif otp candidate pkg=${sbn.packageName} len=${body.length} force=$force")
                SmsOtpHandler.onIncomingSms(
                    applicationContext,
                    address = sbn.packageName,
                    body = body,
                    source = if (force) "notification-rescan" else "notification",
                    force = force
                )
                return true
            }
            return false
        }

        // 仅验证码
        val body = combinedBody(sbn)
        if (body.isBlank()) return false
        if (!looksInterestingForOtp(body)) return false

        Log.i(TAG, "notif otp candidate pkg=${sbn.packageName} len=${body.length} force=$force")
        SmsOtpHandler.onIncomingSms(
            applicationContext,
            address = sbn.packageName,
            body = body,
            source = if (force) "notification-rescan" else "notification",
            force = force
        )
        return true
    }

    private fun combinedBody(sbn: StatusBarNotification): String {
        val n = sbn.notification ?: return ""
        val extras = n.extras ?: return ""
        val title = extras.charSeq(Notification.EXTRA_TITLE)
        val text = extras.charSeq(Notification.EXTRA_TEXT)
        val big = extras.charSeq(Notification.EXTRA_BIG_TEXT)
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n") { it?.toString().orEmpty() }
            .orEmpty()
        val sub = extras.charSeq(Notification.EXTRA_SUB_TEXT)
        return listOf(title, text, big, lines, sub)
            .filter { it.isNotBlank() }
            .joinToString("\n")
    }

    private fun looksInterestingForOtp(body: String): Boolean {
        return OtpParser.looksLikeOtpSms(body) ||
            body.contains("深度求索") ||
            body.contains("验证码") ||
            body.contains("驗證碼") ||
            body.contains("106866")
    }

    private fun android.os.Bundle.charSeq(key: String): String {
        return getCharSequence(key)?.toString().orEmpty()
    }

    companion object {
        private const val TAG = "OtpNotifListen"

        @Volatile
        private var instance: OtpNotificationListener? = null

        @Volatile
        private var pendingRescan: Boolean = false

        fun isConnected(): Boolean = instance != null

        /** 回复前刷新：从通知栏现存微信通知补齐 contentIntent 缓存。 */
        fun refreshWeChatReplyIntentCache(): Int {
            val listener = instance ?: return -1
            val list = try {
                listener.activeNotifications ?: emptyArray()
            } catch (e: Exception) {
                Log.e(TAG, "refreshWeChatReplyIntentCache failed", e)
                return -1
            }
            var n = 0
            for (sbn in list) {
                val pkg = sbn.packageName.orEmpty()
                if (pkg != "com.tencent.mm" && !pkg.contains("tencent.mm")) continue
                val title = sbn.notification?.extras
                    ?.getCharSequence(Notification.EXTRA_TITLE)?.toString()
                WeChatReplyIntentCache.remember(sbn, title)
                n++
            }
            Log.i(TAG, "refreshWeChatReplyIntentCache count=$n cacheSize=${WeChatReplyIntentCache.size()}")
            return n
        }

        fun isEnabled(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            val cn = ComponentName(context, OtpNotificationListener::class.java)
            val expected = cn.flattenToString()
            val expectedShort = "${context.packageName}/${OtpNotificationListener::class.java.canonicalName}"
            if (flat.split(':').any { it.equals(expected, true) || it.equals(expectedShort, true) }) {
                return true
            }
            return flat.contains(context.packageName) &&
                (flat.contains("OtpNotificationListener") || flat.contains(cn.className))
        }

        fun componentName(context: Context): ComponentName {
            return ComponentName(context, OtpNotificationListener::class.java)
        }

        fun ensureBound(context: Context) {
            if (instance != null) return
            if (!isEnabled(context)) return
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    requestRebind(componentName(context))
                    Log.i(TAG, "requestRebind issued")
                    CompanionSession.noteSmsEvent("正在连接通知监听…")
                }
            } catch (e: Exception) {
                Log.w(TAG, "ensureBound failed", e)
            }
        }

        fun openSettings(context: Context) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    context.startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } else {
                    context.startActivity(
                        Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "open settings failed", e)
                try {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:${context.packageName}")
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (_: Exception) {
                }
            }
        }

        fun enabledDetail(context: Context): String {
            return when {
                !isEnabled(context) ->
                    "未开启 — 小米服务号短信必须开此项才能自动收码"
                isConnected() ->
                    "已开启且已连接，可从通知栏抓取验证码"
                else ->
                    "设置已开，但监听服务未连接（重装后常见）。点「重新读取」会尝试重连；仍不行请开关一次通知使用权。"
            }
        }

        data class MacPullScanResult(
            val payloads: List<PhoneNotificationPayload>,
            val otpRescanHits: Int,
            val mode: String,
            val error: String?,
        )

        /**
         * Mac 主动补拉用：收集通知栏当前仍可见、可镜像的条目。
         * 断线期间已划掉的通知无法恢复。
         */
        fun collectActiveForMacPull(context: Context): MacPullScanResult {
            if (!isEnabled(context)) {
                return MacPullScanResult(emptyList(), 0, "unknown", "listener_disabled")
            }
            val svc = instance
            if (svc == null) {
                pendingRescan = false
                ensureBound(context)
                return MacPullScanResult(emptyList(), 0, "unknown", "listener_disconnected")
            }
            return try {
                svc.collectActiveForMacPullLocal()
            } catch (e: Exception) {
                Log.e(TAG, "collectActiveForMacPull failed", e)
                MacPullScanResult(emptyList(), 0, "unknown", "scan_failed")
            }
        }

        /**
         * @return
         *  >0 命中并推送
         *   0 通知栏没有可识别验证码
         *  -1 未开启通知使用权
         *  -2 服务未连接，已请求重绑并排队扫描（稍等）
         *  -3 扫描异常
         */
        fun rescanAndPush(context: Context): Int {
            if (!isEnabled(context)) {
                CompanionSession.noteSmsEvent("未开启通知使用权")
                return -1
            }
            val svc = instance
            if (svc != null) {
                return try {
                    svc.scanActiveNotifications(force = true)
                } catch (e: Exception) {
                    Log.e(TAG, "scan failed", e)
                    -3
                }
            }
            pendingRescan = true
            ensureBound(context)
            CompanionSession.noteSmsEvent("通知服务未连接，已请求重连并排队扫描…")
            return -2
        }

        fun rescanAndPushWithRetry(
            context: Context,
            attempts: Int = 8,
            intervalMs: Long = 400L,
            onResult: (hits: Int) -> Unit,
        ) {
            val app = context.applicationContext
            val main = Handler(Looper.getMainLooper())

            fun tryOnce(left: Int) {
                val hits = rescanAndPush(app)
                if (hits >= 0) {
                    onResult(hits)
                    return
                }
                if (hits == -1) {
                    onResult(-1)
                    return
                }
                if (left <= 0) {
                    onResult(hits)
                    return
                }
                ensureBound(app)
                main.postDelayed({ tryOnce(left - 1) }, intervalMs)
            }
            tryOnce(attempts)
        }
    }
}
