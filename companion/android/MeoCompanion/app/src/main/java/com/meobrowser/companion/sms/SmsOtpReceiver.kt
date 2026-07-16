package com.meobrowser.companion.sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import com.meobrowser.companion.channel.CompanionSession

/**
 * 系统短信广播。部分国产机对 Manifest 静态注册不投递，需同时靠
 * [SmsListenCoordinator] 的动态注册 + ContentObserver。
 */
class SmsOtpReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val pending = goAsync()
        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            val body = messages.joinToString(separator = "") { it.displayMessageBody ?: "" }
            val address = messages.firstOrNull()?.displayOriginatingAddress.orEmpty()
            Log.i(TAG, "SMS_RECEIVED addr=$address bodyLen=${body.length}")
            SmsOtpHandler.onIncomingSms(
                context.applicationContext,
                address = address,
                body = body,
                source = "broadcast"
            )
        } catch (e: Exception) {
            Log.e(TAG, "onReceive failed", e)
            CompanionSession.noteSmsEvent("短信广播异常：${e.message}")
        } finally {
            pending.finish()
        }
    }

    companion object {
        private const val TAG = "MeoSmsOtp"
    }
}
