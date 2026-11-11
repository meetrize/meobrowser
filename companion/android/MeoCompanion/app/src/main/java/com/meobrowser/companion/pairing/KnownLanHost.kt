package com.meobrowser.companion.pairing

import org.json.JSONArray
import org.json.JSONObject

/** 局域网已发现 / 已连接过的 Mac 主机。 */
data class KnownLanHost(
    val host: String,
    val port: Int,
    val name: String,
    val lastSeenAt: Long = System.currentTimeMillis()
) {
    fun endpoint(): String = "$host:$port"

    fun toJson(): JSONObject = JSONObject()
        .put("host", host)
        .put("port", port)
        .put("name", name)
        .put("lastSeenAt", lastSeenAt)

    companion object {
        fun fromJson(obj: JSONObject): KnownLanHost? {
            val host = obj.optString("host")
            val port = obj.optInt("port", 0)
            if (host.isBlank() || port <= 0) return null
            val name = obj.optString("name").ifBlank { "MeoBrowser" }
            val lastSeenAt = obj.optLong("lastSeenAt", System.currentTimeMillis())
            return KnownLanHost(host, port, name, lastSeenAt)
        }

        fun encodeList(list: List<KnownLanHost>): String {
            val arr = JSONArray()
            for (item in list) arr.put(item.toJson())
            return arr.toString()
        }

        fun decodeList(raw: String?): List<KnownLanHost> {
            if (raw.isNullOrBlank()) return emptyList()
            return try {
                val arr = JSONArray(raw)
                (0 until arr.length()).mapNotNull { fromJson(arr.getJSONObject(it)) }
            } catch (_: Exception) {
                emptyList()
            }
        }
    }
}
