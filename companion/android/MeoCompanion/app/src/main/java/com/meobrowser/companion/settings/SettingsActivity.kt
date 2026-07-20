package com.meobrowser.companion.settings

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.SwitchCompat
import androidx.fragment.app.Fragment
import com.meobrowser.companion.R
import com.meobrowser.companion.browser.BrowserPrefs
import com.meobrowser.companion.browser.download.DownloadHub
import com.meobrowser.companion.browser.store.BookmarkStore
import com.meobrowser.companion.browser.store.HistoryStore
import com.meobrowser.companion.databinding.ActivitySettingsBinding
import com.meobrowser.companion.databinding.FragmentSettingsHomeBinding
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.sync.SyncEngine
import com.meobrowser.companion.sync.SyncPrefs
import com.meobrowser.companion.ui.MainActivity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class SettingsActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySettingsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySettingsBinding.inflate(layoutInflater)
        setContentView(binding.root)
        binding.settingsToolbar.title = getString(R.string.settings_title)
        binding.settingsToolbar.setNavigationOnClickListener { onBackPressedDispatcher.onBackPressed() }
        binding.settingsToolbar.setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material)

        when (intent.getStringExtra(EXTRA_SECTION)) {
            SECTION_LINK -> openCompanion()
            SECTION_SYNC -> showFragment(SyncSettingsFragment())
            SECTION_DOWNLOADS -> showFragment(DownloadsFragment())
            SECTION_HISTORY -> showFragment(HistoryFragment())
            SECTION_BOOKMARKS -> showFragment(BookmarksFragment())
            else -> showFragment(SettingsHomeFragment())
        }
    }

    fun showFragment(fragment: Fragment) {
        supportFragmentManager.beginTransaction()
            .replace(R.id.settingsContainer, fragment)
            .commit()
    }

    fun openCompanion() {
        startActivity(Intent(this, MainActivity::class.java))
    }

    companion object {
        const val EXTRA_SECTION = "section"
        const val SECTION_LINK = "link"
        const val SECTION_SYNC = "sync"
        const val SECTION_DOWNLOADS = "downloads"
        const val SECTION_HISTORY = "history"
        const val SECTION_BOOKMARKS = "bookmarks"
    }
}

class SettingsHomeFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val binding = FragmentSettingsHomeBinding.inflate(inflater, container, false)
        val act = activity as SettingsActivity
        binding.openNotificationSettings.setOnClickListener { act.openCompanion() }
        binding.openDownloadSettings.setOnClickListener { act.showFragment(DownloadsFragment()) }
        binding.openHistory.setOnClickListener { act.showFragment(HistoryFragment()) }
        binding.openBookmarks.setOnClickListener { act.showFragment(BookmarksFragment()) }

        val browserPrefs = BrowserPrefs(requireContext())
        val pairingPrefs = PairingPrefs(requireContext())
        binding.generalSummary.text = buildString {
            append(getString(R.string.settings_general_hint))
            append("\n\n")
            append("省内存模式：${if (browserPrefs.lowMemoryMode) "开" else "关"}（⋮ → 自动同步）\n")
            append("标签上限：${browserPrefs.maxTabs}\n")
            append("启动自动连接：${if (pairingPrefs.autoConnectOnLaunch) "开" else "关"}")
        }
        return binding.root
    }
}

class SyncSettingsFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val syncPrefs = SyncPrefs(ctx)
        val pairingPrefs = PairingPrefs(ctx)
        val browserPrefs = BrowserPrefs(ctx)
        val root = LinearLayoutScroll(ctx)

        root.addTitle(getString(R.string.settings_section_sync))
        root.addBody(getString(R.string.sync_privacy_hint))

        val enable = root.addSwitch("启用自动同步", syncPrefs.enabled) {
            syncPrefs.enabled = it
            if (it) {
                // 打开总开关时默认勾选快捷方式
                if (!syncPrefs.syncShortcuts && !syncPrefs.syncHistory && !syncPrefs.syncBookmarks) {
                    syncPrefs.syncShortcuts = true
                }
            }
        }
        root.addSwitch("同步快捷方式", syncPrefs.syncShortcuts) { syncPrefs.syncShortcuts = it }
        root.addSwitch("同步历史", syncPrefs.syncHistory) {
            if (it) {
                Toast.makeText(ctx, "历史 URL 将经局域网明文发送", Toast.LENGTH_LONG).show()
            }
            syncPrefs.syncHistory = it
        }
        root.addSwitch("同步书签", syncPrefs.syncBookmarks) { syncPrefs.syncBookmarks = it }
        root.addSwitch("启动时自动连接 Mac", pairingPrefs.autoConnectOnLaunch) {
            pairingPrefs.autoConnectOnLaunch = it
        }
        root.addBody("默认开启。已配对或已存安全码、且保存过主机地址时，打开浏览器会自动连接。")
        root.addSwitch("省内存模式", browserPrefs.lowMemoryMode) { browserPrefs.lowMemoryMode = it }

        val connected = CompanionSession.client.isConnected
        val last = if (syncPrefs.lastSyncAt > 0) {
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(syncPrefs.lastSyncAt))
        } else "尚未同步"
        root.addBody("Mac 连接：${if (connected) "已连接" else "未连接（请先到「互联与配对」连接）"}\n最近同步：$last")

        root.addButton("立即同步") {
            if (!syncPrefs.enabled) {
                Toast.makeText(ctx, "请先打开同步总开关", Toast.LENGTH_SHORT).show()
                return@addButton
            }
            if (!syncPrefs.syncShortcuts && !syncPrefs.syncHistory && !syncPrefs.syncBookmarks) {
                syncPrefs.syncShortcuts = true
            }
            Toast.makeText(ctx, "正在同步…", Toast.LENGTH_SHORT).show()
            Thread {
                val result = SyncEngine.syncNow(ctx)
                activity?.runOnUiThread {
                    Toast.makeText(ctx, result.message, Toast.LENGTH_LONG).show()
                }
            }.start()
        }
        root.addButton("返回") {
            (activity as? SettingsActivity)?.showFragment(SettingsHomeFragment())
        }
        enable.isEnabled = true
        return root
    }
}

class DownloadsFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val root = LinearLayoutScroll(requireContext())
        root.addTitle(getString(R.string.settings_section_downloads))
        val hub = DownloadHub(requireContext())
        val list = hub.recent()
        if (list.isEmpty()) {
            root.addBody("暂无下载记录")
        } else {
            list.forEach { e ->
                root.addBody("${e.fileName}\n${e.url}")
            }
        }
        root.addButton("返回") {
            (activity as? SettingsActivity)?.showFragment(SettingsHomeFragment())
        }
        return root
    }
}

class HistoryFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val root = LinearLayoutScroll(requireContext())
        root.addTitle(getString(R.string.settings_section_history))
        HistoryStore(requireContext()).loadActive().take(100).forEach { e ->
            root.addBody("${e.title}\n${e.url}")
        }
        root.addButton("返回") {
            (activity as? SettingsActivity)?.showFragment(SettingsHomeFragment())
        }
        return root
    }
}

class BookmarksFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val root = LinearLayoutScroll(requireContext())
        root.addTitle(getString(R.string.settings_section_bookmarks))
        val store = BookmarkStore(requireContext())
        store.loadActive().forEach { e ->
            root.addBody("${e.title}\n${e.url}")
        }
        root.addButton("返回") {
            (activity as? SettingsActivity)?.showFragment(SettingsHomeFragment())
        }
        return root
    }
}

/** 轻量动态表单容器，避免为每个设置页再建 XML。 */
private class LinearLayoutScroll(context: android.content.Context) : android.widget.ScrollView(context) {
    private val box = android.widget.LinearLayout(context).apply {
        orientation = android.widget.LinearLayout.VERTICAL
        setPadding(40, 32, 40, 48)
    }

    init {
        addView(box)
    }

    fun addTitle(text: String) {
        box.addView(TextView(context).apply {
            this.text = text
            textSize = 18f
            setPadding(0, 8, 0, 12)
        })
    }

    fun addBody(text: String) {
        box.addView(TextView(context).apply {
            this.text = text
            textSize = 14f
            setPadding(0, 6, 0, 6)
        })
    }

    fun addSwitch(label: String, checked: Boolean, onChange: (Boolean) -> Unit): SwitchCompat {
        val sw = SwitchCompat(context).apply {
            text = label
            isChecked = checked
            setPadding(0, 16, 0, 16)
            setOnCheckedChangeListener { _, isChecked -> onChange(isChecked) }
        }
        box.addView(sw)
        return sw
    }

    fun addButton(label: String, onClick: () -> Unit) {
        box.addView(Button(context).apply {
            text = label
            setOnClickListener { onClick() }
        })
    }
}
