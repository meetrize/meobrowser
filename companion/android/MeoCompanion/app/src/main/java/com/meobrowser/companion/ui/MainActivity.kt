package com.meobrowser.companion.ui

import android.Manifest
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.graphics.drawable.DrawableCompat
import androidx.lifecycle.lifecycleScope
import com.meobrowser.companion.R
import com.meobrowser.companion.channel.CompanionConnectionService
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.channel.LinkConnectionState
import com.meobrowser.companion.databinding.ActivityMainBinding
import com.meobrowser.companion.pairing.CompanionAuthMode
import com.meobrowser.companion.pairing.NotificationMirrorMode
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.setup.SetupCheckItem
import com.meobrowser.companion.setup.SetupChecker
import com.meobrowser.companion.setup.SetupItemId
import com.meobrowser.companion.sms.OtpNotificationListener
import com.meobrowser.companion.sms.OtpParser
import com.meobrowser.companion.sms.RecentOtpSms
import com.meobrowser.companion.sms.RecentSmsOtpReader
import com.meobrowser.companion.sms.SmsListenCoordinator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private lateinit var prefs: PairingPrefs
    private var readingRecentOtp = false
    private var showAllChecks = false
    private var didAutoConnect = false
    private var suppressMirrorModeCallback = false

    private val smsPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { granted ->
        val ok = granted[Manifest.permission.READ_SMS] == true &&
            granted[Manifest.permission.RECEIVE_SMS] == true
        if (ok) {
            SmsListenCoordinator.start(this)
            readRecentOtpSms()
        } else {
            binding.recentOtpResultText.text = "未授予短信权限，无法读取收件箱"
            Toast.makeText(this, "请授予短信权限后再试", Toast.LENGTH_LONG).show()
        }
        refreshChecks()
    }

    private val statusListener: (String, String) -> Unit = { status, _ ->
        runOnUiThread {
            if (!::binding.isInitialized) return@runOnUiThread
            updateLinkStatusUi(status)
            refreshOtpDisplay()
            refreshChecks()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        prefs = PairingPrefs(this)
        setupToolbar()
        SmsListenCoordinator.start(this)
        restoreConnectionForm()
        applyAuthModeUi()
        applyMirrorModeUi(fromUser = false)
        updateLinkStatusUi(CompanionSession.statusText)

        binding.authModeGroup.setOnCheckedChangeListener { _, checkedId ->
            prefs.authMode = when (checkedId) {
                binding.authModeSecurity.id -> CompanionAuthMode.SECURITY_CODE
                else -> CompanionAuthMode.PAIRING_CODE
            }
            applyAuthModeUi()
            persistCodeFromInput()
        }

        binding.mirrorModeGroup.setOnCheckedChangeListener { _, checkedId ->
            if (suppressMirrorModeCallback) return@setOnCheckedChangeListener
            when (checkedId) {
                binding.mirrorModeAll.id -> confirmEnableAllMirror()
                else -> {
                    prefs.notificationMirrorMode = NotificationMirrorMode.OTP_ONLY
                    applyMirrorModeUi(fromUser = true)
                }
            }
        }

        binding.toggleChecksButton.setOnClickListener {
            showAllChecks = !showAllChecks
            binding.toggleChecksButton.text = if (showAllChecks) "只看未通过" else "展开全部"
            refreshChecks()
        }

        binding.notifAccessButton.setOnClickListener {
            OtpNotificationListener.openSettings(this)
            Toast.makeText(
                this,
                "请找到 Meo Companion / Meo 通知监听，打开开关后返回",
                Toast.LENGTH_LONG
            ).show()
        }

        binding.rescanNotifButton.setOnClickListener {
            rescanNotifications()
        }

        // 设置显示已开但服务未连时，进页就尝试重绑
        OtpNotificationListener.ensureBound(this)

        binding.setupWizardButton.setOnClickListener {
            SetupWizardActivity.start(this)
        }

        binding.connectButton.setOnClickListener {
            connectFromForm(manual = true)
        }

        binding.disconnectButton.setOnClickListener {
            CompanionConnectionService.disconnect(this)
        }

        binding.readRecentOtpButton.setOnClickListener {
            if (!RecentSmsOtpReader.hasReadPermission(this)) {
                smsPermissionLauncher.launch(
                    arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS)
                )
            } else {
                readRecentOtpSms()
            }
        }

        binding.manualOtpButton.setOnClickListener {
            val input = android.widget.EditText(this).apply {
                hint = "输入 4～8 位测试码"
                inputType = android.text.InputType.TYPE_CLASS_NUMBER
            }
            AlertDialog.Builder(this)
                .setTitle("手动发送测试码")
                .setView(input)
                .setPositiveButton("发送") { _, _ ->
                    val raw = input.text?.toString().orEmpty()
                    val code = OtpParser.extract(raw) ?: raw.trim()
                    if (code.isBlank()) {
                        Toast.makeText(this, "无效验证码", Toast.LENGTH_SHORT).show()
                    } else {
                        CompanionSession.pushOtp(this, code)
                    }
                }
                .setNegativeButton("取消", null)
                .show()
        }

        refreshChecks()
        refreshOtpDisplay()

        if (SetupChecker.shouldAutoShowWizard(this)) {
            SetupWizardActivity.start(this)
        } else {
            maybeAutoConnect()
        }
    }

    private fun persistCodeFromInput() {
        val code = binding.pairingCodeInput.text?.toString()?.trim().orEmpty()
        if (code.isBlank()) return
        if (prefs.authMode == CompanionAuthMode.SECURITY_CODE) {
            prefs.securityCode = code
        } else {
            prefs.lastPairingCode = code
        }
    }

    private fun applyAuthModeUi() {
        val security = prefs.authMode == CompanionAuthMode.SECURITY_CODE
        binding.authModeSecurity.isChecked = security
        binding.authModePairing.isChecked = !security
        binding.pairHintText.setText(
            if (security) R.string.pair_hint_security else R.string.pair_hint_pairing
        )
        binding.pairingCodeLayout.hint = if (security) "固定安全码（4～12 位）" else "配对码（6 位）"
        binding.connectButton.text = if (security) "连接（安全码）" else "连接 / 配对"
        // 切换模式时恢复对应字段
        val code = if (security) prefs.securityCode else prefs.lastPairingCode
        if (!code.isNullOrBlank()) {
            binding.pairingCodeInput.setText(code)
        } else if (!security) {
            binding.pairingCodeInput.text = null
        }
    }

    private fun confirmEnableAllMirror() {
        if (prefs.notificationMirrorMode == NotificationMirrorMode.ALL) {
            applyMirrorModeUi(fromUser = false)
            return
        }
        AlertDialog.Builder(this)
            .setTitle(R.string.mirror_all_confirm_title)
            .setMessage(R.string.mirror_all_confirm_message)
            .setPositiveButton("开启") { _, _ ->
                prefs.notificationMirrorMode = NotificationMirrorMode.ALL
                applyMirrorModeUi(fromUser = true)
                Toast.makeText(this, "已开启全部通知镜像", Toast.LENGTH_SHORT).show()
            }
            .setNegativeButton("取消") { _, _ ->
                applyMirrorModeUi(fromUser = false)
            }
            .setOnCancelListener {
                applyMirrorModeUi(fromUser = false)
            }
            .show()
    }

    private fun applyMirrorModeUi(fromUser: Boolean) {
        val all = prefs.notificationMirrorMode == NotificationMirrorMode.ALL
        suppressMirrorModeCallback = true
        binding.mirrorModeAll.isChecked = all
        binding.mirrorModeOtpOnly.isChecked = !all
        suppressMirrorModeCallback = false
        binding.mirrorModeHint.setText(
            if (all) R.string.mirror_mode_hint_all else R.string.mirror_mode_hint_otp
        )
        val access = OtpNotificationListener.enabledDetail(this)
        binding.mirrorModeSummary.text = if (all) {
            getString(R.string.mirror_summary_all) + " · " + access
        } else {
            getString(R.string.mirror_summary_otp) + " · " + access
        }
        if (fromUser) {
            // no-op; prefs already saved
        }
    }

    private fun connectFromForm(manual: Boolean) {
        val code = binding.pairingCodeInput.text?.toString()?.trim().orEmpty()
        val host = binding.hostOverrideInput.text?.toString()?.trim().orEmpty()
        if (host.isNotBlank()) {
            prefs.lastHostOverride = host
        }
        if (prefs.authMode == CompanionAuthMode.SECURITY_CODE) {
            if (code.isNotBlank()) {
                prefs.securityCode = code
            }
            val securityCode = prefs.securityCode
            val token = prefs.deviceToken
            if (securityCode.isNullOrBlank() && token.isNullOrBlank()) {
                if (manual) {
                    Toast.makeText(this, "请输入 Mac 上设定的固定安全码", Toast.LENGTH_SHORT).show()
                }
                return
            }
            CompanionSession.statusText = "正在连接（安全码）…"
            CompanionSession.notifyStatus()
            CompanionConnectionService.startConnect(
                this,
                pairingCode = if (token.isNullOrBlank()) securityCode else null,
                hostOverride = host.ifBlank { null },
                forceSecurityCode = securityCode
            )
        } else {
            if (code.isNotBlank()) prefs.lastPairingCode = code
            CompanionSession.statusText = "正在连接…"
            CompanionSession.notifyStatus()
            CompanionConnectionService.startConnect(
                this,
                pairingCode = code.ifBlank { null },
                hostOverride = host.ifBlank { null }
            )
        }
    }

    private fun maybeAutoConnect() {
        if (didAutoConnect) return
        if (CompanionSession.client.isConnected) return
        if (!prefs.canAutoConnect()) return
        didAutoConnect = true
        CompanionSession.statusText = "自动连接中…"
        CompanionSession.notifyStatus()
        updateLinkStatusUi(CompanionSession.statusText)
        connectFromForm(manual = false)
    }

    private fun restoreConnectionForm() {
        val code = if (prefs.authMode == CompanionAuthMode.SECURITY_CODE) {
            prefs.securityCode
        } else {
            prefs.lastPairingCode
        }
        if (!code.isNullOrBlank()) {
            binding.pairingCodeInput.setText(code)
        }
        val host = prefs.lastHostOverride?.takeIf { it.isNotBlank() }
            ?: prefs.hostPortLabel()
        if (!host.isNullOrBlank()) {
            binding.hostOverrideInput.setText(host)
        }
    }

    private fun rescanNotifications() {
        if (!OtpNotificationListener.isEnabled(this)) {
            Toast.makeText(this, "请先开启通知使用权", Toast.LENGTH_LONG).show()
            OtpNotificationListener.openSettings(this)
            return
        }
        binding.rescanNotifButton.isEnabled = false
        binding.lastOtpMetaText.text = "正在扫描通知栏…"
        OtpNotificationListener.rescanAndPushWithRetry(this) { hits ->
            binding.rescanNotifButton.isEnabled = true
            refreshOtpDisplay()
            when {
                hits > 0 -> {
                    Toast.makeText(this, "已从通知读取并推送", Toast.LENGTH_SHORT).show()
                    refreshOtpDisplay()
                }
                hits == 0 -> {
                    Toast.makeText(this, "通知栏没有识别到验证码通知", Toast.LENGTH_LONG).show()
                    binding.lastOtpMetaText.text = "未在通知栏找到验证码"
                }
                hits == -1 -> {
                    Toast.makeText(this, "请先开启通知使用权", Toast.LENGTH_LONG).show()
                    OtpNotificationListener.openSettings(this)
                }
                else -> {
                    // 重连仍失败
                    AlertDialog.Builder(this)
                        .setTitle("通知监听未连接")
                        .setMessage(
                            "设置里虽显示已开启，但系统尚未把监听服务连上（重装 App 后很常见）。\n\n" +
                                "请按下列步骤操作：\n" +
                                "1. 点「去设置」\n" +
                                "2. 关闭 Meo Companion / Meo 通知监听\n" +
                                "3. 再重新打开\n" +
                                "4. 返回 App，看状态是否变为「已开启且已连接」\n" +
                                "5. 再点「从通知栏重新读取并推送」"
                        )
                        .setPositiveButton("去设置") { _, _ ->
                            OtpNotificationListener.openSettings(this)
                        }
                        .setNegativeButton("取消", null)
                        .show()
                    binding.lastOtpMetaText.text = OtpNotificationListener.enabledDetail(this)
                }
            }
        }
    }

    private fun refreshOtpDisplay() {
        val code = CompanionSession.lastOtpCode
        if (code.isNotBlank()) {
            binding.lastOtpCodeText.text = code
            binding.lastOtpCodeText.setTypeface(null, Typeface.BOLD)
            val src = CompanionSession.lastOtpSource
            val event = CompanionSession.lastSmsEvent
            binding.lastOtpMetaText.text = buildString {
                if (src.isNotBlank()) append("来源：$src")
                if (event.isNotBlank()) {
                    if (isNotEmpty()) append(" · ")
                    append(event)
                }
            }.ifBlank { "已解析" }
        } else {
            binding.lastOtpCodeText.text = "——"
            binding.lastOtpMetaText.text = CompanionSession.lastSmsEvent.ifBlank {
                CompanionSession.lastOtpHint.takeIf { it != "无" } ?: "等待短信 / 通知验证码"
            }
        }
    }

    private fun readRecentOtpSms() {
        if (readingRecentOtp) return
        readingRecentOtp = true
        binding.readRecentOtpButton.isEnabled = false
        binding.recentOtpResultText.text = "正在读取收件箱…"

        lifecycleScope.launch {
            var error: String? = null
            val hit: RecentOtpSms? = withContext(Dispatchers.IO) {
                RecentSmsOtpReader.findLatest(applicationContext) { error = it }
            }
            readingRecentOtp = false
            binding.readRecentOtpButton.isEnabled = true

            if (hit == null) {
                val msg = error ?: "未知原因"
                binding.recentOtpResultText.text = "未读到验证码：$msg"
                AlertDialog.Builder(this@MainActivity)
                    .setTitle("未读到验证码")
                    .setMessage(msg)
                    .setPositiveButton("知道了", null)
                    .show()
                return@launch
            }
            val ageMs = System.currentTimeMillis() - hit.dateMs
            if (ageMs > 30L * 24 * 3600 * 1000) {
                binding.recentOtpResultText.text =
                    "只扫到很旧的验证码（${hit.dateLabel()}）\n发件人：${hit.address}\n验证码：${hit.code}"
                AlertDialog.Builder(this@MainActivity)
                    .setTitle("未读到今日验证码")
                    .setMessage(
                        "读到的是 ${hit.dateLabel()} 的旧短信。\n" +
                            "请用「从通知栏重新读取并推送」，或保持前台等新短信。"
                    )
                    .setPositiveButton("知道了", null)
                    .show()
                return@launch
            }
            showRecentOtpResult(hit)
        }
    }

    private fun showRecentOtpResult(hit: RecentOtpSms) {
        val summary =
            "解析成功 ✓\n" +
                "验证码：${hit.code}\n" +
                "发件人：${hit.address}\n" +
                "时间：${hit.dateLabel()}\n" +
                "摘要：${hit.bodyPreview()}"
        binding.recentOtpResultText.text = summary

        val connected = CompanionSession.client.isConnected
        val builder = AlertDialog.Builder(this)
            .setTitle("最近验证码短信")
            .setMessage(
                summary + "\n\n" +
                    if (connected) "可推送到已连接的 MeoBrowser。"
                    else "当前未连接 Mac，仅完成本地解析测试。"
            )
            .setNegativeButton("关闭", null)
        if (connected) {
            builder.setPositiveButton("推送到 Mac") { _, _ ->
                CompanionSession.pushOtp(this, hit.code)
                Toast.makeText(this, "已请求推送 ${hit.code}", Toast.LENGTH_SHORT).show()
            }
        }
        builder.show()
    }

    override fun onStart() {
        super.onStart()
        CompanionSession.addStatusListener(statusListener)
        refreshChecks()
        refreshOtpDisplay()
    }

    override fun onStop() {
        CompanionSession.removeStatusListener(statusListener)
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        updateLinkStatusUi(CompanionSession.statusText)
        refreshOtpDisplay()
        refreshChecks()
        binding.notifAccessHint.text = OtpNotificationListener.enabledDetail(this)
        binding.notifAccessButton.text = when {
            !OtpNotificationListener.isEnabled(this) ->
                "开启通知使用权（小米必开）"
            OtpNotificationListener.isConnected() ->
                "通知使用权已连接 ✓"
            else ->
                "通知使用权未连接（点此开关一次）"
        }
        applyMirrorModeUi(fromUser = false)
        OtpNotificationListener.ensureBound(this)
        // 从向导返回或再次进入前台时，安全码模式补一次自动连接
        if (!SetupChecker.shouldAutoShowWizard(this)) {
            maybeAutoConnect()
        }
    }

    private fun setupToolbar() {
        binding.linkToolbar.title = getString(R.string.settings_section_link)
        binding.linkToolbar.setNavigationIcon(androidx.appcompat.R.drawable.abc_ic_ab_back_material)
        binding.linkToolbar.navigationIcon?.let { icon ->
            DrawableCompat.setTint(DrawableCompat.wrap(icon.mutate()), 0xFF1C1C1E.toInt())
        }
        binding.linkToolbar.setNavigationOnClickListener {
            onBackPressedDispatcher.onBackPressed()
        }
    }

    private fun updateLinkStatusUi(status: String) {
        if (!::binding.isInitialized) return
        val state = LinkConnectionState.from(status, CompanionSession.client.isConnected)
        binding.linkStatusTitle.text = state.title
        binding.statusText.text = status.ifBlank { state.title }
        applyStatusDot(binding.linkStatusCardDot, state.dotColor)
        binding.linkStatusIconBg.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(state.iconBackgroundColor)
        }
        val connected = state == LinkConnectionState.CONNECTED
        val connecting = state == LinkConnectionState.CONNECTING
        binding.connectButton.isEnabled = !connecting
        binding.disconnectButton.isEnabled = connected || connecting
        binding.connectButton.alpha = if (connecting) 0.5f else 1f
        binding.disconnectButton.alpha = if (connected || connecting) 1f else 0.45f
    }

    private fun applyStatusDot(view: View, color: Int) {
        val stroke = (1.5f * resources.displayMetrics.density).toInt().coerceAtLeast(2)
        view.background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(stroke, 0xFFFFFFFF.toInt())
        }
    }

    private fun refreshChecks() {
        if (!::binding.isInitialized) return
        val items = SetupChecker.allItems(this)
        val failed = items.filter { !it.ok }
        binding.readinessSummary.text = SetupChecker.readinessSummary(this)
        binding.checklistContainer.removeAllViews()

        val toShow = if (showAllChecks) items else failed
        for (item in toShow) {
            binding.checklistContainer.addView(makeCheckRow(item))
        }
        binding.checksEmptyHint.visibility =
            if (!showAllChecks && failed.isEmpty()) View.VISIBLE else View.GONE
        binding.toggleChecksButton.text = if (showAllChecks) "只看未通过" else "展开全部"
        // 全部通过时向导按钮弱化，未通过时更明显
        binding.setupWizardButton.visibility =
            if (failed.isEmpty() && !showAllChecks) View.GONE else View.VISIBLE
    }

    private fun makeCheckRow(item: SetupCheckItem): TextView {
        val mark = if (item.ok) "✓" else "✗"
        val req = if (item.required) "必填" else "建议"
        val tv = TextView(this)
        tv.text = "$mark [${req}] ${item.title}\n   ${item.detail}"
        tv.textSize = 13f
        tv.setPadding(0, 10, 0, 10)
        tv.setTypeface(null, if (item.ok) Typeface.NORMAL else Typeface.BOLD)
        tv.setOnClickListener {
            when (item.id) {
                SetupItemId.NOTIF_ACCESS -> OtpNotificationListener.openSettings(this)
                else -> SetupWizardActivity.start(this)
            }
        }
        return tv
    }
}
