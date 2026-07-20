package com.meobrowser.companion.browser.newtab

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.ImageView
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** 快捷方式图标：内存 + 磁盘缓存；按内容选择满幅圆角 / 白底内边距。 */
object ShortcutIconHelper {
    enum class FitStyle {
        /** 异形 / 透明底：白底圆角矩形 + 四周留白 */
        INSET,
        /** 本身接近矩形色块：铺满圆角矩形 */
        FILL
    }

    data class CachedIcon(val bitmap: Bitmap, val fit: FitStyle)

    private const val TAG = "ShortcutIcon"
    private const val CACHE_DIR = "favicon_cache"
    private const val MAX_DISK_BYTES = 8L * 1024 * 1024
    private const val META_EXT = ".fit"

    private val memory = ConcurrentHashMap<String, CachedIcon>()
    private val inFlight = ConcurrentHashMap.newKeySet<String>()
    private val executor = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var diskDir: File? = null

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

    fun init(context: Context) {
        if (diskDir != null) return
        val dir = File(context.applicationContext.filesDir, CACHE_DIR)
        if (!dir.exists()) dir.mkdirs()
        diskDir = dir
        executor.execute { trimDiskIfNeeded(dir) }
    }

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

    fun contrastLetterColor(@Suppress("UNUSED_PARAMETER") bg: Int): Int = Color.WHITE

    /** 预热：把磁盘命中灌入内存，未命中的后台下载。 */
    fun prefetch(items: List<ShortcutItem>) {
        if (diskDir == null) return
        items.forEach { item ->
            val cacheKey = cacheKeyFor(item) ?: return@forEach
            if (memory.containsKey(cacheKey)) return@forEach
            executor.execute {
                val fromDisk = loadFromDisk(cacheKey)
                if (fromDisk != null) {
                    memory[cacheKey] = fromDisk
                    return@execute
                }
                if (!inFlight.add(cacheKey)) return@execute
                try {
                    val url = resolveFetchUrl(item) ?: return@execute
                    var bmp = download(url)
                    if (bmp == null) {
                        val host = hostOf(item.url)
                        if (host.isNotBlank()) bmp = download("https://$host/favicon.ico")
                    }
                    if (bmp == null) return@execute
                    val fit = analyzeFit(bmp)
                    val cached = CachedIcon(bmp, fit)
                    memory[cacheKey] = cached
                    saveToDisk(cacheKey, cached)
                } finally {
                    inFlight.remove(cacheKey)
                }
            }
        }
    }

    /**
     * 绑定 favicon。命中缓存时同步回调；否则后台拉取并写磁盘。
     * [onLoaded] 在主线程调用。
     */
    fun bindFavicon(
        imageView: ImageView,
        item: ShortcutItem,
        onLoaded: (CachedIcon) -> Unit
    ) {
        imageView.setImageDrawable(null)
        imageView.tag = item.id
        val cacheKey = cacheKeyFor(item) ?: return

        memory[cacheKey]?.let {
            imageView.setImageBitmap(it.bitmap)
            onLoaded(it)
            return
        }

        val fromDisk = loadFromDisk(cacheKey)
        if (fromDisk != null) {
            memory[cacheKey] = fromDisk
            imageView.setImageBitmap(fromDisk.bitmap)
            onLoaded(fromDisk)
            return
        }

        if (!inFlight.add(cacheKey)) return
        val faviconUrl = resolveFetchUrl(item) ?: run {
            inFlight.remove(cacheKey)
            return
        }

        executor.execute {
            try {
                val bmp = download(faviconUrl)
                if (bmp == null) {
                    // 备用：站点根 favicon.ico
                    val host = hostOf(item.url)
                    val fallback = if (host.isNotBlank()) {
                        download("https://$host/favicon.ico")
                    } else null
                    if (fallback == null) return@execute
                    finishLoad(cacheKey, fallback, imageView, item.id, onLoaded)
                } else {
                    finishLoad(cacheKey, bmp, imageView, item.id, onLoaded)
                }
            } finally {
                inFlight.remove(cacheKey)
            }
        }
    }

