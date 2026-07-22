package com.meobrowser.companion.a11y

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.WindowManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.os.Build

/**
 * 微信回复用 AccessibilityService：剪贴板、手势点击、（若节点可读）SET_TEXT/CLICK。
 *
 * 注意：现行微信常对第三方服务返回空树；主路径依赖通知 Intent 打开会话 + 底部手势。
 */
class WeChatReplyAccessibilityService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())

    private val debugReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!isDebuggable()) return
            if (intent?.action != ACTION_DEBUG) return
            val cmd = intent.getStringExtra("cmd").orEmpty()
            val text = intent.getStringExtra("text").orEmpty()
            Log.i(TAG, "debug cmd=$cmd")
            mainHandler.post {
                when (cmd) {
                    "clipboard" -> setClipboard(text)
                    "dump" -> Log.i(TAG, "readable=${isWeChatTreeReadable()} edit=${findEditText()!=null}")
                    "reply" -> {
                        val contact = intent.getStringExtra("contact").orEmpty().ifBlank { "平安喜乐" }
                        val body = text.ifBlank { "测试自动发送" }
                        Thread({
                            val result = WeChatReplyExecutor.tryExecute(
                                this@WeChatReplyAccessibilityService,
                                WeChatReplyExecutor.Request(
                                    requestId = "adb-debug",
                                    contact = contact,
                                    text = body,
                                ),
                            )
                            Log.i(TAG, "debug reply result=$result")
                        }, "wechat-reply-debug").start()
                    }
                    else -> Unit
                }
            }
        }
    }

    private fun isDebuggable(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo?.apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = flags or
                AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            notificationTimeout = 100
        }
        instance = this
        if (isDebuggable()) {
            val filter = IntentFilter(ACTION_DEBUG)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(debugReceiver, filter, RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(debugReceiver, filter)
            }
        }
        Log.i(TAG, "service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (isDebuggable()) {
            try {
                unregisterReceiver(debugReceiver)
            } catch (_: Exception) {
            }
        }
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun setClipboard(text: String) {
        val cm = getSystemService(ClipboardManager::class.java)
        cm?.setPrimaryClip(ClipData.newPlainText("meo_wechat_reply", text))
        Log.i(TAG, "clipboard set len=${text.length}")
    }

    fun activeRoots(): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        rootInActiveWindow?.let { out += it }
        windows?.forEach { w ->
            val r = w.root ?: return@forEach
            if (out.none { it == r }) out += r
        }
        return out
    }

    fun isWeChatTreeReadable(): Boolean {
        return activeRoots().any { root ->
            val pkg = root.packageName?.toString().orEmpty()
            pkg == WeChatReplyIntentCache.WECHAT_PACKAGE && root.childCount > 0
        }
    }

    fun isWeChatForeground(): Boolean {
        return activeRoots().any {
            it.packageName?.toString() == WeChatReplyIntentCache.WECHAT_PACKAGE
        } || windows.orEmpty().any {
            it.root?.packageName?.toString() == WeChatReplyIntentCache.WECHAT_PACKAGE
        }
    }

    fun windowTitles(): List<String> {
        return windows.orEmpty().mapNotNull { w ->
            w.title?.toString()?.takeIf { it.isNotBlank() }
        }
    }

    fun likelyChatWith(contact: String): Boolean {
        val norm = WeChatReplyIntentCache.normalizeTitle(contact)
        if (norm.isBlank()) return false
        if (windowTitles().any { title ->
                val t = title.trim()
                t == contact || t == norm || t.contains(norm) || norm.contains(t)
            }
        ) {
            return true
        }
        // 聊天页顶栏标题常在树里，不一定在 window.title
        return activeRoots().any { root ->
            findFirst(root) { node ->
                val t = node.text?.toString().orEmpty().trim()
                (t == contact || t == norm) && !node.isEditable
            } != null
        }
    }

    fun findEditText(): AccessibilityNodeInfo? {
        // 微信同一 id 可能挂在 FrameLayout 与 EditText 上，必须优先真实可编辑 EditText
        val editable = activeRoots().firstNotNullOfOrNull { root ->
            findFirst(root) {
                it.className?.toString()?.endsWith("EditText") == true && it.isEditable
            }
        }
        if (editable != null) return editable
        return activeRoots().firstNotNullOfOrNull { root ->
            findFirst(root) {
                it.viewIdResourceName == ID_EDIT && it.isEditable
            }
        }
    }

    fun findSendButton(): AccessibilityNodeInfo? {
        return activeRoots().firstNotNullOfOrNull { root ->
            findFirst(root) {
                it.viewIdResourceName == ID_SEND || it.text?.toString() == "发送"
            }
        }
    }

    fun findClickableText(exact: String): AccessibilityNodeInfo? {
        return findContactNode(exact)
    }

    /** 按显示名找会话行（精确 → 包含；点父节点可点区域）。 */
    fun findContactNode(contact: String): AccessibilityNodeInfo? {
        val norm = WeChatReplyIntentCache.normalizeTitle(contact)
        if (norm.isBlank()) return null
        val exact = activeRoots().firstNotNullOfOrNull { root ->
            findFirst(root) { node ->
                val t = node.text?.toString().orEmpty().trim()
                val d = node.contentDescription?.toString().orEmpty().trim()
                t == contact || t == norm || d == contact || d == norm
            }
        }
        if (exact != null) return exact
        return activeRoots().firstNotNullOfOrNull { root ->
            findFirst(root) { node ->
                val t = node.text?.toString().orEmpty().trim()
                val d = node.contentDescription?.toString().orEmpty().trim()
                // 避免匹配聊天气泡正文：优先短标题
                (t.length in norm.length..(norm.length + 8) && (t.contains(norm) || norm.contains(t))) ||
                    (d.length in norm.length..(norm.length + 8) && (d.contains(norm) || norm.contains(d)))
            }
        }
    }

    fun findPasteAction(): AccessibilityNodeInfo? {
        return activeRoots().firstNotNullOfOrNull { root ->
            findFirst(root) {
                val t = it.text?.toString().orEmpty()
                val d = it.contentDescription?.toString().orEmpty()
                t == "粘贴" || t == "Paste" || d == "粘贴" || d == "Paste"
            }
        }
    }

    fun setTextOn(node: AccessibilityNodeInfo, text: String): Boolean {
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val ok = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        Log.i(
            TAG,
            "SET_TEXT ok=$ok class=${node.className} editable=${node.isEditable} id=${node.viewIdResourceName}",
        )
        return ok
    }

    fun click(node: AccessibilityNodeInfo): Boolean {
        var n: AccessibilityNodeInfo? = node
        while (n != null) {
            if (n.isClickable) {
                return n.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            n = n.parent
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    /** 真机评测通过的粘贴路径：焦点在输入框后发 KEYCODE_PASTE。 */
    fun injectPasteKeyEvent(): Boolean {
        return try {
            val p = ProcessBuilder("input", "keyevent", "279")
                .redirectErrorStream(true)
                .start()
            val ok = p.waitFor(2, java.util.concurrent.TimeUnit.SECONDS) && p.exitValue() == 0
            if (!ok) p.destroyForcibly()
            Log.i(TAG, "inject KEYCODE_PASTE ok=$ok")
            ok
        } catch (e: Exception) {
            Log.w(TAG, "inject KEYCODE_PASTE failed", e)
            false
        }
    }

    fun editTextContains(expected: String): Boolean {
        val t = findEditText()?.text?.toString().orEmpty()
        return t.contains(expected)
    }

    fun scrollForwardOnce(): Boolean {
        return activeRoots().any { root ->
            findFirst(root) {
                it.isScrollable && it.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            } != null
        }
    }

    fun displaySize(): Pair<Int, Int> {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            b.width() to b.height()
        } else {
            @Suppress("DEPRECATION")
            val d: Display = wm.defaultDisplay
            val p = android.graphics.Point()
            @Suppress("DEPRECATION")
            d.getRealSize(p)
            p.x to p.y
        }
    }

    fun gestureTap(x: Float, y: Float, label: String, durationMs: Long = 50L): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        val ok = dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.i(TAG, "gesture $label completed")
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "gesture $label cancelled")
            }
        }, null)
        Log.i(TAG, "gesture $label dispatched=$ok @($x,$y)")
        return ok
    }

    fun gestureLongPress(x: Float, y: Float, label: String): Boolean {
        return gestureTap(x, y, label, durationMs = 850L)
    }

    fun nodeCenter(node: AccessibilityNodeInfo): Pair<Float, Float>? {
        val r = Rect()
        node.getBoundsInScreen(r)
        if (r.isEmpty) return null
        return (r.centerX().toFloat()) to (r.centerY().toFloat())
    }

    fun bubbleContains(text: String): Boolean {
        return activeRoots().any { root ->
            findFirst(root) {
                val t = it.text?.toString().orEmpty()
                (it.viewIdResourceName == ID_BUBBLE || t.isNotEmpty()) && t == text
            } != null
        }
    }

    private fun findFirst(
        root: AccessibilityNodeInfo,
        pred: (AccessibilityNodeInfo) -> Boolean,
    ): AccessibilityNodeInfo? {
        var found: AccessibilityNodeInfo? = null
        walk(root, 0) { node, _ ->
            if (found == null && pred(node)) found = node
        }
        return found
    }

    private fun walk(node: AccessibilityNodeInfo?, depth: Int, visit: (AccessibilityNodeInfo, Int) -> Unit) {
        if (node == null || depth > 40) return
        visit(node, depth)
        for (i in 0 until node.childCount) {
            walk(node.getChild(i), depth + 1, visit)
        }
    }

    companion object {
        private const val TAG = "WeChatReplyA11y"
        const val ACTION_DEBUG = "com.meobrowser.companion.a11y.REPLY_DEBUG"
        const val ID_EDIT = "com.tencent.mm:id/bkk"
        const val ID_SEND = "com.tencent.mm:id/bql"
        const val ID_BUBBLE = "com.tencent.mm:id/bkl"

        @Volatile
        var instance: WeChatReplyAccessibilityService? = null
            private set

        fun isEnabled(context: Context): Boolean {
            val expected = "${context.packageName}/${WeChatReplyAccessibilityService::class.java.name}"
            val enabled = android.provider.Settings.Secure.getString(
                context.contentResolver,
                android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ).orEmpty()
            return enabled.split(':').any { it.equals(expected, ignoreCase = true) } ||
                instance != null
        }
    }
}
