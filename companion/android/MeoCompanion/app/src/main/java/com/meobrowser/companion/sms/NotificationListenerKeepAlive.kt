package com.meobrowser.companion.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * 小米等国产 ROM 常在进程被杀 / 重装后保持「通知使用权已开」，但服务实际未绑定。
 * 在开机、覆盖安装、前台服务保活时主动 [OtpNotificationListener.ensureBound]。
 */
object NotificationListenerKeepAlive {
    private const val TAG = "NotifListenKeepAlive"
    private const val PULSE_MS = 30_000L

    private val main = Handler(Looper.getMainLooper())
    private var pulsing = false
    private var appContext: Context? = null

    fun tick(context: Context) {
        val app = context.applicationContext
        appContext = app
        if (!OtpNotificationListener.isEnabled(app)) {
            Log.d(TAG, "skip tick: listener not enabled in settings")
            return
        }
        if (OtpNotificationListener.isConnected()) {
            return
        }
        Log.i(TAG, "listener enabled but unbound → requestRebind")
        OtpNotificationListener.ensureBound(app)
    }

    /** 连接 Mac 期间周期性重绑，避免 MIUI 静默断开后需用户手动开关。 */
    fun startPulsing(context: Context) {
        appContext = context.applicationContext
        if (pulsing) {
            tick(context)
            return
        }
        pulsing = true
        main.removeCallbacks(pulseJob)
        main.post(pulseJob)
    }

    fun stopPulsing() {
        pulsing = false
        main.removeCallbacks(pulseJob)
    }

    private val pulseJob = object : Runnable {
        override fun run() {
            if (!pulsing) return
            val ctx = appContext
            if (ctx != null) {
                tick(ctx)
            }
            main.postDelayed(this, PULSE_MS)
        }
    }
}

/** 开机 / 覆盖安装后尝试重绑通知监听（权限仍在时）。 */
class NotificationListenerRebindReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action.orEmpty()
        Log.i("NotifListenKeepAlive", "rebind receiver action=$action")
        NotificationListenerKeepAlive.tick(context)
    }
}
