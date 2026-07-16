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
import com.meobrowser.companion.channel.CompanionSession

/**
 * 小米等机型上，服务号/智能短信往往不进 content://sms、也不投递 SMS_RECEIVED，
 * 但会在通知栏展示全文。通过通知使用权抓取验证码。
 *
 * 注意：设置里「已开启」≠ 服务已连接。重装 App 后常需 requestRebind，
 * 或用户开关一次通知使用权。
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
        // 系统断开后主动请求重绑（小米重装/杀进程后很常见）
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

    /** 手动扫描当前通知栏，返回命中并推送的条数 */
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
            if (handleSbn(sbn, force = force)) {
                hits++
                if (force) break
            }
        }
        return hits
    }

    private fun handleSbn(sbn: StatusBarNotification, force: Boolean): Boolean {
        if (sbn.packageName == packageName) return false
        val n = sbn.notification ?: return false
        val extras = n.extras ?: return false
        val title = extras.charSeq(Notification.EXTRA_TITLE)
        val text = extras.charSeq(Notification.EXTRA_TEXT)
        val big = extras.charSeq(Notification.EXTRA_BIG_TEXT)
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n") { it?.toString().orEmpty() }
            .orEmpty()
        val sub = extras.charSeq(Notification.EXTRA_SUB_TEXT)
        val body = listOf(title, text, big, lines, sub)
            .filter { it.isNotBlank() }
            .joinToString("\n")
        if (body.isBlank()) return false

        val interesting =
            OtpParser.looksLikeOtpSms(body) ||
                body.contains("深度求索") ||
                body.contains("验证码") ||
                body.contains("驗證碼") ||
                body.contains("106866")
        if (!interesting) return false

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

        /** 设置已开但服务未连时，请求系统重新绑定 */
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
            // 设置开着但服务没连上：排队 + 重绑
            pendingRescan = true
            ensureBound(context)
            CompanionSession.noteSmsEvent("通知服务未连接，已请求重连并排队扫描…")
            return -2
        }

        /**
         * 带重试的扫描：若正在重连，轮询等待连接后再扫。
         * [onResult] 在主线程回调。
         */
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
                // -2 / -3：再等等
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
