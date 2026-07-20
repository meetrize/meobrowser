package com.meobrowser.companion.browser.newtab

import android.content.Context
import android.net.Uri
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class ShortcutItem(
    val id: String = UUID.randomUUID().toString(),
    var title: String,
    var url: String,
    var order: Int,
    var kind: String = "link",
    var folderId: String = "",
    var iconURL: String = "",
    var updatedAt: Long = System.currentTimeMillis() / 1000,
    var deviceId: String = "",
    var deleted: Boolean = false
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("url", url)
        put("order", order)
        put("kind", kind)
        put("folderId", folderId)
        put("iconURL", iconURL)
        put("updatedAt", updatedAt)
        put("deviceId", deviceId)
        put("deleted", deleted)
    }

    companion object {
        fun fromJson(o: JSONObject): ShortcutItem = ShortcutItem(
            id = o.optString("id", UUID.randomUUID().toString()),
            title = o.optString("title"),
            url = o.optString("url"),
            order = o.optInt("order"),
            kind = o.optString("kind", "link"),
            folderId = o.optString("folderId"),
            iconURL = o.optString("iconURL"),
            updatedAt = o.optLong("updatedAt", System.currentTimeMillis() / 1000),
            deviceId = o.optString("deviceId"),
            deleted = o.optBoolean("deleted", false)
        )
    }
}

class ShortcutStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val deviceIdPrefs = context.getSharedPreferences("meo_companion", Context.MODE_PRIVATE)

    fun deviceId(): String {
        val existing = deviceIdPrefs.getString("device_id", null)
        if (!existing.isNullOrBlank()) return existing
        val created = UUID.randomUUID().toString()
        deviceIdPrefs.edit().putString("device_id", created).apply()
        return created
    }

    fun loadActive(): List<ShortcutItem> {
        demoteLegacyFactoryDefaultsIfNeeded()
        val all = loadAll()
        if (all.isEmpty()) {
            val defaults = defaultShortcuts()
            saveAll(defaults)
            return defaults.filter { !it.deleted }
        }
        return all.filter { !it.deleted }.sortedBy { it.order }
    }

    /**
     * 旧版把出厂 4 个站点写成「当前时间戳」，同步时会盖过 Mac。
     * 若本地仍几乎只有这 4 个默认站，则降权以便合并 Mac 数据。
     */
    private fun demoteLegacyFactoryDefaultsIfNeeded() {
        if (prefs.getBoolean(KEY_DEMOTED, false)) return
        val active = loadAll().filter { !it.deleted }
        if (active.isEmpty()) {
            prefs.edit().putBoolean(KEY_DEMOTED, true).apply()
            return
        }
        val hosts = active.map { normalizeUrlKey(it.url).substringBefore('/') }.toSet()
        val factory = setOf("github.com", "google.com", "wikipedia.org", "stackoverflow.com")
        val onlyFactory = hosts.isNotEmpty() && hosts.all { it in factory } && active.size <= 4
        if (onlyFactory) {
            val demoted = loadAll().map { item ->
                if (item.deleted) item
                else item.copy(updatedAt = 1L, id = if (item.id.startsWith("seed-")) item.id else "seed-legacy-${normalizeUrlKey(item.url).substringBefore('/')}")
            }
            saveAll(demoted)
            Log.i("ShortcutStore", "demoted legacy factory defaults count=${demoted.size}")
        }
        prefs.edit().putBoolean(KEY_DEMOTED, true).apply()
    }

    fun loadAll(): List<ShortcutItem> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { ShortcutItem.fromJson(arr.getJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun saveAll(items: List<ShortcutItem>) {
        val arr = JSONArray()
        items.forEach { arr.put(it.toJson()) }
        // commit：同步落盘，避免紧接着 push 读到旧数据
        prefs.edit().putString(KEY, arr.toString()).commit()
    }

    fun upsert(item: ShortcutItem) {
        val list = loadAll().toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        val stamped = item.copy(
            updatedAt = System.currentTimeMillis() / 1000,
            deviceId = deviceId()
        )
        if (idx >= 0) list[idx] = stamped else list.add(stamped)
        saveAll(list)
    }

    fun softDelete(id: String) {
        val list = loadAll().toMutableList()
        val idx = list.indexOfFirst { it.id == id }
        if (idx < 0) return
        list[idx] = list[idx].copy(
            deleted = true,
            updatedAt = System.currentTimeMillis() / 1000,
            deviceId = deviceId()
        )
        saveAll(list)
    }

    /**
     * 按 id LWW 合并；同 URL 去重（避免手机默认 GitHub 与 Mac GitHub 各留一份）。
     * @return 合并后仍可见的条数
     */
    fun mergeRemote(records: List<ShortcutItem>): Int {
        val map = loadAll().associateBy { it.id }.toMutableMap()
        for (incoming in records) {
            if (incoming.id.isBlank()) continue
            val local = map[incoming.id]
            if (local == null) {
                map[incoming.id] = incoming
            } else if (wins(incoming, local)) {
                map[incoming.id] = incoming
            }
        }
        // URL 去重：同规范 URL 只留一条。手机预置 seed 永远让给 Mac/用户数据。
        val active = map.values.filter { !it.deleted && it.kind != "folder" }
        val byUrl = linkedMapOf<String, ShortcutItem>()
        for (item in active) {
            val key = normalizeUrlKey(item.url)
            if (key.isBlank()) continue
            val existing = byUrl[key]
            if (existing == null) {
                byUrl[key] = item
                continue
            }
            val winner = when {
                isWeakSeed(existing) && !isWeakSeed(item) -> item
                isWeakSeed(item) && !isWeakSeed(existing) -> existing
                wins(item, existing) -> item
                else -> existing
            }
            val loser = if (winner.id == item.id) existing else item
            map[loser.id] = loser.copy(
                deleted = true,
                updatedAt = maxOf(existing.updatedAt, item.updatedAt) + 1,
                deviceId = winner.deviceId.ifBlank { deviceId() }
            )
            byUrl[key] = winner
            map[winner.id] = winner
        }
        saveAll(map.values.toList())
        return map.values.count { !it.deleted }
    }

    fun replaceOrder(ordered: List<ShortcutItem>) {
        val now = System.currentTimeMillis() / 1000
        val did = deviceId()
        val updated = ordered.mapIndexed { i, item ->
            item.copy(order = i, updatedAt = now, deviceId = did, deleted = false)
        }
        val deleted = loadAll().filter { it.deleted }
        saveAll(updated + deleted)
    }

    private fun wins(a: ShortcutItem, b: ShortcutItem): Boolean {
        if (a.updatedAt > b.updatedAt) return true
        if (a.updatedAt < b.updatedAt) return false
        return a.deviceId > b.deviceId
    }

    /** 手机出厂预置项：同步时优先让位给 Mac 真实数据 */
    private fun isWeakSeed(item: ShortcutItem): Boolean {
        if (item.id.startsWith("seed-")) return true
        if (item.updatedAt in 1L..10L) return true
        return false
    }

    private fun normalizeUrlKey(url: String): String {
        return try {
            val u = Uri.parse(url.trim())
            val host = (u.host ?: "").lowercase().removePrefix("www.")
            val path = (u.path ?: "").trimEnd('/').ifBlank { "" }
            "$host$path"
        } catch (_: Exception) {
            url.trim().lowercase()
        }
    }

    private fun defaultShortcuts(): List<ShortcutItem> {
        val did = deviceId()
        // 低时间戳：避免首次同步时用「现在」覆盖 Mac 上更真实的快捷方式
        val seedTs = 1L
        val sites = listOf(
            "GitHub" to "https://github.com",
            "Google" to "https://www.google.com",
            "Wikipedia" to "https://www.wikipedia.org",
            "Stack Overflow" to "https://stackoverflow.com"
        )
        return sites.mapIndexed { i, (t, u) ->
            ShortcutItem(
                id = "seed-$i-${u.hashCode()}",
                title = t,
                url = u,
                order = i,
                updatedAt = seedTs,
                deviceId = did
            )
        }
    }

    companion object {
        private const val PREFS = "meo_shortcuts"
        private const val KEY = "items_v1"
        private const val KEY_DEMOTED = "factory_defaults_demoted_v1"
    }
}