    private fun finishLoad(
        cacheKey: String,
        bmp: Bitmap,
        imageView: ImageView,
        itemId: String,
        onLoaded: (CachedIcon) -> Unit
    ) {
        val fit = analyzeFit(bmp)
        val cached = CachedIcon(bmp, fit)
        memory[cacheKey] = cached
        saveToDisk(cacheKey, cached)
        main.post {
            if (imageView.tag == itemId) {
                imageView.setImageBitmap(bmp)
                onLoaded(cached)
            }
        }
    }

    private fun cacheKeyFor(item: ShortcutItem): String? {
        val direct = item.iconURL.trim()
        if (direct.startsWith("http")) return "u:" + sha1(direct)
        val host = hostOf(item.url)
        if (host.isBlank()) return null
        return "h:" + sha1(host.lowercase())
    }

    private fun resolveFetchUrl(item: ShortcutItem): String? {
        val direct = item.iconURL.trim()
        if (direct.startsWith("http")) return direct
        val host = hostOf(item.url)
        if (host.isBlank()) return null
        return "https://www.google.com/s2/favicons?domain=$host&sz=128"
    }

    /**
     * 编辑页：按页面 URL / 指定图标 URL 拉取并缓存。
     * 成功时 [onResult] 主线程回调 (resolvedIconUrl, cached)。
     */
    fun fetchForEditor(
        pageUrl: String,
        preferredIconUrl: String?,
        onResult: (ok: Boolean, iconUrl: String?, cached: CachedIcon?, message: String) -> Unit
    ) {
        executor.execute {
            val preferred = preferredIconUrl?.trim().orEmpty()
            val candidates = mutableListOf<String>()
            if (preferred.startsWith("http")) candidates.add(preferred)
            val host = hostOf(pageUrl)
            if (host.isNotBlank()) {
                candidates.add("https://www.google.com/s2/favicons?domain=$host&sz=128")
                candidates.add("https://$host/favicon.ico")
            }
            if (candidates.isEmpty()) {
                main.post { onResult(false, null, null, "请先输入有效网址") }
                return@execute
            }
            var lastUrl: String? = null
            var bmp: Bitmap? = null
            for (u in candidates.distinct()) {
                lastUrl = u
                bmp = download(u)
                if (bmp != null) break
            }
            if (bmp == null || lastUrl == null) {
                main.post { onResult(false, null, null, "未能获取图标，可手动填写") }
                return@execute
            }
            val fit = analyzeFit(bmp)
            val cached = CachedIcon(bmp, fit)
            val key = "u:" + sha1(lastUrl)
            memory[key] = cached
            saveToDisk(key, cached)
            if (host.isNotBlank()) {
                memory["h:" + sha1(host.lowercase())] = cached
                saveToDisk("h:" + sha1(host.lowercase()), cached)
            }
            main.post { onResult(true, lastUrl, cached, "已获取图标") }
        }
    }

    /** 仅预览：优先内存/磁盘，不强制联网（联网由自动获取触发）。 */
    fun loadPreview(
        pageUrl: String,
        iconUrl: String,
        onResult: (CachedIcon?) -> Unit
    ) {
        val preferred = iconUrl.trim()
        val keys = mutableListOf<String>()
        if (preferred.startsWith("http")) keys.add("u:" + sha1(preferred))
        val host = hostOf(pageUrl)
        if (host.isNotBlank()) keys.add("h:" + sha1(host.lowercase()))
        for (k in keys) {
            memory[k]?.let {
                onResult(it)
                return
            }
        }
        executor.execute {
            for (k in keys) {
                val fromDisk = loadFromDisk(k)
                if (fromDisk != null) {
                    memory[k] = fromDisk
                    main.post { onResult(fromDisk) }
                    return@execute
                }
            }
            // 有显式 iconURL 时轻量拉一次预览
            if (preferred.startsWith("http")) {
                val bmp = download(preferred)
                if (bmp != null) {
                    val cached = CachedIcon(bmp, analyzeFit(bmp))
                    val key = "u:" + sha1(preferred)
                    memory[key] = cached
                    saveToDisk(key, cached)
                    main.post { onResult(cached) }
                    return@execute
                }
            }
            main.post { onResult(null) }
        }
    }

