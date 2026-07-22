package com.meobrowser.companion.a11y

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import com.meobrowser.companion.sms.OtpNotificationListener
import java.util.concurrent.Callable
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 微信回复状态机（WR-0）：
 * 开实验开关 → 无障碍就绪 → 打开会话（通知 Intent / 节点点名）→ 剪贴板粘贴 → 发送。
 *
 * 编排在调用线程（Companion IO 线程）执行；无障碍 API 投递到主线程。
 */
object WeChatReplyExecutor {
    private const val TAG = "WeChatReplyExec"
    private const val TIMEOUT_MS = 20_000L
    private const val CONTACT_MAX = 64
    private const val TEXT_MAX = 1000

    private val busy = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    data class Request(
        val requestId: String,
        val contact: String,
        val text: String,
        val notificationId: String? = null,
        val packageName: String = WeChatReplyIntentCache.WECHAT_PACKAGE,
    )

    sealed class Result {
        data class Ok(val elapsedMs: Long) : Result()
        data class Err(val code: String, val message: String) : Result()
    }

    fun tryExecute(context: Context, request: Request): Result {
        val app = context.applicationContext
        if (!WeChatReplyPrefs(app).wechatReplyEnabled) {
            return Result.Err("disabled", "请先在 Companion 开启「微信回复」实验开关")
        }
        val contact = request.contact.trim()
        val text = request.text.trim()
        if (contact.isEmpty() || contact.length > CONTACT_MAX) {
            return Result.Err("invalid", "contact 无效")
        }
        if (text.isEmpty() || text.length > TEXT_MAX) {
            return Result.Err("invalid", "text 无效")
        }
        val pkg = request.packageName.ifBlank { WeChatReplyIntentCache.WECHAT_PACKAGE }
        if (pkg != WeChatReplyIntentCache.WECHAT_PACKAGE) {
            return Result.Err("invalid", "仅支持微信 com.tencent.mm")
        }
        if (!isWeChatInstalled(app)) {
            return Result.Err("wechat_not_installed", "未安装微信")
        }
        // TalkBack 开关切换后，Meo 无障碍可能短暂崩溃/未绑定：设置里仍显示已开但 instance==null
        if (!waitForAccessibilityReady(app, timeoutMs = 4_000L)) {
            val listed = WeChatReplyAccessibilityService.isEnabled(app)
            return Result.Err(
                "a11y_required",
                if (listed) {
                    "Meo「微信回复」无障碍未就绪（可能刚崩溃）。请关闭再打开一次该无障碍后重试"
                } else {
                    "请开启 Meo「微信回复」无障碍服务"
                },
            )
        }
        if (!busy.compareAndSet(false, true)) {
            return Result.Err("busy", "已有回复任务进行中")
        }
        val started = System.currentTimeMillis()
        return try {
            // 缓存刷新：成功或已有条目立即继续，避免空等
            repeat(3) { attempt ->
                OtpNotificationListener.ensureBound(app)
                val refreshed = OtpNotificationListener.refreshWeChatReplyIntentCache()
                val size = WeChatReplyIntentCache.size()
                Log.i(TAG, "intent cache refresh attempt=$attempt result=$refreshed size=$size")
                if (refreshed >= 0 || size > 0) return@repeat
                sleep(180)
            }

            val deadline = started + TIMEOUT_MS
            fun remaining(): Long = (deadline - System.currentTimeMillis()).coerceAtLeast(0)
            if (remaining() <= 0) return Result.Err("timeout", "回复超时")

            val tOpen = System.currentTimeMillis()
            if (!openChat(contact, remaining(), app)) {
                val miuiBlocked = WeChatReplyLaunchHelper.isMiuiBackgroundStartAllowed(app) == false
                return Result.Err(
                    if (miuiBlocked) "background_launch_blocked" else "contact_not_found",
                    if (miuiBlocked) {
                        "系统拦截了后台打开微信。请在系统设置中允许 Meo Companion「后台弹出界面」后重试"
                    } else {
                        "无法打开「$contact」会话：请保留该微信通知，或确认已允许后台弹出微信"
                    },
                )
            }
            Log.i(TAG, "phase openMs=${System.currentTimeMillis() - tOpen}")

            // 等输入框（或挖空树下微信已在前台），替代固定 sleep(900)
            var ready = waitUntil(1_800L, 100L) {
                onMain {
                    it.findEditText() != null ||
                        (!it.isWeChatTreeReadable() && it.isWeChatForeground())
                }
            }
            if (!ready) {
                // 再给一轮短等待
                ready = waitUntil(800L, 120L) {
                    onMain { it.findEditText() != null || it.isWeChatForeground() }
                }
            }
            Log.i(TAG, "chat ready=$ready readyWaitMs=${System.currentTimeMillis() - tOpen}")

            val tPaste = System.currentTimeMillis()
            if (!pasteIntoChat(text, remaining())) {
                return Result.Err("paste_failed", "粘贴到输入框失败")
            }
            Log.i(TAG, "phase pasteMs=${System.currentTimeMillis() - tPaste}")
            if (remaining() <= 0) return Result.Err("timeout", "回复超时")

            val tSend = System.currentTimeMillis()
            if (!tapSend(remaining())) {
                return Result.Err("send_failed", "未找到或未能点击「发送」")
            }
            val verified = waitUntil(1_400L, 100L) {
                onMain { a11y ->
                    val bubble = a11y.bubbleContains(text)
                    val editText = a11y.findEditText()?.text?.toString().orEmpty()
                    val sendGone = a11y.findSendButton() == null
                    when {
                        bubble -> true
                        a11y.isWeChatTreeReadable() -> {
                            (editText.isEmpty() || !editText.contains(text)) && sendGone
                        }
                        else -> {
                            a11y.likelyChatWith(contact) && a11y.isWeChatForeground()
                        }
                    }
                }
            }
            Log.i(TAG, "phase sendMs=${System.currentTimeMillis() - tSend} verified=$verified")
            if (verified) {
                Result.Ok(System.currentTimeMillis() - started)
            } else {
                Result.Err("send_failed", "发送后未确认成功，请检查微信是否已打开对应会话")
            }
        } catch (e: Exception) {
            Log.e(TAG, "execute failed", e)
            Result.Err("send_failed", e.message ?: "执行异常")
        } finally {
            busy.set(false)
        }
    }

