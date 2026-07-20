package com.meobrowser.companion.browser

import android.net.Uri
import java.util.Locale

object UrlNavigator {
    private val SEARCH = "https://www.google.com/search?q="

    fun normalize(input: String): String {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return "about:blank"
        if (trimmed.equals("about:blank", true) || trimmed.equals("about:newtab", true)) {
            return trimmed.lowercase(Locale.US)
        }
        val hasScheme = trimmed.contains("://")
        if (hasScheme) return trimmed
        val looksLikeHost = trimmed.contains('.') && !trimmed.contains(' ')
        return if (looksLikeHost) {
            "https://$trimmed"
        } else {
            SEARCH + Uri.encode(trimmed)
        }
    }

    fun isNewTabUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return true
        val u = url.lowercase(Locale.US)
        return u == "about:newtab" || u == "about:blank"
    }
}