    fun putInCache(iconUrl: String, cached: CachedIcon) {
        val u = iconUrl.trim()
        if (!u.startsWith("http")) return
        val key = "u:" + sha1(u)
        memory[key] = cached
        saveToDisk(key, cached)
    }

    private fun download(url: String): Bitmap? {
        return try {
            val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 3500
                readTimeout = 3500
                instanceFollowRedirects = true
                requestMethod = "GET"
                setRequestProperty("Accept", "image/*,*/*;q=0.8")
            }
            val code = conn.responseCode
            if (code !in 200..299) {
                conn.disconnect()
                return null
            }
            conn.inputStream.use { stream ->
                val raw = BitmapFactory.decodeStream(stream) ?: return null
                if (raw.width <= 12 || raw.height <= 12) {
                    raw.recycle()
                    return null
                }
                // 统一成可缓存的软件位图（带 alpha）
                if (raw.config == Bitmap.Config.HARDWARE) {
                    val copy = raw.copy(Bitmap.Config.ARGB_8888, false)
                    raw.recycle()
                    copy
                } else {
                    raw
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "download fail $url: ${e.message}")
            null
        }
    }

    private fun loadFromDisk(cacheKey: String): CachedIcon? {
        val dir = diskDir ?: return null
        val file = File(dir, fileName(cacheKey))
        if (!file.exists() || file.length() == 0L) return null
        return try {
            val bmp = BitmapFactory.decodeFile(file.absolutePath) ?: return null
            val fitFile = File(dir, fileName(cacheKey) + META_EXT)
            val fit = when (fitFile.readText().trim()) {
                "FILL" -> FitStyle.FILL
                else -> FitStyle.INSET
            }
            // 刷新 mtime，便于 LRU
            file.setLastModified(System.currentTimeMillis())
            CachedIcon(bmp, fit)
        } catch (_: Exception) {
            null
        }
    }

    private fun saveToDisk(cacheKey: String, cached: CachedIcon) {
        val dir = diskDir ?: return
        try {
            val file = File(dir, fileName(cacheKey))
            FileOutputStream(file).use { out ->
                cached.bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            }
            File(dir, fileName(cacheKey) + META_EXT).writeText(cached.fit.name)
            trimDiskIfNeeded(dir)
        } catch (e: Exception) {
            Log.d(TAG, "disk save fail: ${e.message}")
        }
    }

    private fun trimDiskIfNeeded(dir: File) {
        try {
            val files = dir.listFiles { f -> f.isFile && f.name.endsWith(".png") } ?: return
            var total = files.sumOf { it.length() }
            if (total <= MAX_DISK_BYTES) return
            files.sortedBy { it.lastModified() }.forEach { f ->
                if (total <= MAX_DISK_BYTES * 3 / 4) return
                val meta = File(f.path + META_EXT)
                total -= f.length()
                f.delete()
                meta.delete()
            }
        } catch (_: Exception) {
        }
    }

    private fun fileName(cacheKey: String): String = sha1(cacheKey) + ".png"

    private fun sha1(s: String): String {
        val dig = MessageDigest.getInstance("SHA-1").digest(s.toByteArray())
        return dig.joinToString("") { "%02x".format(it) }
    }

