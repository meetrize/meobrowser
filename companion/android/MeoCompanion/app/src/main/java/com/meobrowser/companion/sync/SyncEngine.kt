package com.meobrowser.companion.sync

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.meobrowser.companion.browser.newtab.ShortcutItem
import com.meobrowser.companion.browser.newtab.ShortcutStore
import com.meobrowser.companion.browser.store.BookmarkEntry
import com.meobrowser.companion.browser.store.BookmarkStore
import com.meobrowser.companion.browser.store.HistoryEntry
import com.meobrowser.companion.browser.store.HistoryStore
import com.meobrowser.companion.channel.CompanionSession
import com.meobrowser.companion.pairing.PairingPrefs
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.CountDownLatch
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

data class SyncResult(
    val ok: Boolean,
    val message: String
)

object SyncEngine {
    private const val TAG = "MeoSync"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pushRunnable: Runnable? = null
    @Volatile
    private var lastError: String? = null
    private val shortcutListeners = CopyOnWriteArraySet<() -> Unit>()

    /** 等待 Mac 对 sync_pull 的回复 */
    @Volatile
    private var pullLatch: CountDownLatch? = null
    private val pulledShortcutRecords = AtomicInteger(0)
    private val mergedShortcutVisible = AtomicInteger(0)

    fun addShortcutChangeListener(listener: () -> Unit) {
        shortcutListeners.add(listener)
    }

    fun removeShortcutChangeListener(listener: () -> Unit) {
        shortcutListeners.remove(listener)
    }

    fun onAppForeground(context: Context) {
        val prefs = SyncPrefs(context)
        if (!prefs.enabled) return
        if (!CompanionSession.client.isConnected) return
        CompanionSession.executor.execute {
            runSyncLocked(context.applicationContext)
        }
    }

    fun onConnected(context: Context) {
        onAppForeground(context)
    }

