package com.meobrowser.companion.sms

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

/** 将应用图标导出为小尺寸 PNG，供 Companion `app_icon` 推送。 */
object AppIconExporter {
    private const val TAG = "AppIconExporter"
    private const val MAX_BYTES = 12 * 1024
    private const val PREFERRED_SIZE = 72
    private const val FALLBACK_SIZE = 48

    data class ExportedIcon(
        val pngBytes: ByteArray,
        val iconHash: String,
        val width: Int,
        val height: Int,
        val appLabel: String
    )

    fun export(context: Context, packageName: String): ExportedIcon? {
        if (packageName.isBlank() || packageName == "otp") return null
        return try {
            val pm = context.packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            val label = pm.getApplicationLabel(appInfo).toString()
            val drawable = pm.getApplicationIcon(appInfo)
            encodeDrawable(drawable, label)
        } catch (e: PackageManager.NameNotFoundException) {
            Log.w(TAG, "package not found: $packageName")
            null
        } catch (e: Exception) {
            Log.e(TAG, "export failed pkg=$packageName", e)
            null
        }
    }

    /**
     * 从通知自带 small/large icon 导出 PNG。
     * 用于厂商代理包（如「智能服务」）无法归因到真实 package 时的侧栏展示。
     */
    fun exportNotificationIcon(
        context: Context,
        notification: Notification,
        appLabel: String,
    ): ExportedIcon? {
        val candidates = mutableListOf<Icon>()
        try {
            notification.getLargeIcon()?.let { candidates.add(it) }
        } catch (_: Exception) {
        }
        notification.smallIcon?.let { candidates.add(it) }
        for (icon in candidates) {
            val drawable = try {
                icon.loadDrawable(context)
            } catch (e: Exception) {
                Log.w(TAG, "loadDrawable failed", e)
                null
            } ?: continue
            val exported = encodeDrawable(drawable, appLabel)
            if (exported != null) {
                return exported
            }
        }
        Log.w(TAG, "notification icon export failed label=$appLabel")
        return null
    }

    private fun encodeDrawable(drawable: Drawable, appLabel: String): ExportedIcon? {
        val at72 = encodePng(drawableToBitmap(drawable, PREFERRED_SIZE), PREFERRED_SIZE)
        val chosen = when {
            at72 != null && at72.size <= MAX_BYTES -> Pair(at72, PREFERRED_SIZE)
            else -> {
                val at48 = encodePng(drawableToBitmap(drawable, FALLBACK_SIZE), FALLBACK_SIZE)
                if (at48 == null || at48.size > MAX_BYTES) {
                    Log.w(TAG, "icon too large or encode failed label=$appLabel")
                    return null
                }
                Pair(at48, FALLBACK_SIZE)
            }
        }
        val bytes = chosen.first
        val size = chosen.second
        return ExportedIcon(
            pngBytes = bytes,
            iconHash = iconHash(bytes),
            width = size,
            height = size,
            appLabel = appLabel
        )
    }

    fun toBase64(bytes: ByteArray): String =
        Base64.encodeToString(bytes, Base64.NO_WRAP)

    fun iconHash(pngBytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(pngBytes)
        return digest.take(8).joinToString("") { b -> "%02x".format(b) }
    }

    private fun drawableToBitmap(drawable: Drawable, size: Int): Bitmap {
        if (drawable is BitmapDrawable && drawable.bitmap != null) {
            return Bitmap.createScaledBitmap(drawable.bitmap, size, size, true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && drawable is AdaptiveIconDrawable) {
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, size, size)
            drawable.draw(canvas)
            return bitmap
        }
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        return bitmap
    }

    private fun encodePng(bitmap: Bitmap, size: Int): ByteArray? {
        val scaled = if (bitmap.width == size && bitmap.height == size) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, size, size, true)
        }
        val out = ByteArrayOutputStream()
        val ok = scaled.compress(Bitmap.CompressFormat.PNG, 100, out)
        if (!ok) return null
        return out.toByteArray()
    }
}
