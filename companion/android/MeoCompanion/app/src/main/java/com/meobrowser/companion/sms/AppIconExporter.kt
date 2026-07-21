package com.meobrowser.companion.sms

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
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
            val at72 = encodePng(drawableToBitmap(drawable, PREFERRED_SIZE), PREFERRED_SIZE)
            val chosen = when {
                at72 != null && at72.size <= MAX_BYTES -> Pair(at72, PREFERRED_SIZE)
                else -> {
                    val at48 = encodePng(drawableToBitmap(drawable, FALLBACK_SIZE), FALLBACK_SIZE)
                    if (at48 == null || at48.size > MAX_BYTES) {
                        Log.w(TAG, "icon too large or encode failed pkg=$packageName")
                        return null
                    }
                    Pair(at48, FALLBACK_SIZE)
                }
            }
            val bytes = chosen.first
            val size = chosen.second
            ExportedIcon(
                pngBytes = bytes,
                iconHash = iconHash(bytes),
                width = size,
                height = size,
                appLabel = label
            )
        } catch (e: PackageManager.NameNotFoundException) {
            Log.w(TAG, "package not found: $packageName")
            null
        } catch (e: Exception) {
            Log.e(TAG, "export failed pkg=$packageName", e)
            null
        }
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
