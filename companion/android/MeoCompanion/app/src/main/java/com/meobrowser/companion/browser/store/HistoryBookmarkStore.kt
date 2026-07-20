package com.meobrowser.companion.browser.store

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

data class HistoryEntry(
    val id: String = UUID.randomUUID().toString(),
    val url: String,
    val title: String,
    val visitTime: Long = System.currentTimeMillis() / 1000,
    val visitCount: Int = 1,
    var updatedAt: Long = System.currentTimeMillis() / 1000,
    var deviceId: String = "",
    var deleted: Boolean = false
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("url", url)
        put("title", title)
        put("visitTime", visitTime)
        put("visitCount", visitCount)
        put("updatedAt", updatedAt)
        put("deviceId", deviceId)
        put("deleted", deleted)
    }

    companion object {
        fun fromJson(o: JSONObject) = HistoryEntry(
            id = o.optString("id", UUID.randomUUID().toString()),
            url = o.optString("url"),
            title = o.optString("title"),
            visitTime = o.optLong("visitTime"),
            visitCount = o.optInt("visitCount", 1),
            updatedAt = o.optLong("updatedAt"),
            deviceId = o.optString("deviceId"),
            deleted = o.optBoolean("deleted", false)
        )
    }
}

class HistoryStore(context: Context, private val maxEntries: Int = 500) {
    private val prefs = context.getSharedPreferences("meo_history", Context.MODE_PRIVATE)

    fun loadActive(): List<HistoryEntry> =
        loadAll().filter { !it.deleted }.sortedByDescending { it.visitTime }

    fun loadAll(): List<HistoryEntry> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { HistoryEntry.fromJson(arr.getJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun record(url: String, title: String, deviceId: String) {
        if (url.startsWith("about:")) return
        val list = loadAll().toMutableList()
        val existing = list.indexOfFirst { it.url == url && !it.deleted }
        val now = System.currentTimeMillis() / 1000
        if (existing >= 0) {
            val e = list[existing]
            list[existing] = e.copy(
                title = title.ifBlank { e.title },
                visitTime = now,
                visitCount = e.visitCount + 1,
                updatedAt = now,
                deviceId = deviceId
            )
        } else {
            list.add(
                HistoryEntry(
                    url = url,
                    title = title.ifBlank { url },
                    visitTime = now,
                    updatedAt = now,
                    deviceId = deviceId
                )
            )
        }
        val active = list.filter { !it.deleted }.sortedByDescending { it.visitTime }.take(maxEntries)
        val deleted = list.filter { it.deleted }
        saveAll(active + deleted)
    }

    fun mergeRemote(records: List<HistoryEntry>) {
        val map = loadAll().associateBy { it.id }.toMutableMap()
        for (incoming in records) {
            val local = map[incoming.id]
            if (local == null) map[incoming.id] = incoming
            else if (incoming.updatedAt > local.updatedAt ||
                (incoming.updatedAt == local.updatedAt && incoming.deviceId > local.deviceId)
            ) {
                map[incoming.id] = incoming
            }
        }
        saveAll(map.values.toList())
    }

    private fun saveAll(items: List<HistoryEntry>) {
        val arr = JSONArray()
        items.forEach { arr.put(it.toJson()) }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    companion object {
        private const val KEY = "items_v1"
    }
}

data class BookmarkEntry(
    val id: String = UUID.randomUUID().toString(),
    var title: String,
    var url: String,
    var order: Int = 0,
    var updatedAt: Long = System.currentTimeMillis() / 1000,
    var deviceId: String = "",
    var deleted: Boolean = false
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("title", title)
        put("url", url)
        put("order", order)
        put("updatedAt", updatedAt)
        put("deviceId", deviceId)
        put("deleted", deleted)
    }

    companion object {
        fun fromJson(o: JSONObject) = BookmarkEntry(
            id = o.optString("id", UUID.randomUUID().toString()),
            title = o.optString("title"),
            url = o.optString("url"),
            order = o.optInt("order"),
            updatedAt = o.optLong("updatedAt"),
            deviceId = o.optString("deviceId"),
            deleted = o.optBoolean("deleted", false)
        )
    }
}

class BookmarkStore(context: Context) {
    private val prefs = context.getSharedPreferences("meo_bookmarks", Context.MODE_PRIVATE)

    fun loadActive(): List<BookmarkEntry> =
        loadAll().filter { !it.deleted }.sortedBy { it.order }

    fun loadAll(): List<BookmarkEntry> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { BookmarkEntry.fromJson(arr.getJSONObject(it)) }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun add(title: String, url: String, deviceId: String) {
        val list = loadAll().toMutableList()
        if (list.any { it.url == url && !it.deleted }) return
        val now = System.currentTimeMillis() / 1000
        list.add(
            BookmarkEntry(
                title = title.ifBlank { url },
                url = url,
                order = list.size,
                updatedAt = now,
                deviceId = deviceId
            )
        )
        saveAll(list)
    }

    fun softDelete(id: String, deviceId: String) {
        val list = loadAll().toMutableList()
        val idx = list.indexOfFirst { it.id == id }
        if (idx < 0) return
        list[idx] = list[idx].copy(
            deleted = true,
            updatedAt = System.currentTimeMillis() / 1000,
            deviceId = deviceId
        )
        saveAll(list)
    }

    fun mergeRemote(records: List<BookmarkEntry>) {
        val map = loadAll().associateBy { it.id }.toMutableMap()
        for (incoming in records) {
            val local = map[incoming.id]
            if (local == null) map[incoming.id] = incoming
            else if (incoming.updatedAt > local.updatedAt ||
                (incoming.updatedAt == local.updatedAt && incoming.deviceId > local.deviceId)
            ) {
                map[incoming.id] = incoming
            }
        }
        saveAll(map.values.toList())
    }

    private fun saveAll(items: List<BookmarkEntry>) {
        val arr = JSONArray()
        items.forEach { arr.put(it.toJson()) }
        prefs.edit().putString(KEY, arr.toString()).apply()
    }

    companion object {
        private const val KEY = "items_v1"
    }
}
