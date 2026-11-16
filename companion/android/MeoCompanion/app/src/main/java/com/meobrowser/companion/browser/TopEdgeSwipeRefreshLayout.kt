package com.meobrowser.companion.browser

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

/**
 * 仅在 [pullAllowed] 为 true 时才拦截下拉；否则完整交给 WebView 滚动。
 */
class TopEdgeSwipeRefreshLayout @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : SwipeRefreshLayout(context, attrs) {

    @Volatile
    var pullAllowed: Boolean = false

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        if (!isEnabled || !pullAllowed) {
            return false
        }
        return try {
            super.onInterceptTouchEvent(ev)
        } catch (_: Exception) {
            false
        }
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        if (!isEnabled || !pullAllowed) {
            return false
        }
        return try {
            super.onTouchEvent(ev)
        } catch (_: Exception) {
            false
        }
    }
}
