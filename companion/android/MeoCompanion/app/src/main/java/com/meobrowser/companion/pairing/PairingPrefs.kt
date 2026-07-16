package com.meobrowser.companion.pairing

import android.content.Context
import java.util.UUID

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
    }
}
