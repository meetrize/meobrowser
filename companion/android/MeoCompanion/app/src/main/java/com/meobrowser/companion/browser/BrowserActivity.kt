package com.meobrowser.companion.browser

import android.annotation.SuppressLint
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.meobrowser.companion.R
import com.meobrowser.companion.browser.download.DownloadHub
import com.meobrowser.companion.browser.newtab.ShortcutGridAdapter
import com.meobrowser.companion.browser.newtab.ShortcutItem
import com.meobrowser.companion.browser.newtab.ShortcutStore
import com.meobrowser.companion.browser.store.BookmarkStore
import com.meobrowser.companion.browser.store.HistoryStore
import com.meobrowser.companion.browser.tab.BrowserTab
import com.meobrowser.companion.browser.tab.TabManager
import com.meobrowser.companion.channel.CompanionConnectionService
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.databinding.ActivityBrowserBinding
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.settings.SettingsActivity
import com.meobrowser.companion.sms.SmsListenCoordinator
import com.meobrowser.companion.sync.SyncEngine

class BrowserActivity : AppCompatActivity() {
    private lateinit var binding: ActivityBrowserBinding
    private lateinit var browserPrefs: BrowserPrefs
    private lateinit var pairingPrefs: PairingPrefs
    private lateinit var tabManager: TabManager
    private lateinit var shortcutStore: ShortcutStore
    private lateinit var historyStore: HistoryStore
    private lateinit var bookmarkStore: BookmarkStore
    private lateinit var downloadHub: DownloadHub
    private var didAutoConnect = false
    private var findQuery: String? = null
    private val shortcutSyncListener: () -> Unit = {
        runOnUiThread { refreshShortcutGrid() }
    }

