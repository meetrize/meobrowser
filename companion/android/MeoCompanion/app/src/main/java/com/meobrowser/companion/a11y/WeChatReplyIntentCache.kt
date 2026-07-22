package com.meobrowser.companion.a11y

import android.app.PendingIntent
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.LinkedHashMap

/**
 * 缓存近期微信通知的 contentIntent，供 [WeChatReplyExecutor] 直接打开对应会话
 *（第三方无障碍往往读不到微信节点树）。
 */
object WeChatReplyIntentCache {
    private const val TAG = "WeChatReplyCache"
    const val WECHAT_PACKAGE = "com.tencent.mm"
    private const val MAX = 40

    data class Entry(
        val title: String,
        val contentIntent: PendingIntent?,
        val cachedAtMs: Long,
    )

    private val lock = Any()
    private val byTitle = object : LinkedHashMap<String, Entry>(MAX, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Entry>?): Boolean {
            return size > MAX
        }
    }

    fun normalizeTitle(raw: String): String {
        var t = raw.trim()
        if (t.isEmpty()) return t
        // 去掉末尾未读数：(2) / （2） / [2]
        t = t.replace(Regex("""[\(\[（]\d+[\)\]）]\s*$"""), "").trim()
        // 「张三: 你好」→ 取冒号前
        val colon = t.indexOfFirst { it == ':' || it == '：' }
        if (colon in 1..31) {
            t = t.substring(0, colon).trim()
        }
        return t
    }

    fun remember(sbn: StatusBarNotification, titleHint: String?) {
        val pkg = sbn.packageName.orEmpty()
        if (pkg != WECHAT_PACKAGE && !pkg.contains("tencent.mm")) return
        val extras = sbn.notification?.extras
        val title = titleHint?.trim().orEmpty().ifBlank {
            extras?.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        }
        if (title.isBlank()) return
        val pi = sbn.notification?.contentIntent
        val entry = Entry(title = title, contentIntent = pi, cachedAtMs = System.currentTimeMillis())
        val keys = linkedSetOf(title, normalizeTitle(title)).filter { it.isNotBlank() }
        synchronized(lock) {
            for (k in keys) {
                byTitle[k] = entry
            }
        }
        Log.i(TAG, "remember title=$title keys=$keys hasIntent=${pi != null}")
    }

    fun find(contact: String): Entry? {
        val key = contact.trim()
        if (key.isBlank()) return null
        val norm = normalizeTitle(key)
        synchronized(lock) {
            byTitle[key]?.let { return it }
            byTitle[norm]?.let { return it }
            return byTitle.values.firstOrNull {
                val t = it.title
                val n = normalizeTitle(t)
                t == key || n == key || n == norm ||
                    t.contains(key) || key.contains(n) || n.contains(norm)
            }
        }
    }

    fun size(): Int = synchronized(lock) { byTitle.size }

    fun clear() {
        synchronized(lock) { byTitle.clear() }
    }
}
