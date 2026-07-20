package com.meobrowser.companion.browser.tab

import android.webkit.WebView
import com.meobrowser.companion.browser.UrlNavigator
import java.util.UUID

data class BrowserTab(
    val id: String = UUID.randomUUID().toString(),
    var title: String = "新标签页",
    var url: String = "about:newtab",
    var isLoading: Boolean = false,
    var webView: WebView? = null
) {
    val isNewTabPage: Boolean
        get() = UrlNavigator.isNewTabUrl(url)
}

class TabManager(
    private val maxTabs: Int = DEFAULT_MAX
) {
    private val tabs = mutableListOf<BrowserTab>()
    var activeIndex: Int = 0
        private set

    val size: Int get() = tabs.size
    val all: List<BrowserTab> get() = tabs.toList()
    val active: BrowserTab? get() = tabs.getOrNull(activeIndex)

    fun ensureInitial() {
        if (tabs.isEmpty()) {
            tabs.add(BrowserTab())
            activeIndex = 0
        }
    }

    fun addTab(url: String = "about:newtab"): BrowserTab? {
        if (tabs.size >= maxTabs) return null
        val tab = BrowserTab(url = url, title = if (UrlNavigator.isNewTabUrl(url)) "新标签页" else url)
        tabs.add(tab)
        activeIndex = tabs.lastIndex
        return tab
    }

    fun closeTab(index: Int): Boolean {
        if (index !in tabs.indices || tabs.size <= 1) return false
        tabs[index].webView?.apply {
            stopLoading()
            destroy()
        }
        tabs.removeAt(index)
        if (activeIndex >= tabs.size) activeIndex = tabs.lastIndex
        else if (activeIndex > index) activeIndex--
        return true
    }

    fun select(index: Int) {
        if (index in tabs.indices) activeIndex = index
    }

    fun snapshot(): List<Pair<String, String>> =
        tabs.map { it.url to it.title }

    fun restore(entries: List<Pair<String, String>>) {
        tabs.forEach { it.webView?.destroy() }
        tabs.clear()
        if (entries.isEmpty()) {
            ensureInitial()
            return
        }
        entries.forEach { (url, title) ->
            tabs.add(BrowserTab(url = url, title = title.ifBlank { "标签" }))
        }
        activeIndex = 0
    }

    companion object {
        const val DEFAULT_MAX = 8
        const val HARD_MAX = 12
    }
}
