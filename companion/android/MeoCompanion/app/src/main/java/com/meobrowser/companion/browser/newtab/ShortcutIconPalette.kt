package com.meobrowser.companion.browser.newtab

import android.graphics.Color
import android.net.Uri

/** 与 Mac BrowserShortcutIconPalette 对齐的 16 色固定色板。 */
object ShortcutIconPalette {
    const val COLOR_COUNT = 16
    const val STYLE_AUTO = "auto"
    const val STYLE_LETTER = "letter"

    fun clampedIndex(index: Int): Int {
        if (index < 0 || index >= COLOR_COUNT) return 0
        return index
    }

    fun colorAtIndex(index: Int): Int {
        val i = clampedIndex(index)
        val hue = i * (360f / COLOR_COUNT)
        return Color.HSVToColor(floatArrayOf(hue, 0.45f, 0.85f))
    }

    fun defaultIndexForUrl(url: String): Int {
        if (url.isBlank()) return 0
        return kotlin.math.abs(url.hashCode()) % COLOR_COUNT
    }

    fun normalizedLetter(raw: String?): String {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return ""
        val cp = trimmed.codePointAt(0)
        return String(Character.toChars(cp))
    }

    fun defaultLetter(title: String, url: String): String {
        val fromTitle = normalizedLetter(title)
        if (fromTitle.isNotEmpty()) {
            return fromTitle.uppercase()
        }
        val host = try {
            val h = (Uri.parse(url).host ?: "?").removePrefix("www.")
            h.ifBlank { "?" }
        } catch (_: Exception) {
            "?"
        }
        val fromHost = normalizedLetter(host)
        return if (fromHost.isNotEmpty()) fromHost.uppercase() else "?"
    }

    fun displayLetter(item: ShortcutItem): String {
        if (item.usesCustomLetterIcon && item.iconLetter.isNotBlank()) {
            return item.iconLetter
        }
        return defaultLetter(item.title, item.url)
    }

    fun displayColor(item: ShortcutItem): Int {
        if (item.usesCustomLetterIcon) {
            return colorAtIndex(item.iconColorIndex)
        }
        return ShortcutIconHelper.colorFor(item.url, item.title)
    }
}
