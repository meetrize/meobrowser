package com.meobrowser.companion.browser

import android.content.Context
import com.meobrowser.companion.browser.tab.TabManager
import org.json.JSONArray
import org.json.JSONObject

class BrowserPrefs(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    var lowMemoryMode: Boolean
        get() = prefs.getBoolean(KEY_LOW_MEM, false)
        set(value) = prefs.edit().putBoolean(KEY_LOW_MEM, value).apply()

    var maxTabs: Int
        get() = prefs.getInt(KEY_MAX_TABS, TabManager.DEFAULT_MAX).coerceIn(2, TabManager.HARD_MAX)
        set(value) = prefs.edit().putInt(KEY_MAX_TABS, value.coerceIn(2, TabManager.HARD_MAX)).apply()

    var desktopUa: Boolean
        get() = prefs.getBoolean(KEY_DESKTOP_UA, false)
        set(value) = prefs.edit().putBoolean(KEY_DESKTOP_UA, value).apply()

    /** 沉浸式全屏（隐藏系统栏） */
    var fullscreen: Boolean
        get() = prefs.getBoolean(KEY_FULLSCREEN, false)
        set(value) = prefs.edit().putBoolean(KEY_FULLSCREEN, value).apply()

    /**
     * 0 = 跟随系统（SENSOR）
     * 1 = 锁定竖屏
     * 2 = 锁定横屏
     */
    var orientationMode: Int
        get() = prefs.getInt(KEY_ORIENTATION, 0).coerceIn(0, 2)
        set(value) = prefs.edit().putInt(KEY_ORIENTATION, value.coerceIn(0, 2)).apply()

    /** WebSettings.textZoom：85 / 100 / 125 / 150 */
    var textZoom: Int
        get() {
            val v = prefs.getInt(KEY_TEXT_ZOOM, 100)
            return if (v in TEXT_ZOOM_STEPS) v else 100
        }
        set(value) {
            val next = TEXT_ZOOM_STEPS.minByOrNull { kotlin.math.abs(it - value) } ?: 100
            prefs.edit().putInt(KEY_TEXT_ZOOM, next).apply()
        }

    fun cycleTextZoom(): Int {
        val idx = TEXT_ZOOM_STEPS.indexOf(textZoom).let { if (it < 0) 1 else it }
        val next = TEXT_ZOOM_STEPS[(idx + 1) % TEXT_ZOOM_STEPS.size]
        textZoom = next
        return next
    }

    fun cycleOrientationMode(): Int {
        val next = (orientationMode + 1) % 3
        orientationMode = next
        return next
    }

    fun saveSession(entries: List<Pair<String, String>>, activeIndex: Int) {
        val arr = JSONArray()
        entries.forEach { (url, title) ->
            arr.put(JSONObject().put("url", url).put("title", title))
        }
        prefs.edit()
            .putString(KEY_SESSION, arr.toString())
            .putInt(KEY_ACTIVE, activeIndex)
            .apply()
    }

    fun loadSession(): Pair<List<Pair<String, String>>, Int> {
        val raw = prefs.getString(KEY_SESSION, null) ?: return emptyList<Pair<String, String>>() to 0
        return try {
            val arr = JSONArray(raw)
            val list = (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                o.optString("url") to o.optString("title")
            }
            list to prefs.getInt(KEY_ACTIVE, 0)
        } catch (_: Exception) {
            emptyList<Pair<String, String>>() to 0
        }
    }

    companion object {
        private const val PREFS = "meo_browser"
        private const val KEY_LOW_MEM = "low_memory_mode"
        private const val KEY_MAX_TABS = "max_tabs"
        private const val KEY_DESKTOP_UA = "desktop_ua"
        private const val KEY_FULLSCREEN = "fullscreen"
        private const val KEY_ORIENTATION = "orientation_mode"
        private const val KEY_TEXT_ZOOM = "text_zoom"
        private const val KEY_SESSION = "session_tabs"
        private const val KEY_ACTIVE = "session_active"
        val TEXT_ZOOM_STEPS = listOf(85, 100, 125, 150)
    }
}
