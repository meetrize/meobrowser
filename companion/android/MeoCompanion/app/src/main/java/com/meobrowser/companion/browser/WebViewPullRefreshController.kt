package com.meobrowser.companion.browser

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.ViewTreeObserver
import android.webkit.JavascriptInterface
import android.webkit.WebView
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

/**
 * 解决「页面中部下拉仍出现刷新」：
 *
 * 许多站点用内部 div 滚动，WebView.scrollY 恒为 0，会被误判为页顶。
 * 因此采用三重门闩（对齐 Chrome / MetaMask）：
 * 1. JS 捕获真实滚动位置（含内部滚动容器）
 * 2. 手指必须从顶部激活区内按下
 * 3. 未武装时 SwipeRefresh 完全不拦截触摸
 */
class WebViewPullRefreshController(
    private val swipe: SwipeRefreshLayout,
    private val isWebPageActive: () -> Boolean,
    private val onRefresh: () -> Unit
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var boundWebView: WebView? = null
    private var pageEnabled = false
    /** 本次手势是否允许下拉刷新（DOWN 时锁定） */
    private var gestureArmed = false
    /** 页面/内部容器滚动位置（JS 上报） */
    @Volatile
    private var jsScrollY: Int = 0

    private val activationZonePx: Float =
        swipe.resources.displayMetrics.density * ACTIVATION_ZONE_DP

    private val scrollListener = ViewTreeObserver.OnScrollChangedListener {
        if (!swipe.isRefreshing) {
            applyArmedState()
        }
    }

    private val jsBridge = object {
        @JavascriptInterface
        fun onScroll(y: Int) {
            jsScrollY = y.coerceAtLeast(0)
            mainHandler.post {
                if (!swipe.isRefreshing && !gestureArmed) {
                    applyArmedState()
                }
            }
        }
    }

    fun attach() {
        swipe.setColorSchemeColors(0xFF007AFF.toInt())
        val trigger = (swipe.resources.displayMetrics.density * TRIGGER_DISTANCE_DP).toInt()
        swipe.setDistanceToTriggerSync(trigger)
        swipe.setOnRefreshListener { onRefresh() }
        // true = 还能向上滚 → 不刷新
        swipe.setOnChildScrollUpCallback { _, _ -> !gestureArmed || !isAtDocumentTop() }
        setPullAllowed(false)
        swipe.isEnabled = false
    }

    @SuppressLint("ClickableViewAccessibility", "SetJavaScriptEnabled")
    fun bind(webView: WebView?) {
        unbind()
        if (webView == null) {
            pageEnabled = false
            gestureArmed = false
            jsScrollY = 0
            setPullAllowed(false)
            swipe.isEnabled = false
            return
        }
        boundWebView = webView
        webView.isNestedScrollingEnabled = true
        webView.addJavascriptInterface(jsBridge, JS_INTERFACE)
        webView.setOnTouchListener { _, event ->
            handleTouch(webView, event)
            false
        }
        webView.viewTreeObserver.addOnScrollChangedListener(scrollListener)
        injectScrollTracker(webView)
        gestureArmed = false
        applyArmedState()
    }

    fun unbind() {
        boundWebView?.let { wv ->
            wv.setOnTouchListener(null)
            // removeJavascriptInterface 在 API 11+
            try {
                wv.removeJavascriptInterface(JS_INTERFACE)
            } catch (_: Exception) {
            }
            if (wv.viewTreeObserver.isAlive) {
                wv.viewTreeObserver.removeOnScrollChangedListener(scrollListener)
            }
        }
        boundWebView = null
        gestureArmed = false
        jsScrollY = 0
        setPullAllowed(false)
        if (!swipe.isRefreshing) {
            swipe.isEnabled = false
        }
    }

    fun setPageEnabled(enabled: Boolean) {
        pageEnabled = enabled
        if (!enabled) {
            gestureArmed = false
            jsScrollY = 0
            swipe.isRefreshing = false
            setPullAllowed(false)
            swipe.isEnabled = false
        } else {
            applyArmedState()
        }
    }

    fun stopRefreshing() {
        swipe.isRefreshing = false
        gestureArmed = false
        setPullAllowed(false)
        applyArmedState()
    }

    /** 页面加载完成后重新注入滚动监听 */
    fun onPageFinished(webView: WebView?) {
        if (webView == null || webView !== boundWebView) return
        jsScrollY = 0
        injectScrollTracker(webView)
        if (!gestureArmed) {
            applyArmedState()
        }
    }

    private fun handleTouch(webView: WebView, event: MotionEvent) {
        if (!pageEnabled || !isWebPageActive()) {
            disarm()
            return
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                // 同步再读一次原生 scrollY；JS 值由滚动过程持续更新
                val inTopZone = event.y <= activationZonePx
                val atTop = isAtDocumentTop(webView)
                gestureArmed = inTopZone && atTop
                applyArmedState()
            }
            MotionEvent.ACTION_MOVE -> {
                if (!gestureArmed) return
                // 拉的过程中若页面其实已不在顶（内部容器滚动起来了），立刻交还
                if (!isAtDocumentTop(webView)) {
                    disarm()
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (!swipe.isRefreshing) {
                    disarm()
                }
            }
        }
    }

    private fun disarm() {
        gestureArmed = false
        setPullAllowed(false)
        if (!swipe.isRefreshing) {
            swipe.isEnabled = false
        }
    }

    private fun applyArmedState() {
        if (!pageEnabled || !isWebPageActive()) {
            disarm()
            return
        }
        if (swipe.isRefreshing) {
            swipe.isEnabled = true
            setPullAllowed(true)
            return
        }
        // 空闲时：只有「已武装的本次手势」才允许拦截；绝不因 scrollY==0 而常开
        val allow = gestureArmed && isAtDocumentTop()
        swipe.isEnabled = allow
        setPullAllowed(allow)
    }

    private fun setPullAllowed(allowed: Boolean) {
        (swipe as? TopEdgeSwipeRefreshLayout)?.pullAllowed = allowed
    }

    private fun isAtDocumentTop(webView: WebView? = boundWebView): Boolean {
        if (webView == null) return false
        if (webView.scrollY > SCROLL_TOP_THRESHOLD_PX) return false
        if (jsScrollY > SCROLL_TOP_THRESHOLD_PX) return false
        return true
    }

    private fun injectScrollTracker(webView: WebView) {
        webView.evaluateJavascript(SCROLL_TRACKER_JS, null)
    }

    companion object {
        private const val JS_INTERFACE = "MeoPtr"
        /** 必须从网页顶部这段区域内起手，中部下拉绝不通往刷新 */
        private const val ACTIVATION_ZONE_DP = 72f
        private const val TRIGGER_DISTANCE_DP = 80f
        private const val SCROLL_TOP_THRESHOLD_PX = 8

        private val SCROLL_TRACKER_JS = """
            (function(){
              if (window.__meoPtrInstalled) {
                try {
                  var y0 = Math.max(window.pageYOffset||0,
                    document.documentElement.scrollTop||0,
                    document.body.scrollTop||0);
                  MeoPtr.onScroll(Math.round(y0));
                } catch (e) {}
                return;
              }
              window.__meoPtrInstalled = true;
              function report(y){
                try { MeoPtr.onScroll(Math.round(y)); } catch (e) {}
              }
              function pageY(){
                return Math.max(window.pageYOffset||0,
                  document.documentElement.scrollTop||0,
                  (document.body && document.body.scrollTop)||0);
              }
              document.addEventListener('scroll', function(ev){
                var y = pageY();
                var t = ev.target;
                if (t && t !== document && t !== window) {
                  try {
                    if (typeof t.scrollTop === 'number') y = Math.max(y, t.scrollTop);
                  } catch (e) {}
                }
                report(y);
              }, {passive:true, capture:true});
              document.addEventListener('touchstart', function(){
                report(pageY());
              }, {passive:true, capture:true});
              report(pageY());
            })();
        """.trimIndent()
    }
}
