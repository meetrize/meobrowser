package com.meobrowser.companion.ui

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import com.meobrowser.companion.channel.CompanionConnectionService
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.databinding.ActivitySetupWizardBinding
import com.meobrowser.companion.pairing.CompanionAuthMode
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.setup.SetupChecker
import com.meobrowser.companion.sms.OtpNotificationListener

/**
 * 分步设置向导：短信 → 通知使用权 → 通知/电池 → Wi‑Fi → 配对。
 */
class SetupWizardActivity : AppCompatActivity() {
    private lateinit var binding: ActivitySetupWizardBinding
    private var step = 0

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) {
        refreshStepUi()
    }

    private val batteryLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        refreshStepUi()
    }

    private val statusListener: (String, String) -> Unit = { _, _ ->
        runOnUiThread { refreshStepUi() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivitySetupWizardBinding.inflate(layoutInflater)
        setContentView(binding.root)

        binding.wizardBackButton.setOnClickListener {
            if (step > 0) {
                step--
                refreshStepUi()
            }
        }
        binding.wizardNextButton.setOnClickListener {
            if (step < LAST_STEP) {
                step++
                refreshStepUi()
            } else {
                finishWizard()
            }
        }
        binding.wizardSkipButton.setOnClickListener {
            SetupChecker.markWizardDone(this)
            finish()
        }
        binding.wizardActionButton.setOnClickListener { onActionClicked() }

        refreshStepUi()
    }

    override fun onStart() {
        super.onStart()
        CompanionSession.addStatusListener(statusListener)
    }

    override fun onStop() {
        CompanionSession.removeStatusListener(statusListener)
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        refreshStepUi()
    }

    override fun onDestroy() {
        CompanionSession.removeStatusListener(statusListener)
        super.onDestroy()
    }

    private fun refreshStepUi() {
        binding.wizardProgress.max = LAST_STEP + 1
        binding.wizardProgress.progress = step + 1
        binding.wizardStepLabel.text = "步骤 ${step + 1}/${LAST_STEP + 1}"
        binding.wizardBackButton.isEnabled = step > 0
        binding.wizardPairingLayout.visibility = View.GONE
        binding.wizardHostLayout.visibility = View.GONE

        when (step) {
            0 -> {
                binding.wizardHeadline.text = "欢迎使用 Meo Companion"
                binding.wizardBody.text =
                    "本向导会帮你完成短信自动推码所需设置：\n\n" +
                        "1. 短信权限\n" +
                        "2. 通知使用权（小米服务号验证码必开）\n" +
                        "3. 通知权限 / 电池优化\n" +
                        "4. Wi‑Fi 与 Mac 配对\n\n" +
                        "隐私：默认只上传验证码与时间戳，不上传短信全文。"
                binding.wizardStatus.text = SetupChecker.readinessSummary(this)
                binding.wizardActionButton.text = "开始检测"
                binding.wizardNextButton.text = "下一步"
            }
            1 -> {
                val ok = SetupChecker.hasSmsPermission(this)
                binding.wizardHeadline.text = "① 短信权限"
                binding.wizardBody.text =
                    "需要「接收短信」和「读取短信」权限。\n\n" +
                        "小米上【深度求索】等服务号往往仍读不到收件箱，下一步的「通知使用权」才是关键。"
                binding.wizardStatus.text = if (ok) "状态：已授予 ✓" else "状态：未授予 ✗"
                binding.wizardActionButton.text = if (ok) "已完成，可下一步" else "授予短信权限"
                binding.wizardNextButton.text = "下一步"
            }
            2 -> {
                val ok = OtpNotificationListener.isEnabled(this)
                binding.wizardHeadline.text = "② 通知使用权（小米必开）"
                binding.wizardBody.text =
                    "小米会把服务号短信放进「智能短信」，第三方读不到短信库，也收不到短信广播。\n\n" +
                        "请开启「通知使用权 / 通知读取」：系统会列出「Meo Companion」或「Meo 通知监听」，打开开关。\n\n" +
                        "开启后，通知栏出现验证码时会自动解析并推送到 Mac。"
                binding.wizardStatus.text = if (ok) "状态：已开启 ✓" else "状态：未开启 ✗"
                binding.wizardActionButton.text = if (ok) "已完成，可下一步" else "打开通知使用权设置"
                binding.wizardNextButton.text = "下一步"
            }
            3 -> {
                val ok = SetupChecker.hasNotificationPermission(this)
                binding.wizardHeadline.text = "③ 通知权限"
                binding.wizardBody.text =
                    "Android 13+ 需要通知权限，以便显示「连接中」前台服务。\n" +
                        "较低版本系统可直接下一步。"
                binding.wizardStatus.text = if (ok) "状态：已就绪 ✓" else "状态：未授予 ✗"
                binding.wizardActionButton.text = if (ok) "已完成，可下一步" else "授予通知权限"
                binding.wizardNextButton.text = "下一步"
            }
            4 -> {
                val ok = SetupChecker.isIgnoringBatteryOptimizations(this)
                binding.wizardHeadline.text = "④ 电池优化"
                binding.wizardBody.text =
                    "请将 Meo Companion 加入省电白名单 /「不优化」。\n\n" +
                        "小米建议额外开启：自启动、后台运行，并在多任务里锁定本 App。"
                binding.wizardStatus.text = if (ok) "状态：已忽略电池优化 ✓" else "状态：仍受省电限制 ✗"
                binding.wizardActionButton.text = if (ok) "已完成，可下一步" else "打开电池设置"
                binding.wizardNextButton.text = "下一步"
            }
            5 -> {
                val ok = SetupChecker.isWifiConnected(this)
                binding.wizardHeadline.text = "⑤ 确认局域网"
                binding.wizardBody.text =
                    "手机与运行 MeoBrowser 的 Mac 需在同一 Wi‑Fi（或可互通的局域网）。\n\n" +
                        "可在 MeoBrowser「登录助手」底部查看配对码与端口；若 Bonjour 发现失败，可在下一步填写 MacIP:端口。"
                binding.wizardStatus.text = if (ok) "状态：已连接 Wi‑Fi ✓" else "状态：未检测到 Wi‑Fi ✗"
                binding.wizardActionButton.text = "打开无线局域网设置"
                binding.wizardNextButton.text = "下一步"
            }
            else -> {
                val connected = CompanionSession.client.isConnected
                val prefs = PairingPrefs(this)
                val security = prefs.authMode == CompanionAuthMode.SECURITY_CODE
                binding.wizardHeadline.text = "⑥ 配对 MeoBrowser"
                binding.wizardBody.text = if (security) {
                    "1. Mac「登录助手」切换到「固定安全码」并保存安全码\n" +
                        "2. 本页填写相同安全码与主机 IP:端口\n" +
                        "3. 连接成功后，以后打开 App 会自动连接\n\n" +
                        "也可在主界面切换「临时配对码 / 固定安全码」。"
                } else {
                    "1. Mac 打开「文件 → 登录助手…」\n" +
                        "2. 底部查看配对码（新设备可点「刷新配对码」）\n" +
                        "3. 在下方输入配对码并连接\n\n" +
                        "日常建议改用「固定安全码」模式，打开即可自动连接。"
                }
                binding.wizardStatus.text = "状态：${CompanionSession.statusText}"
                binding.wizardPairingLayout.visibility = View.VISIBLE
                binding.wizardHostLayout.visibility = View.VISIBLE
                binding.wizardPairingLayout.hint = if (security) "固定安全码" else "配对码（6 位）"
                binding.wizardActionButton.text = if (connected) "已连接，完成向导" else "连接 / 配对"
                binding.wizardNextButton.text = "完成"
            }
        }
    }

    private fun onActionClicked() {
        when (step) {
            0 -> {
                step = 1
                refreshStepUi()
            }
            1 -> {
                if (SetupChecker.hasSmsPermission(this)) {
                    step = 2
                    refreshStepUi()
                } else {
                    permissionLauncher.launch(
                        arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS)
                    )
                }
            }
            2 -> {
                if (OtpNotificationListener.isEnabled(this)) {
                    step = 3
                    refreshStepUi()
                } else {
                    OtpNotificationListener.openSettings(this)
                }
            }
            3 -> {
                if (SetupChecker.hasNotificationPermission(this)) {
                    step = 4
                    refreshStepUi()
                } else if (Build.VERSION.SDK_INT >= 33) {
                    permissionLauncher.launch(arrayOf(Manifest.permission.POST_NOTIFICATIONS))
                } else {
                    step = 4
                    refreshStepUi()
                }
            }
            4 -> {
                if (SetupChecker.isIgnoringBatteryOptimizations(this)) {
                    step = 5
                    refreshStepUi()
                } else {
                    requestBatteryExemption()
                }
            }
            5 -> {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            }
            else -> {
                if (CompanionSession.client.isConnected) {
                    finishWizard()
                } else {
                    val prefs = PairingPrefs(this)
                    val code = binding.wizardPairingInput.text?.toString()?.trim().orEmpty()
                    val host = binding.wizardHostInput.text?.toString()?.trim().orEmpty()
                    val security = prefs.authMode == CompanionAuthMode.SECURITY_CODE
                    if (code.isBlank() && !SetupChecker.hasDeviceToken(this)) {
                        Toast.makeText(
                            this,
                            if (security) "请输入 Mac 上的固定安全码" else "请输入 Mac 上的 6 位配对码",
                            Toast.LENGTH_SHORT
                        ).show()
                        return
                    }
                    if (host.isNotBlank()) prefs.lastHostOverride = host
                    if (code.isNotBlank()) {
                        if (security) prefs.securityCode = code else prefs.lastPairingCode = code
                    }
                    CompanionConnectionService.startConnect(
                        this,
                        pairingCode = code.ifBlank { null },
                        hostOverride = host.ifBlank { null },
                        forceSecurityCode = if (security) prefs.securityCode else null
                    )
                    Toast.makeText(this, "正在连接…", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun requestBatteryExemption() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            refreshStepUi()
            return
        }
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            batteryLauncher.launch(intent)
        } catch (_: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {
                openAppSettings()
            }
        }
    }

    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            )
        )
    }

    private fun finishWizard() {
        SetupChecker.markWizardDone(this)
        Toast.makeText(this, "设置完成。可回首页查看就绪状态。", Toast.LENGTH_LONG).show()
        finish()
    }

    companion object {
        private const val LAST_STEP = 6

        fun start(activity: AppCompatActivity) {
            activity.startActivity(Intent(activity, SetupWizardActivity::class.java))
        }
    }
}