    /** 轮询直到条件成立或超时。 */
    private fun waitUntil(timeoutMs: Long, stepMs: Long, pred: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (pred()) return true
            sleep(stepMs)
        }
        return pred()
    }

    private fun waitForAccessibilityReady(app: Context, timeoutMs: Long): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val bound = WeChatReplyAccessibilityService.instance != null
            val listed = WeChatReplyAccessibilityService.isEnabled(app)
            if (bound && listed) return true
            if (bound) return true
            sleep(300)
        }
        return WeChatReplyAccessibilityService.instance != null
    }

    private fun openChat(contact: String, timeoutMs: Long, app: Context): Boolean {
        // 已在目标会话：标题 / 顶栏名 / 联系人节点任一命中即可（TalkBack 聚焦输入框时 window.title 常为空）
        if (onMain {
                it.findEditText() != null &&
                    (it.likelyChatWith(contact) || it.findContactNode(contact) != null)
            }
        ) {
            Log.i(TAG, "already in target chat contact=$contact")
            return true
        }
        if (onMain { it.findEditText() != null && it.isWeChatTreeReadable() && !it.likelyChatWith(contact) }) {
            Log.i(TAG, "in other chat; back to list for contact=$contact")
            onMain {
                val back = it.findClickableText("返回")
                if (back != null) it.click(back) else {
                    it.performGlobalAction(
                        android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK,
                    )
                }
            }
            sleep(700)
        }

        val cached = WeChatReplyIntentCache.find(contact)
        Log.i(
            TAG,
            "cache lookup contact=$contact hit=${cached != null} hasIntent=${cached?.contentIntent != null} title=${cached?.title} size=${WeChatReplyIntentCache.size()} miuiBg=${WeChatReplyLaunchHelper.isMiuiBackgroundStartAllowed(app)}",
        )
        val pi = cached?.contentIntent
        if (pi != null) {
            val sent = WeChatReplyLaunchHelper.sendPendingIntent(pi)
            Log.i(TAG, "opened via notification intent title=${cached.title} sent=$sent")
            if (sent) {
                // 轮询进入会话，替代固定 sleep(1600)+再等 2200
                val ok = waitUntil(2_800L, 120L) {
                    onMain {
                        it.findEditText() != null ||
                            it.likelyChatWith(contact) ||
                            (!it.isWeChatTreeReadable() && it.isWeChatForeground())
                    }
                }
                if (ok) return true
            }
            // PendingIntent 可能已失效或被 MIUI 静默拦截 → 中转页再试一次
            WeChatReplyLaunchHelper.startTrampoline(app, contact, pi)
            val ok2 = waitUntil(2_400L, 120L) {
                onMain {
                    it.findEditText() != null ||
                        it.likelyChatWith(contact) ||
                        (!it.isWeChatTreeReadable() && it.isWeChatForeground())
                }
            }
            if (ok2) return true
        }

        return openViaListOrLaunch(contact, timeoutMs, app)
    }

    private fun openViaListOrLaunch(contact: String, @Suppress("UNUSED_PARAMETER") timeoutMs: Long, app: Context): Boolean {
        bringWeChatToForeground(app, contact, WeChatReplyIntentCache.find(contact)?.contentIntent)
        if (!waitWeChatForeground(2_400L)) {
            Log.w(TAG, "wechat still not foreground after launch attempts titles=${onMain { it.windowTitles() }}")
            if (openViaNotificationShade(contact)) {
                waitUntil(1_200L, 100L) { onMain { it.isWeChatForeground() } }
            }
        }
        if (onMain { it.findEditText() != null && it.likelyChatWith(contact) }) return true

        val readable = onMain { it.isWeChatTreeReadable() }
        val fg = onMain { it.isWeChatForeground() }
        Log.i(TAG, "wechat tree readable=$readable fg=$fg")
        if (!fg) {
            return false
        }
        if (readable) {
            if (openReadableContact(contact)) return true
        } else {
            Log.w(TAG, "tree opaque; list open needs TalkBack/读屏 or notification intent")
        }

        Log.i(TAG, "fallback opaque search for contact=$contact")
        return openOpaqueBySearch(contact)
    }

    private fun bringWeChatToForeground(app: Context, contact: String, contentIntent: PendingIntent?) {
        onMain { launchWeChat(it) }
        if (waitUntil(500L, 80L) { onMain { it.isWeChatForeground() } }) return
        WeChatReplyLaunchHelper.launchWeChatPackage(app)
        if (waitUntil(500L, 80L) { onMain { it.isWeChatForeground() } }) return
        WeChatReplyLaunchHelper.startTrampoline(app, contact, contentIntent)
    }

    private fun waitWeChatForeground(timeoutMs: Long): Boolean {
        return waitUntil(timeoutMs, 120L) { onMain { it.isWeChatForeground() } }
    }

    /** 下拉通知栏点击仍在的微信通知（contentIntent 失效时的兜底）。 */
    private fun openViaNotificationShade(contact: String): Boolean {
        Log.i(TAG, "try notification shade for contact=$contact")
        onMain {
            it.performGlobalAction(
                android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS,
            )
        }
        sleep(900)
        val clicked = onMain { a11y ->
            val hit = a11y.findContactNode(contact) ?: return@onMain false
            a11y.click(hit)
        }
        sleep(800)
        // 收起通知栏
        onMain {
            it.performGlobalAction(
                android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK,
            )
        }
        sleep(500)
        val ok = onMain { it.isWeChatForeground() }
        Log.i(TAG, "notification shade click=$clicked fg=$ok")
        return ok
    }

    private fun openReadableContact(contact: String): Boolean {
        // 若已在某聊天，先回列表
        if (onMain { it.findEditText() != null }) {
            onMain {
                val back = it.findClickableText("返回")
                if (back != null) it.click(back) else it.performGlobalAction(
                    android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK,
                )
            }
            sleep(700)
        }

        repeat(4) { page ->
            val hitClicked = onMain { a11y ->
                val hit = a11y.findContactNode(contact) ?: return@onMain false
                a11y.click(hit)
            }
            if (hitClicked) {
                val opened = waitUntil(1_200L, 100L) {
                    onMain { it.findEditText() != null || it.likelyChatWith(contact) }
                }
                if (opened) {
                    Log.i(TAG, "opened contact via list page=$page")
                    return true
                }
            }
            onMain { it.scrollForwardOnce() }
            sleep(350)
        }

        val searched = onMain { a11y ->
            val search = a11y.findClickableText("搜索")
                ?: a11y.findContactNode("搜索")
                ?: return@onMain false
            a11y.click(search)
            true
        }
        if (!searched) return false
        sleep(800)
        onMain { it.setClipboard(contact) }
        sleep(200)
        val typed = onMain { a11y ->
            val edit = a11y.findEditText() ?: return@onMain false
            a11y.click(edit)
            if (a11y.setTextOn(edit, contact)) return@onMain true
            if (edit.performAction(AccessibilityNodeInfo.ACTION_PASTE)) return@onMain true
            false
        }
        if (!typed) {
            onMain { it.injectPasteKeyEvent() }
            sleep(350)
        }
        sleep(900)
        val opened = onMain { a11y ->
            val result = a11y.findContactNode(contact) ?: return@onMain false
            a11y.click(result)
        }
        if (opened) sleep(1000)
        return onMain { it.findEditText() != null || it.likelyChatWith(contact) }
    }

    /**
     * 无障碍树挖空时的兜底。优先依赖通知 contentIntent；此处尽量留在微信内搜索。
     */
    private fun openOpaqueBySearch(contact: String): Boolean {
        onMain { launchWeChat(it) }
        sleep(1600)
        if (!ensureWeChatForeground()) return false

        // 从聊天页回到会话列表（只退一步，避免退出微信）
        onMain {
            it.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
        }
        sleep(600)
        if (!ensureWeChatForeground()) {
            onMain { launchWeChat(it) }
            sleep(1200)
            if (!ensureWeChatForeground()) return false
        }

        onMain { a11y ->
            val (w, h) = a11y.displaySize()
            a11y.gestureTap(w * 0.82f, h * 0.072f, "searchIcon")
        }
        sleep(900)
        if (!onMain { it.isWeChatForeground() }) {
            Log.w(TAG, "searchIcon left WeChat (likely system search); abort")
            onMain {
                it.performGlobalAction(android.accessibilityservice.AccessibilityService.GLOBAL_ACTION_BACK)
            }
            return false
        }

        onMain { it.setClipboard(contact) }
        sleep(250)
        onMain { a11y ->
            val (w, h) = a11y.displaySize()
            a11y.gestureTap(w * 0.5f, h * 0.09f, "searchEdit")
        }
        sleep(400)

        var pasted = onMain { a11y ->
            val edit = a11y.findEditText()
            if (edit != null) {
                a11y.click(edit)
                if (a11y.setTextOn(edit, contact)) return@onMain true
                if (edit.performAction(AccessibilityNodeInfo.ACTION_PASTE)) return@onMain true
            }
            false
        }
        if (!pasted) {
            onMain { a11y ->
                val (w, h) = a11y.displaySize()
                a11y.gestureLongPress(w * 0.5f, h * 0.09f, "searchLong")
            }
            sleep(800)
            pasted = onMain { a11y ->
                val paste = a11y.findPasteAction()
                if (paste != null) {
                    a11y.click(paste)
                    true
                } else {
                    val (w, h) = a11y.displaySize()
                    a11y.gestureTap(w * 0.4f, h * 0.05f, "pasteApprox")
                    true
                }
            }
        }
        if (!pasted) return false
        sleep(1200)
        if (!onMain { it.isWeChatForeground() }) return false

        if (onMain { it.isWeChatTreeReadable() }) {
            val hit = onMain { a11y ->
                val node = a11y.findClickableText(contact) ?: return@onMain false
                a11y.click(node)
            }
            if (hit) {
                sleep(1200)
                return onMain { it.findEditText() != null || it.likelyChatWith(contact) }
            }
        }

        onMain { a11y ->
            val (w, h) = a11y.displaySize()
            a11y.gestureTap(w * 0.5f, h * 0.22f, "searchResult1")
        }
        sleep(1000)
        val ok = onMain { it.isWeChatForeground() && (it.findEditText() != null || it.likelyChatWith(contact)) }
        Log.i(TAG, "opaque search done ok=$ok titles=${onMain { it.windowTitles() }}")
        return ok
    }

    private fun ensureWeChatForeground(): Boolean {
        if (onMain { it.isWeChatForeground() }) return true
        onMain { launchWeChat(it) }
        sleep(800)
        if (waitWeChatForeground(2000)) return true
        Log.w(TAG, "wechat not foreground titles=${onMain { it.windowTitles() }}")
        return false
    }

    private fun launchWeChat(a11y: WeChatReplyAccessibilityService) {
        WeChatReplyLaunchHelper.launchWeChatPackage(a11y)
    }

    private fun pasteIntoChat(text: String, @Suppress("UNUSED_PARAMETER") timeoutMs: Long): Boolean {
        onMain { it.setClipboard(text) }
        sleep(60)

        repeat(3) { attempt ->
            val setOk = onMain { a11y ->
                val edit = a11y.findEditText() ?: return@onMain false
                a11y.click(edit)
                edit.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                a11y.setTextOn(edit, text)
            }
            if (setOk) {
                if (waitUntil(450L, 60L) { onMain { it.editTextContains(text) } }) {
                    Log.i(TAG, "SET_TEXT verified attempt=$attempt")
                    return true
                }
            }

            val pasteOk = onMain { a11y ->
                val edit = a11y.findEditText() ?: return@onMain false
                a11y.click(edit)
                edit.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                edit.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            }
            if (pasteOk) {
                if (waitUntil(450L, 60L) { onMain { it.editTextContains(text) } }) {
                    Log.i(TAG, "ACTION_PASTE verified attempt=$attempt")
                    return true
                }
            }

            onMain { it.injectPasteKeyEvent() }
            if (waitUntil(350L, 60L) { onMain { it.editTextContains(text) } }) {
                Log.i(TAG, "KEYCODE_PASTE verified attempt=$attempt")
                return true
            }
        }

        // 长按输入框中心 → 点「粘贴」
        val longPressPt = onMain { a11y ->
            val edit = a11y.findEditText()
            a11y.nodeCenter(edit ?: return@onMain null)
        }
        if (longPressPt != null) {
            onMain { it.gestureLongPress(longPressPt.first, longPressPt.second, "editLong") }
        } else {
            onMain { a11y ->
                val (w, h) = a11y.displaySize()
                a11y.gestureTap(w * 0.42f, h * 0.93f, "edit")
            }
            sleep(300)
            onMain { a11y ->
                val (w, h) = a11y.displaySize()
                a11y.gestureLongPress(w * 0.42f, h * 0.93f, "editLong")
            }
        }
        sleep(700)
        val menuPaste = onMain { a11y ->
            val paste = a11y.findPasteAction()
            if (paste != null) {
                a11y.click(paste)
                true
            } else {
                false
            }
        }
        if (menuPaste) {
            sleep(350)
            if (onMain { !it.isWeChatTreeReadable() || it.editTextContains(text) }) return true
        }

        return onMain { !it.isWeChatTreeReadable() || it.editTextContains(text) }
    }

    private fun tapSend(@Suppress("UNUSED_PARAMETER") timeoutMs: Long): Boolean {
        val viaNode = onMain { a11y ->
            val send = a11y.findSendButton() ?: return@onMain false
            if (a11y.click(send)) return@onMain true
            a11y.nodeCenter(send)?.let { (x, y) -> a11y.gestureTap(x, y, "sendNode") } ?: false
        }
        if (viaNode) return true
        return onMain { a11y ->
            val (w, h) = a11y.displaySize()
            a11y.gestureTap(w * 0.91f, h * 0.97f, "sendApprox")
        }
    }

    private fun <T> onMain(block: (WeChatReplyAccessibilityService) -> T): T {
        val a11y = WeChatReplyAccessibilityService.instance
            ?: error("a11y gone")
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return block(a11y)
        }
        val task = FutureTask(Callable {
            val svc = WeChatReplyAccessibilityService.instance
                ?: error("a11y gone")
            block(svc)
        })
        mainHandler.post(task)
        return task.get(8, TimeUnit.SECONDS)
    }

    private fun isWeChatInstalled(context: Context): Boolean {
        val pm = context.packageManager
        val pkg = WeChatReplyIntentCache.WECHAT_PACKAGE
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
            }
            return true
        } catch (_: PackageManager.NameNotFoundException) {
            // 兜底：LAUNCHER intent（仍依赖 manifest <queries>）
            return pm.getLaunchIntentForPackage(pkg) != null
        }
    }

    private fun sleep(ms: Long) {
        try {
            Thread.sleep(ms)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }
}
