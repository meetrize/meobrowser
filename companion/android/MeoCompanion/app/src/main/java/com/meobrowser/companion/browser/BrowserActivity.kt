package com.meobrowser.companion.browser

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.ActivityInfo
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.inputmethod.EditorInfo
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.view.WindowCompat
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.meobrowser.companion.R
import com.meobrowser.companion.browser.download.DownloadHub
import com.meobrowser.companion.browser.newtab.ShortcutGridAdapter
import com.meobrowser.companion.browser.newtab.ShortcutIconHelper
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
import com.meobrowser.companion.sync.SyncPrefs
import com.meobrowser.companion.ui.MainActivity

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
    private var toolsSheet: BottomSheetDialog? = null
    private var tabsSheet: BottomSheetDialog? = null
    private val shortcutSyncListener: () -> Unit = {
        runOnUiThread { refreshShortcutGrid() }
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
        ShortcutIconHelper.init(this)
        tabManager = TabManager(browserPrefs.maxTabs)
        SmsListenCoordinator.start(this)

        applyOrientationMode()
        applyFullscreenMode()

        val (session, active) = browserPrefs.loadSession()
        if (session.isNotEmpty()) {
            tabManager.restore(session)
            tabManager.select(active.coerceIn(0, (tabManager.size - 1).coerceAtLeast(0)))
        } else {
            tabManager.ensureInitial()
        }

        binding.backButton.setOnClickListener { goBack() }
        binding.forwardButton.setOnClickListener { goForward() }
        binding.toolsButton.setOnClickListener { showToolsSheet() }
        binding.tabsButton.setOnClickListener { showTabsSheet() }
        binding.newTabButton.setOnClickListener { newTab() }
        binding.overflowButton.setOnClickListener { showOverflowMenu() }
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
            handleLaunchIntent(intent)
            showActiveTab()
            Log.i(TAG, "MeoBrowserColdStart ms=${System.currentTimeMillis() - coldStart}")
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent)
        showActiveTab()
    }

    override fun onStart() {
        super.onStart()
        SyncEngine.addShortcutChangeListener(shortcutSyncListener)
        maybeAutoConnect()
        SyncEngine.onAppForeground(this)
        refreshShortcutGrid()
        updateNavChrome()
    }

    override fun onStop() {
        SyncEngine.removeShortcutChangeListener(shortcutSyncListener)
        persistSession()
        super.onStop()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && browserPrefs.fullscreen) {
            applyFullscreenMode()
        }
    }

    private fun handleLaunchIntent(intent: Intent?) {
        val data = intent?.dataString ?: return
        if (data.isBlank()) return
        navigate(data)
        intent.data = null
    }

    private fun maybeAutoConnect() {
        if (didAutoConnect) return
        if (CompanionSession.client.isConnected) return
        if (!pairingPrefs.canAutoConnect()) return
        didAutoConnect = true
        CompanionSession.statusText = "自动连接中…"
        CompanionSession.notifyStatus()
        val useToken = !pairingPrefs.deviceToken.isNullOrBlank()
        CompanionConnectionService.startConnect(
            this,
            pairingCode = if (useToken) null else pairingPrefs.securityCode,
            hostOverride = pairingPrefs.lastHostOverride,
            forceSecurityCode = pairingPrefs.securityCode
        )
    }

    private fun persistSession() {
        browserPrefs.saveSession(tabManager.snapshot(), tabManager.activeIndex)
    }

    private fun showOverflowMenu() {
        val popup = PopupMenu(this, binding.overflowButton)
        popup.menu.add(0, 1, 0, getString(R.string.menu_bookmark))
        popup.menu.add(0, 2, 0, getString(R.string.menu_link))
        popup.menu.add(0, 3, 0, getString(R.string.menu_sync))
        popup.menu.add(0, 4, 0, getString(R.string.menu_sync_now))
        popup.menu.add(0, 5, 0, getString(R.string.menu_settings))
        popup.menu.add(0, 6, 0, getString(R.string.menu_find))
        popup.menu.add(0, 7, 0, getString(R.string.menu_add_to_home))
        popup.menu.add(0, 8, 0, getString(R.string.menu_share))
        popup.menu.add(0, 9, 0, getString(R.string.menu_send_to_mac))
        popup.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                1 -> addBookmark()
                2 -> startActivity(Intent(this, MainActivity::class.java))
                3 -> startActivity(
                    Intent(this, SettingsActivity::class.java)
                        .putExtra(SettingsActivity.EXTRA_SECTION, SettingsActivity.SECTION_SYNC)
                )
                4 -> syncNowFromMenu()
                5 -> startActivity(Intent(this, SettingsActivity::class.java))
                6 -> findInPage()
                7 -> addToHomeScreen()
                8 -> shareCurrent()
                9 -> sendToMac()
            }
            true
        }
        popup.show()
    }

    private fun syncNowFromMenu() {
        val syncPrefs = SyncPrefs(this)
        if (!syncPrefs.enabled) {
            Toast.makeText(this, "请先在「自动同步」中打开同步开关", Toast.LENGTH_SHORT).show()
            startActivity(
                Intent(this, SettingsActivity::class.java)
                    .putExtra(SettingsActivity.EXTRA_SECTION, SettingsActivity.SECTION_SYNC)
            )
            return
        }
        if (!syncPrefs.syncShortcuts && !syncPrefs.syncHistory && !syncPrefs.syncBookmarks) {
            syncPrefs.syncShortcuts = true
        }
        Toast.makeText(this, "正在同步…", Toast.LENGTH_SHORT).show()
        Thread {
            val result = SyncEngine.syncNow(this)
            runOnUiThread {
                Toast.makeText(this, result.message, Toast.LENGTH_LONG).show()
                if (result.ok) refreshShortcutGrid()
            }
        }.start()
    }

    private fun showToolsSheet() {
        toolsSheet?.dismiss()
        val dialog = BottomSheetDialog(this)
        val view = layoutInflater.inflate(R.layout.bottom_sheet_tools, null)
        dialog.setContentView(view)
        view.findViewById<TextView>(R.id.toolsDownloads).setOnClickListener {
            dialog.dismiss()
            startActivity(
                Intent(this, SettingsActivity::class.java)
                    .putExtra(SettingsActivity.EXTRA_SECTION, SettingsActivity.SECTION_DOWNLOADS)
            )
        }
        view.findViewById<TextView>(R.id.toolsNewBookmark).setOnClickListener {
            dialog.dismiss()
            addBookmark()
        }
        view.findViewById<TextView>(R.id.toolsDesktopMode).apply {
            text = if (browserPrefs.desktopUa) "桌面模式 ✓" else getString(R.string.tools_desktop_mode)
            setOnClickListener {
                dialog.dismiss()
                toggleDesktopUa()
            }
        }
        view.findViewById<TextView>(R.id.toolsReload).setOnClickListener {
            dialog.dismiss()
            reload()
        }
        view.findViewById<TextView>(R.id.toolsFullscreen).apply {
            text = if (browserPrefs.fullscreen) "全屏 ✓" else getString(R.string.tools_fullscreen)
            setOnClickListener {
                dialog.dismiss()
                toggleFullscreen()
            }
        }
        view.findViewById<TextView>(R.id.toolsRotate).apply {
            text = "屏幕旋转（${orientationLabel()}）"
            setOnClickListener {
                browserPrefs.cycleOrientationMode()
                applyOrientationMode()
                text = "屏幕旋转（${orientationLabel()}）"
                Toast.makeText(this@BrowserActivity, "已切换：${orientationLabel()}", Toast.LENGTH_SHORT).show()
            }
        }
        view.findViewById<TextView>(R.id.toolsFontSize).apply {
            text = "字体大小 ${browserPrefs.textZoom}%"
            setOnClickListener {
                val zoom = browserPrefs.cycleTextZoom()
                applyTextZoomToAll()
                text = "字体大小 $zoom%"
                Toast.makeText(this@BrowserActivity, "字号 $zoom%", Toast.LENGTH_SHORT).show()
            }
        }
        view.findViewById<TextView>(R.id.toolsCollapse).setOnClickListener { dialog.dismiss() }
        toolsSheet = dialog
        dialog.show()
    }

    private fun showTabsSheet() {
        tabsSheet?.dismiss()
        val dialog = BottomSheetDialog(this)
        val view = layoutInflater.inflate(R.layout.bottom_sheet_tabs, null)
        dialog.setContentView(view)
        val list = view.findViewById<RecyclerView>(R.id.tabsList)
        list.layoutManager = LinearLayoutManager(this)
        val adapter = TabsSheetAdapter(
            tabs = tabManager.all.toMutableList(),
            activeIndex = tabManager.activeIndex,
            onSelect = { index ->
                tabManager.select(index)
                dialog.dismiss()
                showActiveTab()
            },
            onClose = { index ->
                if (!tabManager.closeTab(index)) {
                    Toast.makeText(this, "至少保留一个标签", Toast.LENGTH_SHORT).show()
                    return@TabsSheetAdapter
                }
                dialog.dismiss()
                showActiveTab()
            }
        )
        list.adapter = adapter
        ItemTouchHelper(object : ItemTouchHelper.SimpleCallback(0, ItemTouchHelper.LEFT) {
            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean = false

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
                val index = viewHolder.bindingAdapterPosition
                if (index == RecyclerView.NO_POSITION) return
                if (!tabManager.closeTab(index)) {
                    adapter.notifyItemChanged(index)
                    Toast.makeText(this@BrowserActivity, "至少保留一个标签", Toast.LENGTH_SHORT).show()
                    return
                }
                dialog.dismiss()
                showActiveTab()
            }
        }).attachToRecyclerView(list)
        tabsSheet = dialog
        dialog.show()
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
        if (tab.isNewTabPage) {
            Toast.makeText(this, "当前是新标签页", Toast.LENGTH_SHORT).show()
            return
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, tab.url)
            putExtra(Intent.EXTRA_SUBJECT, tab.title)
        }
        startActivity(Intent.createChooser(send, "分享链接"))
    }

    private fun sendToMac() {
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage || tab.url.isBlank()) {
            Toast.makeText(this, "当前是新标签页", Toast.LENGTH_SHORT).show()
            return
        }
        CompanionSession.sendOpenUrl(this, tab.url) { ok, message ->
            runOnUiThread {
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            }
            if (ok) {
                Log.i(TAG, "open_url sent")
            }
        }
    }

    private fun addToHomeScreen() {
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage) {
            Toast.makeText(this, "当前是新标签页", Toast.LENGTH_SHORT).show()
            return
        }
        if (!ShortcutManagerCompat.isRequestPinShortcutSupported(this)) {
            Toast.makeText(this, "系统不支持固定快捷方式", Toast.LENGTH_SHORT).show()
            return
        }
        val label = tab.title.ifBlank { tab.url }.take(24)
        val launch = Intent(Intent.ACTION_VIEW, Uri.parse(tab.url)).apply {
            setPackage(packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val info = ShortcutInfoCompat.Builder(this, "meo-pin-${tab.url.hashCode()}")
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(IconCompat.createWithResource(this, android.R.drawable.ic_menu_compass))
            .setIntent(launch)
            .build()
        val ok = ShortcutManagerCompat.requestPinShortcut(this, info, null)
        Toast.makeText(
            this,
            if (ok) "请确认添加到桌面" else "无法添加快捷方式",
            Toast.LENGTH_SHORT
        ).show()
    }

    private fun findInPage() {
        val wv = tabManager.active?.webView ?: return
        val input = EditText(this)
        findQuery?.let { input.setText(it) }
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

    private fun toggleFullscreen() {
        browserPrefs.fullscreen = !browserPrefs.fullscreen
        applyFullscreenMode()
        Toast.makeText(
            this,
            if (browserPrefs.fullscreen) "已进入全屏" else "已退出全屏",
            Toast.LENGTH_SHORT
        ).show()
    }

    private fun orientationLabel(): String = when (browserPrefs.orientationMode) {
        1 -> "竖屏"
        2 -> "横屏"
        else -> "跟随"
    }

    private fun applyOrientationMode() {
        requestedOrientation = when (browserPrefs.orientationMode) {
            1 -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            2 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    private fun applyFullscreenMode() {
        WindowCompat.setDecorFitsSystemWindows(window, !browserPrefs.fullscreen)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val controller = window.insetsController ?: return
            if (browserPrefs.fullscreen) {
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            } else {
                controller.show(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = if (browserPrefs.fullscreen) {
                (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION)
            } else {
                View.SYSTEM_UI_FLAG_VISIBLE
            }
        }
        binding.topBar.visibility = if (browserPrefs.fullscreen) View.GONE else View.VISIBLE
        binding.bottomBar.visibility = if (browserPrefs.fullscreen) View.GONE else View.VISIBLE
    }

    private fun applyTextZoomToAll() {
        val zoom = browserPrefs.textZoom
        tabManager.all.forEach { it.webView?.settings?.textZoom = zoom }
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
        if (wv != null && wv.canGoBack()) {
            wv.goBack()
            updateNavChrome()
        }
    }

    private fun goForward() {
        val wv = tabManager.active?.webView
        if (wv != null && wv.canGoForward()) {
            wv.goForward()
            updateNavChrome()
        }
    }

    private fun reload() {
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage) {
            refreshShortcutGrid()
            return
        }
        tab.webView?.reload()
    }

    private fun updateNavChrome() {
        val tab = tabManager.active
        val wv = tab?.webView
        val canBack = wv?.canGoBack() == true
        val canForward = wv?.canGoForward() == true
        binding.backButton.isEnabled = canBack
        binding.forwardButton.isEnabled = canForward
        binding.backButton.alpha = if (canBack) 1f else 0.35f
        binding.forwardButton.alpha = if (canForward) 1f else 0.35f
        binding.tabsCountBadge.text = tabManager.size.coerceAtMost(99).toString()
    }

    private fun showActiveTab() {
        updateNavChrome()
        val tab = tabManager.active ?: return
        if (tab.isNewTabPage) {
            binding.newTabContainer.visibility = View.VISIBLE
            binding.webContainer.visibility = View.GONE
            binding.addressBar.setText("")
            binding.addressBar.hint = getString(R.string.address_hint)
            binding.backButton.isEnabled = false
            binding.forwardButton.isEnabled = false
            binding.backButton.alpha = 0.35f
            binding.forwardButton.alpha = 0.35f
            refreshShortcutGrid()
            applyLowMemoryToInactive()
            return
        }
        binding.newTabContainer.visibility = View.GONE
        binding.webContainer.visibility = View.VISIBLE
        val wv = ensureWebView(tab)
        binding.webContainer.removeAllViews()
        (wv.parent as? ViewGroup)?.removeView(wv)
        binding.webContainer.addView(
            wv,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.MATCH_PARENT
            )
        )
        binding.addressBar.setText(tab.url)
        updateNavChrome()
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
            (parent as? ViewGroup)?.removeView(this)
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
        wv.settings.textZoom = browserPrefs.textZoom
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
                    updateNavChrome()
                    binding.loadProgress.visibility = View.GONE
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
                    updateNavChrome()
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

    private fun refreshShortcutGrid() {
        val items = shortcutStore.loadActive()
        // 后台预热磁盘/网络图标，网格滚动时更快命中内存
        ShortcutIconHelper.prefetch(items)
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
        val view = layoutInflater.inflate(R.layout.dialog_edit_shortcut, null)
        val titleInput = view.findViewById<EditText>(R.id.shortcutTitleInput)
        val urlInput = view.findViewById<EditText>(R.id.shortcutUrlInput)
        val iconUrlInput = view.findViewById<EditText>(R.id.shortcutIconUrlInput)
        val preview = view.findViewById<android.widget.ImageView>(R.id.shortcutIconPreview)
        val letter = view.findViewById<TextView>(R.id.shortcutIconLetter)
        val fetchBtn = view.findViewById<com.google.android.material.button.MaterialButton>(R.id.shortcutFetchIconButton)
        val errorView = view.findViewById<TextView>(R.id.shortcutEditError)

        titleInput.setText(existing?.title.orEmpty())
        urlInput.setText(existing?.url.orEmpty())
        iconUrlInput.setText(existing?.iconURL.orEmpty())

        fun showError(msg: String?) {
            if (msg.isNullOrBlank()) {
                errorView.visibility = View.GONE
                errorView.text = ""
            } else {
                errorView.visibility = View.VISIBLE
                errorView.text = msg
            }
        }

        fun applyPreview(cached: ShortcutIconHelper.CachedIcon?) {
            if (cached == null) {
                preview.setImageDrawable(null)
                letter.visibility = View.VISIBLE
                letter.text = ShortcutIconHelper.letter(
                    titleInput.text?.toString().orEmpty(),
                    urlInput.text?.toString().orEmpty()
                )
            } else {
                letter.visibility = View.GONE
                val pad = if (cached.fit == ShortcutIconHelper.FitStyle.INSET) {
                    (6 * resources.displayMetrics.density).toInt()
                } else 0
                preview.setPadding(pad, pad, pad, pad)
                preview.scaleType = if (cached.fit == ShortcutIconHelper.FitStyle.INSET) {
                    android.widget.ImageView.ScaleType.FIT_CENTER
                } else {
                    android.widget.ImageView.ScaleType.CENTER_CROP
                }
                preview.setImageBitmap(cached.bitmap)
            }
        }

        fun refreshPreview() {
            letter.visibility = View.VISIBLE
            letter.text = ShortcutIconHelper.letter(
                titleInput.text?.toString().orEmpty(),
                urlInput.text?.toString().orEmpty()
            )
            preview.setImageDrawable(null)
            ShortcutIconHelper.loadPreview(
                urlInput.text?.toString().orEmpty(),
                iconUrlInput.text?.toString().orEmpty()
            ) { cached ->
                applyPreview(cached)
            }
        }

        refreshPreview()

        fetchBtn.setOnClickListener {
            val pageUrl = UrlNavigator.normalize(urlInput.text?.toString().orEmpty())
            if (UrlNavigator.isNewTabUrl(pageUrl) || pageUrl.isBlank()) {
                showError("请先输入有效的网址，再自动获取图标")
                return@setOnClickListener
            }
            showError(null)
            fetchBtn.isEnabled = false
            fetchBtn.text = getString(R.string.shortcut_fetch_icon_busy)
            ShortcutIconHelper.fetchForEditor(
                pageUrl,
                iconUrlInput.text?.toString()
            ) { ok, iconUrl, cached, message ->
                fetchBtn.isEnabled = true
                fetchBtn.text = getString(R.string.shortcut_fetch_icon)
                if (!ok || iconUrl == null || cached == null) {
                    showError(message)
                    return@fetchForEditor
                }
                iconUrlInput.setText(iconUrl)
                applyPreview(cached)
                showError(null)
                Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            }
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(if (existing == null) "添加快捷方式" else "编辑快捷方式")
            .setView(view)
            .setPositiveButton("保存", null)
            .setNegativeButton("取消", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val title = titleInput.text?.toString()?.trim().orEmpty()
                val url = UrlNavigator.normalize(urlInput.text?.toString().orEmpty())
                val iconRaw = iconUrlInput.text?.toString()?.trim().orEmpty()
                if (title.isBlank()) {
                    showError("请输入名称")
                    return@setOnClickListener
                }
                if (UrlNavigator.isNewTabUrl(url) || url.isBlank()) {
                    showError("请输入有效的网址")
                    return@setOnClickListener
                }
                val iconURL = when {
                    iconRaw.isBlank() -> ""
                    iconRaw.startsWith("http://") || iconRaw.startsWith("https://") -> iconRaw
                    else -> {
                        showError("请输入有效的图标链接（http/https）")
                        return@setOnClickListener
                    }
                }
                val order = existing?.order ?: shortcutStore.loadActive().size
                val item = (existing ?: ShortcutItem(title = title, url = url, order = order)).copy(
                    title = title,
                    url = url,
                    iconURL = iconURL,
                    order = order,
                    updatedAt = System.currentTimeMillis() / 1000,
                    deviceId = shortcutStore.deviceId()
                )
                shortcutStore.upsert(item)
                refreshShortcutGrid()
                SyncEngine.schedulePush(this)
                dialog.dismiss()
            }
        }
        dialog.show()
    }

    private class TabsSheetAdapter(
        private val tabs: MutableList<BrowserTab>,
        private val activeIndex: Int,
        private val onSelect: (Int) -> Unit,
        private val onClose: (Int) -> Unit
    ) : RecyclerView.Adapter<TabsSheetAdapter.VH>() {

        class VH(view: View) : RecyclerView.ViewHolder(view) {
            val title: TextView = view.findViewById(R.id.tabTitle)
            val close: ImageButton = view.findViewById(R.id.tabClose)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val v = LayoutInflater.from(parent.context).inflate(R.layout.item_tab_row, parent, false)
            return VH(v)
        }

        override fun getItemCount(): Int = tabs.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val tab = tabs[position]
            holder.title.text = tab.title.ifBlank { tab.url.ifBlank { "标签" } }
            holder.title.setTextColor(if (position == activeIndex) 0xFF007AFF.toInt() else Color.BLACK)
            holder.itemView.setOnClickListener {
                val pos = holder.bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) onSelect(pos)
            }
            holder.close.setOnClickListener {
                val pos = holder.bindingAdapterPosition
                if (pos != RecyclerView.NO_POSITION) onClose(pos)
            }
        }
    }

    companion object {
        private const val TAG = "MeoBrowser"
    }
}
