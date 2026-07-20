package com.meobrowser.companion.pairing

import android.content.Context
import java.util.UUID

enum class CompanionAuthMode {
    PAIRING_CODE,
    SECURITY_CODE;

    companion object {
        fun fromStorage(value: String?): CompanionAuthMode {
            return if (value == SECURITY_CODE.name) SECURITY_CODE else PAIRING_CODE
        }
    }
}

/** 通知镜像模式：默认仅验证码。 */
enum class NotificationMirrorMode {
    OTP_ONLY,
    ALL;

    companion object {
        fun fromStorage(value: String?): NotificationMirrorMode {
            return if (value == ALL.name) ALL else OTP_ONLY
        }
    }
}

class PairingPrefs(context: Context) {
    private val prefs = context.getSharedPreferences("meo_companion", Context.MODE_PRIVATE)

    var deviceId: String
        get() {
            val existing = prefs.getString(KEY_DEVICE_ID, null)
            if (!existing.isNullOrBlank()) return existing
            val created = UUID.randomUUID().toString()
            prefs.edit().putString(KEY_DEVICE_ID, created).apply()
            return created
        }
        set(value) = prefs.edit().putString(KEY_DEVICE_ID, value).apply()

    var deviceToken: String?
        get() = prefs.getString(KEY_DEVICE_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_DEVICE_TOKEN, value).apply()

    var lastHost: String?
        get() = prefs.getString(KEY_LAST_HOST, null)
        set(value) = prefs.edit().putString(KEY_LAST_HOST, value).apply()

    var lastPort: Int
        get() = prefs.getInt(KEY_LAST_PORT, 0)
        set(value) = prefs.edit().putInt(KEY_LAST_PORT, value).apply()

    /** 上次成功连接时填写的配对码（便于再次输入） */
    var lastPairingCode: String?
        get() = prefs.getString(KEY_LAST_PAIRING_CODE, null)
        set(value) = prefs.edit().putString(KEY_LAST_PAIRING_CODE, value).apply()

    /** 固定安全码（安全码模式） */
    var securityCode: String?
        get() = prefs.getString(KEY_SECURITY_CODE, null)
        set(value) = prefs.edit().putString(KEY_SECURITY_CODE, value).apply()

    var authMode: CompanionAuthMode
        get() = CompanionAuthMode.fromStorage(prefs.getString(KEY_AUTH_MODE, null))
        set(value) = prefs.edit().putString(KEY_AUTH_MODE, value.name).apply()

    /** 通知镜像：仅验证码（默认）/ 全部通知 */
    var notificationMirrorMode: NotificationMirrorMode
        get() = NotificationMirrorMode.fromStorage(prefs.getString(KEY_NOTIF_MIRROR_MODE, null))
        set(value) = prefs.edit().putString(KEY_NOTIF_MIRROR_MODE, value.name).apply()

    /** 启动浏览器时是否自动连接（默认开） */
    var autoConnectOnLaunch: Boolean
        get() = prefs.getBoolean(KEY_AUTO_CONNECT, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_CONNECT, value).apply()

    /** 上次在表单里填写的手动主机，如 192.168.1.10:12345 */
    var lastHostOverride: String?
        get() = prefs.getString(KEY_LAST_HOST_OVERRIDE, null)
        set(value) = prefs.edit().putString(KEY_LAST_HOST_OVERRIDE, value).apply()

    fun hostPortLabel(): String? {
        val host = lastHost
        val port = lastPort
        if (!host.isNullOrBlank() && port > 0) return "$host:$port"
        return lastHostOverride
    }

    fun hasSavedHost(): Boolean =
        (!lastHost.isNullOrBlank() && lastPort > 0) || !lastHostOverride.isNullOrBlank()

    /** 安全码模式下是否具备自动连接条件（兼容旧调用） */
    fun canAutoConnectSecurityMode(): Boolean {
        if (authMode != CompanionAuthMode.SECURITY_CODE) return false
        val hasCred = !deviceToken.isNullOrBlank() || !securityCode.isNullOrBlank()
        return hasCred && hasSavedHost()
    }

    /**
     * 是否应自动连接：开关默认开；已保存主机，且有 deviceToken 或（安全码模式+安全码）。
     * 配对码模式成功后也会靠 token 自动重连。
     */
    fun canAutoConnect(): Boolean {
        if (!autoConnectOnLaunch) return false
        if (!hasSavedHost()) return false
        if (!deviceToken.isNullOrBlank()) return true
        return authMode == CompanionAuthMode.SECURITY_CODE && !securityCode.isNullOrBlank()
    }

    fun clearSession() {
        prefs.edit()
            .remove(KEY_DEVICE_TOKEN)
            .remove(KEY_LAST_HOST)
            .remove(KEY_LAST_PORT)
            .apply()
    }

    companion object {
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_DEVICE_TOKEN = "device_token"
        private const val KEY_LAST_HOST = "last_host"
        private const val KEY_LAST_PORT = "last_port"
        private const val KEY_LAST_PAIRING_CODE = "last_pairing_code"
        private const val KEY_LAST_HOST_OVERRIDE = "last_host_override"
        private const val KEY_AUTH_MODE = "auth_mode"
        private const val KEY_SECURITY_CODE = "security_code"
        private const val KEY_NOTIF_MIRROR_MODE = "notification_mirror_mode"
        private const val KEY_AUTO_CONNECT = "auto_connect_on_launch"
    }
}
