package com.meobrowser.companion.browser

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.Toast
import com.meobrowser.companion.R
import java.util.Locale

/**
 * 将 zhihu://、weixin://、intent:// 等 App 自定义协议交给系统打开对应 App。
 * http(s) / about / data 等仍留在 WebView 内。
 */
object ExternalAppNavigator {
    private const val TAG = "MeoExtNav"

    fun shouldHandleExternally(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        val scheme = Uri.parse(url).scheme?.lowercase(Locale.US) ?: return false
        return when (scheme) {
            "http", "https",
            "about", "data", "blob", "javascript",
            "file", "content",
            "ws", "wss" -> false
            else -> true
        }
    }

    /**
     * 尝试唤起外部 App。
     * @param loadInWebView 当 intent:// 提供 http(s) fallback 且未安装 App 时回调，由浏览器自己打开。
     * @return true 表示已拦截，WebView 不应再加载原 URL。
     */
    fun open(
        context: Context,
        url: String,
        loadInWebView: ((String) -> Unit)? = null
    ): Boolean {
        if (!shouldHandleExternally(url)) return false
        return try {
            when {
                url.startsWith("intent:", ignoreCase = true) ->
                    openIntentUri(context, url, loadInWebView)
                url.startsWith("android-app:", ignoreCase = true) ->
                    openAndroidAppUri(context, url)
                else -> openViewUri(context, url)
            }
        } catch (e: Exception) {
            Log.w(TAG, "open failed: $url", e)
            toast(context, context.getString(R.string.external_app_open_failed))
            true
        }
    }

    private fun openViewUri(context: Context, url: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startOrExplain(context, intent, url)
    }

    private fun openIntentUri(
        context: Context,
        url: String,
        loadInWebView: ((String) -> Unit)?
    ): Boolean {
        val intent = Intent.parseUri(url, Intent.URI_INTENT_SCHEME).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            component = null
            selector = null
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            val fallback = intent.getStringExtra("browser_fallback_url")
            if (!fallback.isNullOrBlank() &&
                (fallback.startsWith("http://", true) || fallback.startsWith("https://", true))
            ) {
                loadInWebView?.invoke(fallback)
                return true
            }
            if (tryMarket(context, intent.`package`)) return true
            toast(context, context.getString(R.string.external_app_not_installed))
            true
        }
    }

    private fun openAndroidAppUri(context: Context, url: String): Boolean {
        return try {
            val intent = Intent.parseUri(url, Intent.URI_ANDROID_APP_SCHEME).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startOrExplain(context, intent, url)
        } catch (_: Exception) {
            openViewUri(context, url)
        }
    }

    private fun tryMarket(context: Context, packageName: String?): Boolean {
        if (packageName.isNullOrBlank()) return false
        val marketIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("market://details?id=$packageName")
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(marketIntent)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                context.startActivity(
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("https://play.google.com/store/apps/details?id=$packageName")
                    ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                )
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun startOrExplain(context: Context, intent: Intent, url: String): Boolean {
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            Log.i(TAG, "no handler for $url")
            toast(context, context.getString(R.string.external_app_not_installed))
            true
        }
    }

    private fun toast(context: Context, message: String) {
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }
}
