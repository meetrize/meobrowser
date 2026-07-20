package com.meobrowser.companion.sync

import android.content.Context

class SyncPrefs(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 总开关默认关 */
    var enabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /** 打开总开关后，快捷方式默认勾选 */
    var syncShortcuts: Boolean
        get() = prefs.getBoolean(KEY_SHORTCUTS, true)
        set(value) = prefs.edit().putBoolean(KEY_SHORTCUTS, value).apply()

    var syncHistory: Boolean
        get() = prefs.getBoolean(KEY_HISTORY, false)
        set(value) = prefs.edit().putBoolean(KEY_HISTORY, value).apply()

    var syncBookmarks: Boolean
        get() = prefs.getBoolean(KEY_BOOKMARKS, false)
        set(value) = prefs.edit().putBoolean(KEY_BOOKMARKS, value).apply()

    var lastSyncAt: Long
        get() = prefs.getLong(KEY_LAST_AT, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_AT, value).apply()

    var epoch: Long
        get() = prefs.getLong(KEY_EPOCH, 0L)
        set(value) = prefs.edit().putLong(KEY_EPOCH, value).apply()

    fun bumpEpoch(): Long {
        val next = epoch + 1
        epoch = next
        return next
    }

    companion object {
        private const val PREFS = "meo_sync"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_SHORTCUTS = "sync_shortcuts"
        private const val KEY_HISTORY = "sync_history"
        private const val KEY_BOOKMARKS = "sync_bookmarks"
        private const val KEY_LAST_AT = "last_sync_at"
        private const val KEY_EPOCH = "epoch"
    }
}
