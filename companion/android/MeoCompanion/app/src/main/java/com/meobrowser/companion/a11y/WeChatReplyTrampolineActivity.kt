package com.meobrowser.companion.a11y

import android.app.PendingIntent
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.appcompat.app.AppCompatActivity

/**
 * 透明中转页：在获得前台瞬间再转发微信 contentIntent / LAUNCHER，绕过部分后台限制。
 */
class WeChatReplyTrampolineActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val contact = intent?.getStringExtra(EXTRA_CONTACT).orEmpty()
        val pi = if (Build.VERSION.SDK_INT >= 33) {
            intent?.getParcelableExtra(EXTRA_CONTENT_INTENT, PendingIntent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_CONTENT_INTENT) as? PendingIntent
        }
        Log.i(TAG, "trampoline contactLen=${contact.length} hasPi=${pi != null}")
        var ok = false
        if (pi != null) {
            ok = WeChatReplyLaunchHelper.sendPendingIntent(pi)
        }
        if (!ok) {
            ok = WeChatReplyLaunchHelper.launchWeChatPackage(this)
        }
        Log.i(TAG, "trampoline done ok=$ok")
        finish()
        overridePendingTransition(0, 0)
    }

    companion object {
        private const val TAG = "WeChatReplyTrampoline"
        const val EXTRA_CONTACT = "contact"
        const val EXTRA_CONTENT_INTENT = "content_intent"
    }
}
