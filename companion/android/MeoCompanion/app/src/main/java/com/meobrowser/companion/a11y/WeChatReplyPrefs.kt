package com.meobrowser.companion.a11y

import android.content.Context

/** 微信侧栏回复实验开关（默认关）。 */
class WeChatReplyPrefs(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("meo_companion", Context.MODE_PRIVATE)

    var wechatReplyEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    companion object {
        private const val KEY_ENABLED = "wechat_reply_enabled"
    }
}