    /**
     * 简化自 Mac BrowserFaviconAnalyzeIconForDisplay：
     * 四角不透明且偏色块 → FILL；透明异形 → INSET（白底留白）。
     */
    fun analyzeFit(bitmap: Bitmap): FitStyle {
        val w = bitmap.width
        val h = bitmap.height
        if (w < 8 || h < 8) return FitStyle.INSET

        fun px(x: Int, y: Int): Int = bitmap.getPixel(
            x.coerceIn(0, w - 1),
            y.coerceIn(0, h - 1)
        )

        val corners = listOf(
            px(1, 1), px(w - 2, 1), px(1, h - 2), px(w - 2, h - 2)
        )
        val cornerAlphaAvg = corners.map { Color.alpha(it) / 255f }.average().toFloat()
        val cornersTransparent = cornerAlphaAvg < 0.20f

        if (!cornersTransparent) {
            val avgR = corners.map { Color.red(it) }.average() / 255.0
            val avgG = corners.map { Color.green(it) }.average() / 255.0
            val avgB = corners.map { Color.blue(it) }.average() / 255.0
            val (s, l) = rgbToSL(avgR, avgG, avgB)
            val cornerBg = corners[0]
            var fg = 0
            var minX = w
            var minY = h
            var maxX = -1
            var maxY = -1
            // 抽样扫描，控制开销
            val step = maxOf(1, minOf(w, h) / 48)
            var y = 0
            while (y < h) {
                var x = 0
                while (x < w) {
                    if (isForeground(bitmap.getPixel(x, y), cornerBg, bgClear = false)) {
                        fg++
                        if (x < minX) minX = x
                        if (x > maxX) maxX = x
                        if (y < minY) minY = y
                        if (y > maxY) maxY = y
                    }
                    x += step
                }
                y += step
            }
            var coverage = 0f
            if (fg > 4 && maxX >= minX && maxY >= minY) {
                val bw = maxX - minX + 1
                val bh = maxY - minY + 1
                coverage = (bw * bh).toFloat() / (w * h).toFloat()
            }
            val vividOrDark = s >= 0.18 || l <= 0.45
            val lightCanvas = l >= 0.82 && s <= 0.25 && coverage > 0.05f && coverage < 0.88f
            return when {
                vividOrDark && !lightCanvas -> FitStyle.FILL
                !lightCanvas && coverage >= 0.90f && fg > 4 -> FitStyle.FILL
                else -> FitStyle.INSET
            }
        }

        // 透明四角：看前景是否接近铺满包围盒的圆角矩形
        var fg = 0
        var minX = w
        var minY = h
        var maxX = -1
        var maxY = -1
        val step = maxOf(1, minOf(w, h) / 48)
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                if (isForeground(bitmap.getPixel(x, y), 0, bgClear = true)) {
                    fg++
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
                x += step
            }
            y += step
        }
        if (fg < 4 || maxX < minX || maxY < minY) return FitStyle.INSET
        val bw = maxX - minX + 1
        val bh = maxY - minY + 1
        // 用包围盒粗估填充（抽样点数 / 包围盒抽样格）
        val boxSamples = ((bw + step - 1) / step) * ((bh + step - 1) / step)
        val fillRatio = if (boxSamples > 0) fg.toFloat() / boxSamples.toFloat() else 0f
        var aspect = bw.toFloat() / maxOf(bh, 1).toFloat()
        if (aspect < 1f) aspect = 1f / aspect
        return if (fillRatio >= 0.88f && aspect <= 1.25f) FitStyle.FILL else FitStyle.INSET
    }

    private fun isForeground(pixel: Int, bg: Int, bgClear: Boolean): Boolean {
        val a = Color.alpha(pixel)
        if (bgClear) return a > 40
        if (a < 24) return false
        val dr = Color.red(pixel) - Color.red(bg)
        val dg = Color.green(pixel) - Color.green(bg)
        val db = Color.blue(pixel) - Color.blue(bg)
        val da = a - Color.alpha(bg)
        return dr * dr + dg * dg + db * db + da * da > 32 * 32
    }

    private fun rgbToSL(r: Double, g: Double, b: Double): Pair<Double, Double> {
        val maxc = maxOf(r, g, b)
        val minc = minOf(r, g, b)
        val l = (maxc + minc) * 0.5
        val s = if (maxc <= minc + 1e-6) {
            0.0
        } else {
            val d = maxc - minc
            if (l > 0.5) d / (2.0 - maxc - minc) else d / (maxc + minc)
        }
        return s to l
    }
}
