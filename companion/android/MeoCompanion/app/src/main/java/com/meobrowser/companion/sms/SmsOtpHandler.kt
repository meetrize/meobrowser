package com.meobrowser.companion.sms

import android.content.Context
import android.util.Log
import com.meobrowser.companion.channel.CompanionSession

/**
 * 统一处理「收到短信 → 解析 → 更新最近推码 → 推送到 Mac」。
 */
object SmsOtpHandler {
    private const val TAG = "SmsOtpHandler"
    @Volatile
    private var lastHandledKey: String = ""
    @Volatile
    private var lastHandledAt: Long = 0L

    fun onIncomingSms(
        context: Context,
        address: String,
        body: String,
        source: String,
        force: Boolean = false,
    ) {
        if (body.isBlank()) {
            CompanionSession.noteSmsEvent("收到空短信（$source）")
            return
        }

        val key = "${address}|${body.hashCode()}"
        val now = System.currentTimeMillis()
        if (!force && key == lastHandledKey && now - lastHandledAt < 2000L) {
            Log.i(TAG, "skip duplicate from $source")
            return
        }

        CompanionSession.noteSmsEvent("收到短信@$source ${address.ifBlank { "?" }} len=${body.length}")

        val code = OtpParser.extractStrict(body)
            ?: if (OtpParser.looksLikeOtpSms(body) || body.contains("深度求索") || address.contains("106866")) {
                OtpParser.extract(body)
            } else {
                null
            }
            ?: Regex("""验证码\s*[:：]?\s*([0-9]{4,8})""")
                .find(OtpParser.normalize(body))
                ?.groupValues?.getOrNull(1)

        if (code.isNullOrBlank()) {
            val preview = OtpParser.normalize(body).replace('\n', ' ').let {
                if (it.length > 36) it.take(36) + "…" else it
            }
            CompanionSession.noteSmsEvent("已收到但未识别验证码：$preview")
            Log.i(TAG, "no otp in body from $source preview=$preview")
            return
        }

        lastHandledKey = key
        lastHandledAt = now
        CompanionSession.markOtpDetected(code, source)
        CompanionSession.pushOtp(context.applicationContext, code)
        Log.i(TAG, "otp=$code via $source force=$force")
    }
}
