package com.meobrowser.companion.call

import android.content.Context

/** 来电提醒开关（默认关）。 */
class CallAlertPrefs(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("meo_companion", Context.MODE_PRIVATE)

    var callAlertEnabled: Boolean
        get() = prefs.getBoolean(KEY_CALL_ALERT, false)
        set(value) = prefs.edit().putBoolean(KEY_CALL_ALERT, value).apply()

    companion object {
        private const val KEY_CALL_ALERT = "call_alert_enabled"
    }
}
