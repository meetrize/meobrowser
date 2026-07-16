package com.meobrowser.companion.setup

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.PowerManager
import androidx.core.content.ContextCompat
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.pairing.PairingPrefs
import com.meobrowser.companion.sms.OtpNotificationListener

enum class SetupItemId {
    SMS,
    NOTIF_ACCESS,
    NOTIFICATION,
    BATTERY,
    WIFI,
    PAIRED,
}

data class SetupCheckItem(
    val id: SetupItemId,
    val title: String,
    val detail: String,
    val ok: Boolean,
    val required: Boolean,
)

object SetupChecker {

    fun hasSmsPermission(context: Context): Boolean {
        val receive = ContextCompat.checkSelfPermission(context, Manifest.permission.RECEIVE_SMS) ==
            PackageManager.PERMISSION_GRANTED
        val read = ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED
        return receive && read
    }

    fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun isWifiConnected(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    fun isPairedOrConnected(context: Context): Boolean {
        val prefs = PairingPrefs(context)
        if (!prefs.deviceToken.isNullOrBlank() && CompanionSession.client.isConnected) {
            return true
        }
        return CompanionSession.client.isConnected &&
            CompanionSession.statusText.contains("已配对")
    }

    fun hasDeviceToken(context: Context): Boolean {
        return !PairingPrefs(context).deviceToken.isNullOrBlank()
    }

    fun allItems(context: Context): List<SetupCheckItem> {
        return listOf(
            SetupCheckItem(
                id = SetupItemId.SMS,
                title = "短信权限",
                detail = if (hasSmsPermission(context)) {
                    "已授予，可拦截普通短信验证码"
                } else {
                    "未授予，无法自动解析短信验证码"
                },
                ok = hasSmsPermission(context),
                required = true,
            ),
            SetupCheckItem(
                id = SetupItemId.NOTIF_ACCESS,
                title = "通知使用权（小米必开）",
                detail = OtpNotificationListener.enabledDetail(context),
                ok = OtpNotificationListener.isEnabled(context),
                required = true,
            ),
            SetupCheckItem(
                id = SetupItemId.NOTIFICATION,
                title = "通知权限",
                detail = if (hasNotificationPermission(context)) {
                    "已授予，连接时可显示前台状态"
                } else {
                    "未授予，前台服务通知可能被隐藏"
                },
                ok = hasNotificationPermission(context),
                required = Build.VERSION.SDK_INT >= 33,
            ),
            SetupCheckItem(
                id = SetupItemId.BATTERY,
                title = "电池优化白名单",
                detail = if (isIgnoringBatteryOptimizations(context)) {
                    "已忽略优化，后台收短信更稳定"
                } else {
                    "仍受省电限制，国产机上短信广播易被杀"
                },
                ok = isIgnoringBatteryOptimizations(context),
                required = false,
            ),
            SetupCheckItem(
                id = SetupItemId.WIFI,
                title = "局域网 / Wi‑Fi",
                detail = if (isWifiConnected(context)) {
                    "当前在 Wi‑Fi（或有线）网络上"
                } else {
                    "未检测到 Wi‑Fi，Bonjour 配对通常需要同网段"
                },
                ok = isWifiConnected(context),
                required = true,
            ),
            SetupCheckItem(
                id = SetupItemId.PAIRED,
                title = "与 Mac 配对连接",
                detail = when {
                    CompanionSession.client.isConnected -> "已连接：${CompanionSession.statusText}"
                    hasDeviceToken(context) -> "已保存配对，但当前未连接，请回首页点「连接」"
                    else -> "尚未配对，请在向导或首页输入 MeoBrowser 配对码"
                },
                ok = CompanionSession.client.isConnected,
                required = true,
            ),
        )
    }

    fun readinessSummary(context: Context): String {
        val items = allItems(context)
        val okCount = items.count { it.ok }
        val requiredMissing = items.filter { it.required && !it.ok }
        return if (requiredMissing.isEmpty()) {
            "就绪 $okCount/${items.size}：可自动拦截短信并推码"
        } else {
            "未就绪：还缺「${requiredMissing.joinToString("、") { it.title }}」"
        }
    }

    fun shouldAutoShowWizard(context: Context): Boolean {
        val prefs = context.getSharedPreferences("meo_companion", Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_WIZARD_DONE, false)) {
            return false
        }
        val requiredMissing = allItems(context).any { it.required && !it.ok }
        return requiredMissing
    }

    fun markWizardDone(context: Context) {
        context.getSharedPreferences("meo_companion", Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_WIZARD_DONE, true)
            .apply()
    }

    private const val KEY_WIZARD_DONE = "setup_wizard_done"
}
