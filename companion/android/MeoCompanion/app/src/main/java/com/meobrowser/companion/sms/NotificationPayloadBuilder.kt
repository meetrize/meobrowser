package com.meobrowser.companion.sms

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.service.notification.StatusBarNotification
import org.json.JSONObject

data class PhoneNotificationPayload(
    val id: String,
    val packageName: String,
    val appLabel: String,
    val title: String,
    val body: String,
    val ts: Long,
    val postTimeMs: Long,
    val ongoing: Boolean,
    val groupSummary: Boolean,
) {
    fun toJson(deviceToken: String): JSONObject {
        val flags = JSONObject()
        flags.put("ongoing", ongoing)
        flags.put("groupSummary", groupSummary)
        return JSONObject().apply {
            put("v", 1)
            put("type", "phone_notification")
            put("deviceToken", deviceToken)
            put("id", id)
            put("packageName", packageName)
            put("appLabel", appLabel)
            put("title", title)
            put("body", body)
            put("ts", ts)
            put("postTimeMs", postTimeMs)
            put("flags", flags)
        }
    }
}

/**
 * 从 StatusBarNotification 组装协议载荷（截断 + 去重 id）。
 */
object NotificationPayloadBuilder {
    private const val TITLE_MAX = 200
    private const val BODY_MAX = 1000

    fun build(context: Context, sbn: StatusBarNotification): PhoneNotificationPayload? {
        val n = sbn.notification ?: return null
        val extras = n.extras ?: return null
        val title = truncate(extras.charSeq(Notification.EXTRA_TITLE), TITLE_MAX)
        val text = extras.charSeq(Notification.EXTRA_TEXT)
        val big = extras.charSeq(Notification.EXTRA_BIG_TEXT)
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n") { it?.toString().orEmpty() }
            .orEmpty()
        val sub = extras.charSeq(Notification.EXTRA_SUB_TEXT)
        val bodyRaw = listOf(text, big, lines, sub)
            .filter { it.isNotBlank() }
            .joinToString("\n")
            .ifBlank {
                // title 已单独上传；正文为空时用 title 作 body 兜底（避免 Mac 跳过）
                if (title.isNotBlank()) title else ""
            }
        val body = truncate(bodyRaw, BODY_MAX)
        if (title.isBlank() && body.isBlank()) return null

        val packageName = sbn.packageName.orEmpty()
        val appLabel = resolveAppLabel(context, packageName)
        val postTimeMs = sbn.postTime
        val id = buildId(sbn, packageName, title, body, postTimeMs)
        val ongoing = (n.flags and Notification.FLAG_ONGOING_EVENT) != 0
        val groupSummary = (n.flags and Notification.FLAG_GROUP_SUMMARY) != 0

        return PhoneNotificationPayload(
            id = id,
            packageName = packageName,
            appLabel = appLabel,
            title = title,
            body = body,
            ts = postTimeMs / 1000L,
            postTimeMs = postTimeMs,
            ongoing = ongoing,
            groupSummary = groupSummary,
        )
    }

    private fun buildId(
        sbn: StatusBarNotification,
        packageName: String,
        title: String,
        body: String,
        postTimeMs: Long,
    ): String {
        val key = try {
            sbn.key
        } catch (_: Exception) {
            null
        }
        if (!key.isNullOrBlank()) {
            return truncate("$packageName:$key", 180)
        }
        val bucket = postTimeMs / 5000L
        return truncate(
            "$packageName:${title.hashCode()}:${body.hashCode()}:$bucket",
            180
        )
    }

    private fun resolveAppLabel(context: Context, packageName: String): String {
        if (packageName.isBlank()) return ""
        return try {
            val pm = context.packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (_: PackageManager.NameNotFoundException) {
            ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun truncate(value: String, max: Int): String {
        val t = value.trim()
        if (t.length <= max) return t
        return t.take(max - 1) + "…"
    }

    private fun android.os.Bundle.charSeq(key: String): String {
        return getCharSequence(key)?.toString().orEmpty()
    }
}