    private val statusListener: (String, String) -> Unit = { status, _ ->
        runOnUiThread { updateLinkStatusUi(status) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val coldStart = System.currentTimeMillis()
        binding = ActivityBrowserBinding.inflate(layoutInflater)
        setContentView(binding.root)
        browserPrefs = BrowserPrefs(this)
        pairingPrefs = PairingPrefs(this)
        shortcutStore = ShortcutStore(this)
        historyStore = HistoryStore(this)
        bookmarkStore = BookmarkStore(this)
        downloadHub = DownloadHub(this)
        tabManager = TabManager(browserPrefs.maxTabs)
        SmsListenCoordinator.start(this)

        val (session, active) = browserPrefs.loadSession()
        if (session.isNotEmpty()) {
            tabManager.restore(session)
            tabManager.select(active.coerceIn(0, (tabManager.size - 1).coerceAtLeast(0)))
        } else {
            tabManager.ensureInitial()
        }

        binding.backButton.setOnClickListener { goBack() }
        binding.forwardButton.setOnClickListener { goForward() }
        binding.reloadButton.setOnClickListener { reload() }
        binding.menuButton.setOnClickListener { showMenu() }
        binding.linkStatusButton.setOnClickListener {
            startActivity(Intent(this, SettingsActivity::class.java).putExtra(SettingsActivity.EXTRA_SECTION, SettingsActivity.SECTION_LINK))
        }
        binding.addressBar.setOnEditorActionListener { _, actionId, event ->
            if (actionId == EditorInfo.IME_ACTION_GO ||
                (event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_DOWN)
            ) {
                navigate(binding.addressBar.text?.toString().orEmpty())
                true
            } else false
        }

        binding.newTabGrid.layoutManager = GridLayoutManager(this, 4)
        binding.newTabGrid.itemAnimator = null
        refreshShortcutGrid()

        binding.root.post {
            showActiveTab()
            Log.i(TAG, "MeoBrowserColdStart ms=${System.currentTimeMillis() - coldStart}")
        }
    }

    override fun onStart() {
        super.onStart()
        CompanionSession.addStatusListener(statusListener)
        SyncEngine.addShortcutChangeListener(shortcutSyncListener)
        updateLinkStatusUi(CompanionSession.statusText)
        maybeAutoConnect()
        SyncEngine.onAppForeground(this)
        refreshShortcutGrid()
    }

    override fun onStop() {
        CompanionSession.removeStatusListener(statusListener)
        SyncEngine.removeShortcutChangeListener(shortcutSyncListener)
        persistSession()
        super.onStop()
    }

    private fun maybeAutoConnect() {
        if (didAutoConnect) return
        if (!pairingPrefs.autoConnectOnLaunch) return
        if (CompanionSession.client.isConnected) return
        if (!pairingPrefs.canAutoConnectSecurityMode()) return
        didAutoConnect = true
        CompanionSession.statusText = "安全码模式：自动连接中…"
        CompanionSession.notifyStatus()
        CompanionConnectionService.startConnect(
            this,
            pairingCode = if (pairingPrefs.deviceToken.isNullOrBlank()) pairingPrefs.securityCode else null,
            hostOverride = pairingPrefs.lastHostOverride,
            forceSecurityCode = pairingPrefs.securityCode
        )
    }

    private fun updateLinkStatusUi(status: String) {
        val connected = CompanionSession.client.isConnected || status.contains("连接保持") || status.contains("已连接")
        binding.linkStatusButton.alpha = if (connected) 1f else 0.35f
    }

    private fun persistSession() {
        browserPrefs.saveSession(tabManager.snapshot(), tabManager.activeIndex)
    }

    private fun showMenu() {
        val popup = PopupMenu(this, binding.menuButton)
        popup.menu.add(0, 1, 0, "新标签页")
        popup.menu.add(0, 2, 0, "关闭标签")
        popup.menu.add(0, 3, 0, "添加书签")
        popup.menu.add(0, 4, 0, "分享")
        popup.menu.add(0, 5, 0, "页内查找")
        popup.menu.add(0, 6, 0, "桌面版网站")
        popup.menu.add(0, 7, 0, "发送到 Mac（即将推出）")
        popup.menu.add(0, 8, 0, "设置")
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> newTab()
                2 -> closeCurrentTab()
                3 -> addBookmark()
                4 -> shareCurrent()
                5 -> findInPage()
                6 -> toggleDesktopUa()
                7 -> Toast.makeText(this, "Send Tab 将在后续版本提供", Toast.LENGTH_SHORT).show()
                8 -> startActivity(Intent(this, SettingsActivity::class.java))
            }
            true
        }
        popup.show()
    }

    private fun newTab() {
        val tab = tabManager.addTab()
        if (tab == null) {
            Toast.makeText(this, "标签数已达上限（${browserPrefs.maxTabs}）", Toast.LENGTH_SHORT).show()
            return
        }
        showActiveTab()
    }

    private fun closeCurrentTab() {
        if (!tabManager.closeTab(tabManager.activeIndex)) {
            Toast.makeText(this, "至少保留一个标签", Toast.LENGTH_SHORT).show()
            return
        }
        showActiveTab()
    }

    private fun addBookmark() {
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage) {
            Toast.makeText(this, "当前是新标签页", Toast.LENGTH_SHORT).show()
            return
        }
        bookmarkStore.add(tab.title, tab.url, shortcutStore.deviceId())
        Toast.makeText(this, "已加入书签", Toast.LENGTH_SHORT).show()
        SyncEngine.schedulePush(this)
    }

    private fun shareCurrent() {
        val tab = tabManager.active ?: return
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, tab.url)
            putExtra(Intent.EXTRA_SUBJECT, tab.title)
        }
        startActivity(Intent.createChooser(send, "分享链接"))
    }

    private fun findInPage() {
        val wv = tabManager.active?.webView ?: return
        val input = EditText(this)
        AlertDialog.Builder(this)
            .setTitle("页内查找")
            .setView(input)
            .setPositiveButton("查找") { _, _ ->
                val q = input.text?.toString().orEmpty()
                findQuery = q
                wv.findAllAsync(q)
            }
            .setNeutralButton("下一个") { _, _ -> wv.findNext(true) }
            .setNegativeButton("清除") { _, _ ->
                wv.clearMatches()
                findQuery = null
            }
            .show()
    }

    private fun toggleDesktopUa() {
        browserPrefs.desktopUa = !browserPrefs.desktopUa
        Toast.makeText(
            this,
            if (browserPrefs.desktopUa) "已切换桌面 UA（刷新生效）" else "已恢复移动 UA（刷新生效）",
            Toast.LENGTH_SHORT
        ).show()
        reload()
    }

    private fun navigate(raw: String) {
        val url = UrlNavigator.normalize(raw)
        val tab = tabManager.active ?: return
        if (UrlNavigator.isNewTabUrl(url)) {
            tab.url = "about:newtab"
            tab.title = "新标签页"
            destroyWebViewIfNeeded(tab)
            showActiveTab()
            return
        }
        tab.url = url
        ensureWebView(tab).loadUrl(url)
        showActiveTab()
    }

    private fun goBack() {
        val wv = tabManager.active?.webView
        if (wv != null && wv.canGoBack()) wv.goBack()
    }

    private fun goForward() {
        val wv = tabManager.active?.webView
        if (wv != null && wv.canGoForward()) wv.goForward()
    }

    private fun reload() {
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage) {
            refreshShortcutGrid()
            return
        }
        tab.webView?.reload()
    }

    private fun showActiveTab() {
        renderTabStrip()
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage) {
            binding.newTabGrid.visibility = View.VISIBLE
            binding.webContainer.visibility = View.GONE
            binding.addressBar.setText("")
            binding.addressBar.hint = getString(R.string.address_hint)
            binding.backButton.isEnabled = false
            binding.forwardButton.isEnabled = false
            refreshShortcutGrid()
            applyLowMemoryToInactive()
            return
        }
        binding.newTabGrid.visibility = View.GONE
        binding.webContainer.visibility = View.VISIBLE
        val wv = ensureWebView(tab)
        binding.webContainer.removeAllViews()
        (wv.parent as? android.view.ViewGroup)?.removeView(wv)
        binding.webContainer.addView(
            wv,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
        )
        binding.addressBar.setText(tab.url)
        binding.backButton.isEnabled = wv.canGoBack()
        binding.forwardButton.isEnabled = wv.canGoForward()
        applyLowMemoryToInactive()
    }

    private fun applyLowMemoryToInactive() {
        if (!browserPrefs.lowMemoryMode) {
            tabManager.all.forEach { t ->
                if (t !== tabManager.active) t.webView?.onPause()
                else t.webView?.onResume()
            }
            return
        }
        val activeId = tabManager.active?.id
        tabManager.all.forEach { t ->
            if (t.id != activeId && t.webView != null) {
                destroyWebViewIfNeeded(t)
            }
        }
    }

    private fun destroyWebViewIfNeeded(tab: BrowserTab) {
        tab.webView?.apply {
            stopLoading()
            (parent as? android.view.ViewGroup)?.removeView(this)
            destroy()
        }
        tab.webView = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun ensureWebView(tab: BrowserTab): WebView {
        tab.webView?.let { return it }
        val wv = WebView(this)
        wv.settings.javaScriptEnabled = true
        wv.settings.domStorageEnabled = true
        wv.settings.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        if (browserPrefs.desktopUa) {
            wv.settings.userAgentString =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        }
        wv.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean = false

            override fun onPageFinished(view: WebView?, url: String?) {
                val t = tabManager.all.find { it.webView === view } ?: return
                t.url = url ?: t.url
                t.title = view?.title?.ifBlank { t.url } ?: t.title
                t.isLoading = false
                if (t === tabManager.active) {
                    binding.addressBar.setText(t.url)
                    binding.backButton.isEnabled = view?.canGoBack() == true
                    binding.forwardButton.isEnabled = view?.canGoForward() == true
                    binding.loadProgress.visibility = View.GONE
                    renderTabStrip()
                }
                historyStore.record(t.url, t.title, shortcutStore.deviceId())
                SyncEngine.schedulePush(this@BrowserActivity)
            }
        }
        wv.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                if (tabManager.active?.webView !== view) return
                binding.loadProgress.visibility = if (newProgress in 1..99) View.VISIBLE else View.GONE
                binding.loadProgress.progress = newProgress
            }

            override fun onReceivedTitle(view: WebView?, title: String?) {
                val t = tabManager.all.find { it.webView === view } ?: return
                if (!title.isNullOrBlank()) {
                    t.title = title
                    renderTabStrip()
                }
            }
        }
        wv.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
            downloadHub.enqueue(url, userAgent, contentDisposition, mimeType)
            Toast.makeText(this, "开始下载", Toast.LENGTH_SHORT).show()
        }
        tab.webView = wv
        if (!UrlNavigator.isNewTabUrl(tab.url)) {
            wv.loadUrl(tab.url)
        }
        return wv
    }

    private fun renderTabStrip() {
        binding.tabStrip.removeAllViews()
        tabManager.all.forEachIndexed { index, tab ->
            val chip = TextView(this).apply {
                text = tab.title.take(12).ifBlank { "标签" }
                setPadding(24, 12, 24, 12)
                textSize = 13f
                setTextColor(if (index == tabManager.activeIndex) Color.WHITE else Color.BLACK)
                setBackgroundColor(if (index == tabManager.activeIndex) 0xFF3D7EFF.toInt() else 0xFFE8E8E8.toInt())
                setOnClickListener {
                    tabManager.select(index)
                    showActiveTab()
                }
                setOnLongClickListener {
                    tabManager.select(index)
                    closeCurrentTab()
                    true
                }
            }
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
            lp.marginEnd = 6
            binding.tabStrip.addView(chip, lp)
        }
        val add = TextView(this).apply {
            text = "+"
            gravity = Gravity.CENTER
            setPadding(28, 12, 28, 12)
            textSize = 18f
            setOnClickListener { newTab() }
        }
        binding.tabStrip.addView(add)
    }

    private fun refreshShortcutGrid() {
        val items = shortcutStore.loadActive()
        binding.newTabGrid.adapter = ShortcutGridAdapter(items, onOpen = { item ->
            navigate(item.url)
        }, onLong = { item ->
            AlertDialog.Builder(this)
                .setTitle(item.title)
                .setItems(arrayOf("编辑", "删除")) { _, which ->
                    when (which) {
                        0 -> editShortcut(item)
                        1 -> {
                            shortcutStore.softDelete(item.id)
                            refreshShortcutGrid()
                            SyncEngine.schedulePush(this)
                        }
                    }
                }
                .show()
        }, onAdd = { editShortcut(null) })
    }

    private fun editShortcut(existing: ShortcutItem?) {
        val titleInput = EditText(this).apply {
            hint = "标题"
            setText(existing?.title.orEmpty())
        }
        val urlInput = EditText(this).apply {
            hint = "URL"
            setText(existing?.url.orEmpty())
        }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 20, 40, 0)
            addView(titleInput)
            addView(urlInput)
        }
        AlertDialog.Builder(this)
            .setTitle(if (existing == null) "添加快捷方式" else "编辑快捷方式")
            .setView(box)
            .setPositiveButton("保存") { _, _ ->
                val title = titleInput.text?.toString()?.trim().orEmpty()
                val url = UrlNavigator.normalize(urlInput.text?.toString().orEmpty())
                if (title.isBlank() || UrlNavigator.isNewTabUrl(url)) {
                    Toast.makeText(this, "请填写标题与有效 URL", Toast.LENGTH_SHORT).show()
                    return@setPositiveButton
                }
                val order = existing?.order ?: shortcutStore.loadActive().size
                val item = (existing ?: ShortcutItem(title = title, url = url, order = order)).copy(
                    title = title,
                    url = url,
                    order = order
                )
                shortcutStore.upsert(item)
                refreshShortcutGrid()
                SyncEngine.schedulePush(this)
            }
            .setNegativeButton("取消", null)
            .show()
    }

    companion object {
        private const val TAG = "MeoBrowser"
    }
}