    fun schedulePush(context: Context) {
        val app = context.applicationContext
        val prefs = SyncPrefs(app)
        if (!prefs.enabled) return
        pushRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            CompanionSession.executor.execute { pushAll(app) }
        }
        pushRunnable = r
        mainHandler.postDelayed(r, 3000L)
    }

    fun syncNow(context: Context): SyncResult {
        val app = context.applicationContext
        val prefs = SyncPrefs(app)
        if (!prefs.enabled) {
            return SyncResult(false, "请先打开「启用自动同步」")
        }
        if (!prefs.syncShortcuts && !prefs.syncHistory && !prefs.syncBookmarks) {
            return SyncResult(false, "请至少勾选一项同步内容（建议勾选快捷方式）")
        }
        val pairing = PairingPrefs(app)
        if (pairing.deviceToken.isNullOrBlank()) {
            return SyncResult(false, "尚未与 Mac 配对，请先到「互联与配对」连接")
        }
        if (!CompanionSession.client.isConnected) {
            return SyncResult(false, "未连接 Mac，请先在「互联与配对」连接后再同步")
        }
        return try {
            lastError = null
            pulledShortcutRecords.set(0)
            mergedShortcutVisible.set(0)
            val future = FutureTask {
                runSyncLocked(app)
                Unit
            }
            CompanionSession.executor.execute(future)
            future.get(25, TimeUnit.SECONDS)
            val err = lastError
            if (!err.isNullOrBlank()) {
                SyncResult(false, err)
            } else {
                prefs.lastSyncAt = System.currentTimeMillis()
                val pulled = pulledShortcutRecords.get()
                val visible = mergedShortcutVisible.get().takeIf { it > 0 }
                    ?: ShortcutStore(app).loadActive().size
                SyncResult(
                    true,
                    "同步完成：从 Mac 收到 $pulled 条，当前新标签页 $visible 个快捷方式"
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "syncNow failed", e)
            SyncResult(false, "同步失败：${e.message ?: e.javaClass.simpleName}")
        }
    }

    fun pullAndPush(context: Context) {
        CompanionSession.executor.execute {
            runSyncLocked(context.applicationContext)
        }
    }

    private fun runSyncLocked(context: Context) {
        lastError = null
        val prefs = SyncPrefs(context)
        if (!prefs.enabled) return
        val pairing = PairingPrefs(context)
        val token = pairing.deviceToken
        if (token.isNullOrBlank()) {
            lastError = "尚未配对"
            return
        }
        if (!CompanionSession.client.isConnected) {
            lastError = "未连接"
            return
        }
        try {
            // 确保本地至少有一次 load（含 seed），但 seed 时间戳很低，不会盖过 Mac
            ShortcutStore(context).loadActive()

            val hello = JSONObject()
            hello.put("v", 1)
            hello.put("type", "sync_hello")
            hello.put("deviceToken", token)
            hello.put("deviceId", pairing.deviceId)
            hello.put("supportedKinds", JSONArray().apply {
                if (prefs.syncShortcuts) put("shortcut")
                if (prefs.syncHistory) put("history")
                if (prefs.syncBookmarks) put("bookmark")
            })
            hello.put("epoch", prefs.epoch)
            CompanionSession.client.send(hello)

            val waiting = mutableListOf<String>()
            if (prefs.syncShortcuts) waiting.add("shortcut")
            if (prefs.syncHistory) waiting.add("history")
            if (prefs.syncBookmarks) waiting.add("bookmark")

            if (waiting.isNotEmpty()) {
                val latch = CountDownLatch(waiting.size)
                pullLatch = latch
                waiting.forEach { kind ->
                    sendPull(token, kind, prefs.epoch)
                }
                val ok = latch.await(12, TimeUnit.SECONDS)
                pullLatch = null
                if (!ok && lastError.isNullOrBlank()) {
                    lastError = "等待 Mac 回传超时，请确认 Mac「登录助手」已开启同步，并重启 Mac 端 MeoBrowser"
                    Log.e(TAG, "pull timeout waiting=$waiting")
                }
                // Mac 可能分多帧推送，首帧到达后稍等后续帧
                if (ok) Thread.sleep(600)
            }

            // 拉完再推，避免用手机默认列表覆盖 Mac
            if (lastError.isNullOrBlank()) {
                pushAll(context)
                Thread.sleep(200)
            }
            prefs.lastSyncAt = System.currentTimeMillis()
            Log.i(
                TAG,
                "runSyncLocked done pulled=${pulledShortcutRecords.get()} visible=${mergedShortcutVisible.get()} err=$lastError"
            )
        } catch (e: Exception) {
            Log.e(TAG, "runSyncLocked failed", e)
            lastError = e.message ?: "发送失败"
            pullLatch = null
        }
    }

    fun pushAll(context: Context) {
        val prefs = SyncPrefs(context)
        if (!prefs.enabled) return
        val pairing = PairingPrefs(context)
        val token = pairing.deviceToken ?: return
        if (!CompanionSession.client.isConnected) return
        try {
            if (prefs.syncShortcuts) {
                val store = ShortcutStore(context)
                val records = store.loadAll().map { it.toJson() }
                Log.i(TAG, "push shortcut count=${records.size}")
                pushKind(token, "shortcut", prefs.bumpEpoch(), records)
            }
            if (prefs.syncHistory) {
                val store = HistoryStore(context)
                pushKind(token, "history", prefs.bumpEpoch(), store.loadAll().map { it.toJson() })
            }
            if (prefs.syncBookmarks) {
                val store = BookmarkStore(context)
                pushKind(token, "bookmark", prefs.bumpEpoch(), store.loadAll().map { it.toJson() })
            }
            prefs.lastSyncAt = System.currentTimeMillis()
        } catch (e: Exception) {
            Log.e(TAG, "pushAll failed", e)
            lastError = e.message ?: "推送失败"
        }
    }

    private fun sendPull(token: String, kind: String, since: Long) {
        val json = JSONObject()
        json.put("v", 1)
        json.put("type", "sync_pull")
        json.put("deviceToken", token)
        json.put("kind", kind)
        json.put("sinceEpoch", since)
        CompanionSession.client.send(json)
    }

    private fun pushKind(token: String, kind: String, epoch: Long, records: List<JSONObject>) {
        val chunkSize = 30
        if (records.size <= chunkSize) {
            val arr = JSONArray()
            records.forEach { arr.put(it) }
            val json = JSONObject()
            json.put("v", 1)
            json.put("type", "sync_push")
            json.put("deviceToken", token)
            json.put("kind", kind)
            json.put("epoch", epoch)
            json.put("records", arr)
            val bytes = json.toString().toByteArray(Charsets.UTF_8)
            if (bytes.size > 60 * 1024) {
                pushChunked(token, kind, epoch, records, 12)
            } else {
                CompanionSession.client.send(json)
            }
            return
        }
        pushChunked(token, kind, epoch, records, chunkSize)
    }

    private fun pushChunked(
        token: String,
        kind: String,
        epoch: Long,
        records: List<JSONObject>,
        chunkSize: Int
    ) {
        val transferId = "${kind}-${epoch}-${System.currentTimeMillis()}"
        val chunks = records.chunked(chunkSize)
        chunks.forEachIndexed { index, part ->
            val arr = JSONArray()
            part.forEach { arr.put(it) }
            val wrapper = JSONObject()
            wrapper.put("kind", kind)
            wrapper.put("epoch", epoch)
            wrapper.put("records", arr)
            val chunk = JSONObject()
            chunk.put("v", 1)
            chunk.put("type", "sync_chunk")
            chunk.put("deviceToken", token)
            chunk.put("transferId", transferId)
            chunk.put("index", index)
            chunk.put("total", chunks.size)
            chunk.put("payload", wrapper.toString())
            CompanionSession.client.send(chunk)
        }
    }

    fun handleMessage(context: Context, json: JSONObject) {
        val type = json.optString("type")
        when (type) {
            "sync_push", "sync_chunk" -> {
                applyIncoming(context, json)
                signalPullDone(json.optString("kind").ifBlank {
                    if (type == "sync_chunk") {
                        runCatching {
                            JSONObject(json.optString("payload")).optString("kind")
                        }.getOrDefault("")
                    } else ""
                })
            }
            "sync_pull" -> {
                CompanionSession.executor.execute { pushAll(context) }
            }
            "sync_ack" -> {
                SyncPrefs(context).lastSyncAt = System.currentTimeMillis()
                Log.i(TAG, "sync_ack kind=${json.optString("kind")}")
            }
            "sync_hello" -> Log.i(TAG, "sync_hello from peer")
            "sync_error" -> {
                val msg = json.optString("message").ifBlank { "Mac 拒绝同步" }
                lastError = msg
                Log.e(TAG, "sync_error: $msg")
                // 错误也结束等待，避免一直卡到超时
                pullLatch?.let { latch ->
                    while (latch.count > 0) latch.countDown()
                }
            }
        }
    }

    private fun signalPullDone(kind: String) {
        val latch = pullLatch ?: return
        // 每种 kind 的第一次回复就 countDown 一次；多余 push 忽略
        if (latch.count > 0) {
            latch.countDown()
            Log.i(TAG, "pull signal kind=$kind remaining=${latch.count}")
        }
    }

    private fun applyIncoming(context: Context, json: JSONObject) {
        val prefs = SyncPrefs(context)
        if (!prefs.enabled) {
            signalPullDone(json.optString("kind"))
            return
        }
        val kind: String
        val records: JSONArray
        if (json.optString("type") == "sync_chunk") {
            val payload = JSONObject(json.optString("payload"))
            kind = payload.optString("kind")
            records = payload.optJSONArray("records") ?: JSONArray()
        } else {
            kind = json.optString("kind")
            records = json.optJSONArray("records") ?: JSONArray()
        }
        Log.i(TAG, "applyIncoming kind=$kind count=${records.length()}")
        when (kind) {
            "shortcut" -> if (prefs.syncShortcuts) {
                val list = (0 until records.length()).mapNotNull {
                    runCatching { ShortcutItem.fromJson(records.getJSONObject(it)) }.getOrNull()
                }
                pulledShortcutRecords.addAndGet(list.size)
                val visible = ShortcutStore(context).mergeRemote(list)
                mergedShortcutVisible.set(visible)
                notifyShortcutsChanged()
            }
            "history" -> if (prefs.syncHistory) {
                val list = (0 until records.length()).map {
                    HistoryEntry.fromJson(records.getJSONObject(it))
                }
                HistoryStore(context).mergeRemote(list)
            }
            "bookmark" -> if (prefs.syncBookmarks) {
                val list = (0 until records.length()).map {
                    BookmarkEntry.fromJson(records.getJSONObject(it))
                }
                BookmarkStore(context).mergeRemote(list)
            }
        }
        prefs.lastSyncAt = System.currentTimeMillis()
        ack(context, kind, json.optLong("epoch", prefs.epoch))
    }

    private fun notifyShortcutsChanged() {
        mainHandler.post {
            shortcutListeners.forEach { runCatching { it.invoke() } }
        }
    }

    private fun ack(context: Context, kind: String, epoch: Long) {
        val token = PairingPrefs(context).deviceToken ?: return
        if (!CompanionSession.client.isConnected) return
        val json = JSONObject()
        json.put("v", 1)
        json.put("type", "sync_ack")
        json.put("deviceToken", token)
        json.put("kind", kind)
        json.put("appliedEpoch", epoch)
        try {
            CompanionSession.client.send(json)
        } catch (e: Exception) {
            Log.e(TAG, "ack failed", e)
        }
    }
}
