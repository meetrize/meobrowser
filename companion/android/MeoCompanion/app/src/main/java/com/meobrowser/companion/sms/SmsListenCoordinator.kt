package com.meobrowser.companion.sms

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import androidx.core.content.ContextCompat
import com.meobrowser.companion.channel.CompanionSession

/**
 * 在前台服务 / 主界面存活期间强化短信监听：
 * 1. 动态高优先级注册 SMS_RECEIVED（补静态 Manifest 收不到的机型）
 * 2. 观察 content://sms 变化（广播被拦但短信入库时仍可捞到）
 */
object SmsListenCoordinator {
    private const val TAG = "SmsListen"

    @Volatile
    private var started = false
    private var appContext: Context? = null
    private var dynamicReceiver: BroadcastReceiver? = null
    private var observer: ContentObserver? = null
    private var workerThread: HandlerThread? = null
    private var lastInboxScanAt = 0L

    @Synchronized
    fun start(context: Context) {
        val app = context.applicationContext
        appContext = app
        if (started) return
        started = true

        registerDynamicReceiver(app)
        registerInboxObserver(app)
        CompanionSession.noteSmsEvent("短信监听已启动")
        Log.i(TAG, "started")
    }

    @Synchronized
    fun stop() {
        val app = appContext
        if (app != null) {
            dynamicReceiver?.let {
                try {
                    app.unregisterReceiver(it)
                } catch (_: Exception) {
                }
            }
            observer?.let {
                try {
                    app.contentResolver.unregisterContentObserver(it)
                } catch (_: Exception) {
                }
            }
        }
        dynamicReceiver = null
        observer = null
        workerThread?.quitSafely()
        workerThread = null
        started = false
        appContext = null
        Log.i(TAG, "stopped")
    }

    private fun registerDynamicReceiver(app: Context) {
        if (dynamicReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                SmsOtpReceiver().onReceive(context, intent)
            }
        }
        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        filter.priority = IntentFilter.SYSTEM_HIGH_PRIORITY
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                app.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                app.registerReceiver(receiver, filter)
            }
            dynamicReceiver = receiver
            Log.i(TAG, "dynamic SMS receiver registered")
        } catch (e: Exception) {
            Log.e(TAG, "registerReceiver failed", e)
            CompanionSession.noteSmsEvent("动态广播注册失败：${e.message}")
        }
    }

    private fun registerInboxObserver(app: Context) {
        if (observer != null) return
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.READ_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "skip observer: no READ_SMS")
            return
        }

        val thread = HandlerThread("meo-sms-observer").also { it.start() }
        workerThread = thread
        val handler = Handler(thread.looper)
        val obs = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                onChange(selfChange, null)
            }

            override fun onChange(selfChange: Boolean, uri: Uri?) {
                val now = System.currentTimeMillis()
                if (now - lastInboxScanAt < 800L) return
                lastInboxScanAt = now
                handler.post { scanNewestSms(app) }
            }
        }
        try {
            app.contentResolver.registerContentObserver(
                Uri.parse("content://sms"),
                true,
                obs
            )
            app.contentResolver.registerContentObserver(
                Telephony.Sms.CONTENT_URI,
                true,
                obs
            )
            observer = obs
            Log.i(TAG, "sms content observer registered")
        } catch (e: Exception) {
            Log.e(TAG, "registerContentObserver failed", e)
            CompanionSession.noteSmsEvent("收件箱观察注册失败：${e.message}")
        }
    }

    private fun scanNewestSms(app: Context) {
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.READ_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        try {
            val cursor = app.contentResolver.query(
                Uri.parse("content://sms/inbox"),
                arrayOf("_id", "address", "body", "date"),
                null,
                null,
                "_id DESC"
            ) ?: app.contentResolver.query(
                Uri.parse("content://sms"),
                arrayOf("_id", "address", "body", "date"),
                null,
                null,
                "_id DESC"
            ) ?: return

            cursor.use { c ->
                if (!c.moveToFirst()) return
                val idxAddr = c.getColumnIndex("address")
                val idxBody = c.getColumnIndex("body")
                val idxDate = c.getColumnIndex("date")
                val body = if (idxBody >= 0) c.getString(idxBody) else return
                val address = if (idxAddr >= 0) c.getString(idxAddr).orEmpty() else ""
                val date = if (idxDate >= 0) c.getLong(idxDate) else 0L
                val dateMs = when {
                    date in 1_000_000_000L..9_999_999_999L -> date * 1000L
                    else -> date
                }
                // 只处理近 3 分钟内入库的，避免观察器启动时扫到旧短信
                if (dateMs > 0L && System.currentTimeMillis() - dateMs > 3 * 60 * 1000L) {
                    return
                }
                if (!OtpParser.looksLikeOtpSms(body) &&
                    !body.contains("深度求索") &&
                    !address.contains("106866")
                ) {
                    return
                }
                SmsOtpHandler.onIncomingSms(app, address, body, "inbox-observer")
            }
        } catch (e: Exception) {
            Log.w(TAG, "scanNewestSms", e)
        }
    }

    /** 主线程提示用，可在 Activity 里轮询展示 */
    fun isRunning(): Boolean = started
}
