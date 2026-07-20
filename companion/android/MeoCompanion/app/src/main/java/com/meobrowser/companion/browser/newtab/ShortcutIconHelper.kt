package com.meobrowser.companion.browser.newtab

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** 轻量图标：首字母色块 + 可选拉取站点 favicon（无额外依赖）。 */
object ShortcutIconHelper {
    private val cache = ConcurrentHashMap<String, Bitmap>()
    private val executor = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())

    private val palette = intArrayOf(
        0xFF5B8DEF.toInt(),
        0xFF34C759.toInt(),
        0xFFFF9500.toInt(),
        0xFFFF3B30.toInt(),
        0xFFAF52DE.toInt(),
        0xFF00C7BE.toInt(),
        0xFFFF2D55.toInt(),
        0xFF5856D6.toInt()
    )

    fun letter(title: String, url: String): String {
        val t = title.trim()
        if (t.isNotEmpty()) {
            val ch = t.first()
            return if (ch.isLetterOrDigit()) ch.uppercaseChar().toString() else "•"
        }
        val host = hostOf(url)
        return host.firstOrNull()?.uppercaseChar()?.toString() ?: "•"
    }

    fun colorFor(url: String, title: String): Int {
        val key = hostOf(url).ifBlank { title }
        var h = 0
        for (c in key) h = 31 * h + c.code
        return palette[kotlin.math.abs(h) % palette.size]
    }

    fun hostOf(url: String): String {
        return try {
            val u = Uri.parse(url)
            (u.host ?: "").removePrefix("www.")
        } catch (_: Exception) {
            ""
        }
    }

    /**
     * 绑定 favicon；成功时回调 onLoaded。失败则保持字母占位。
     */
    fun bindFavicon(imageView: ImageView, item: ShortcutItem, onLoaded: () -> Unit) {
        imageView.setImageDrawable(null)
        imageView.tag = item.id
        val direct = item.iconURL.trim()
        val host = hostOf(item.url)
        val faviconUrl = when {
            direct.startsWith("http") -> direct
            host.isNotBlank() -> "https://www.google.com/s2/favicons?domain=$host&sz=128"
            else -> null
        } ?: return

        cache[faviconUrl]?.let {
            imageView.setImageBitmap(it)
            onLoaded()
            return
        }

        executor.execute {
            val bmp = download(faviconUrl) ?: return@execute
            cache[faviconUrl] = bmp
            main.post {
                if (imageView.tag == item.id) {
                    imageView.setImageBitmap(bmp)
                    onLoaded()
                }
            }
        }
    }

    private fun download(url: String): Bitmap? {
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 4000
                readTimeout = 4000
                instanceFollowRedirects = true
                requestMethod = "GET"
            }
            conn.inputStream.use { stream ->
                val raw = BitmapFactory.decodeStream(stream) ?: return null
                if (raw.width <= 16 || raw.height <= 16) {
                    raw.recycle()
                    return null
                }
                raw
            }
        } catch (_: Exception) {
            null
        }
    }

    fun contrastLetterColor(@Suppress("UNUSED_PARAMETER") bg: Int): Int = Color.WHITE
}
