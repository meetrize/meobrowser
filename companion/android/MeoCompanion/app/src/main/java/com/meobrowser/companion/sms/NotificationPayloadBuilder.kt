package com.meobrowser.companion.sms

import android.app.Notification
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.service.notification.StatusBarNotification
import android.util.Log
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
    /** 代理包无法归因到真实 App 时，附带通知自带小图标（可选）。 */
    val inlineIconPng: ByteArray? = null,
    val inlineIconHash: String? = null,
    val inlineIconWidth: Int? = null,
    val inlineIconHeight: Int? = null,
) {
    fun toJson(deviceToken: String, source: String? = null): JSONObject {
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
            // Mac 侧栏「同步通知」补拉：source=pull 时入库但不弹系统横幅
            if (!source.isNullOrBlank()) {
                put("source", source)
            }
            val png = inlineIconPng
            val hash = inlineIconHash
            if (png != null && !hash.isNullOrBlank()) {
                put("iconPngBase64", AppIconExporter.toBase64(png))
                put("iconHash", hash)
                put("iconWidth", inlineIconWidth ?: 0)
                put("iconHeight", inlineIconHeight ?: 0)
            }
        }
    }
}

/**
 * 从 StatusBarNotification 组装协议载荷（截断 + 去重 id）。
 *
 * 厂商推送代理（如华为「智能服务」）可能导致 `sbn.packageName` 不是真实 App：
 * 优先用 Icon 资源包名归因；否则用 EXTRA_SUBSTITUTE_APP_NAME + 通知自带图标。
 */
object NotificationPayloadBuilder {
    private const val TAG = "NotifPayload"
    private const val TITLE_MAX = 200
    private const val BODY_MAX = 1000

    /** 常见 OEM 推送 / 智能助手代理包（不全，标签「智能服务」等另作兜底）。 */
    private val KNOWN_PROXY_PACKAGES = setOf(
        "com.huawei.intelligent",
        "com.huawei.hwintelligent",
        "com.huawei.android.pushagent",
        "com.huawei.android.pushagentie",
        "com.hihonor.intelligent",
        "com.hihonor.push",
        "com.coloros.mcs",
        "com.heytap.mcs",
        "com.heytap.htms",
        "com.vivo.pushservice",
        "com.vivo.abe",
        "com.xiaomi.xmsf",
        "com.miui.systemAdSolution",
    )

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
        // 许多短信/App 通知 text 与 bigText 内容相同；直接拼接会在 Mac 显示成「同一条文案两遍」。
        val bodyRaw = composeBody(text = text, big = big, lines = lines, sub = sub)
            .ifBlank {
                // title 已单独上传；正文为空时用 title 作 body 兜底（避免 Mac 跳过）
                if (title.isNotBlank()) title else ""
            }
        val body = truncate(bodyRaw, BODY_MAX)
        if (title.isBlank() && body.isBlank()) return null

        val postedPackage = sbn.packageName.orEmpty()
        val opPkg = try {
            sbn.opPkg.orEmpty()
        } catch (_: Exception) {
            ""
        }
        // API 35+ 为 Notification.EXTRA_SUBSTITUTE_APP_NAME；compileSdk 34 用字面量兼容
        val substituteName = extras.charSeq("android.substName").trim()
        val iconResPackage = resolveIconResPackage(n)
        val postedIsProxy = isProxyPackage(context, postedPackage)

        val attributedPackage = resolveAttributedPackage(
            context = context,
            postedPackage = postedPackage,
            iconResPackage = iconResPackage,
            postedIsProxy = postedIsProxy,
        )

        val appLabel = when {
            substituteName.isNotBlank() -> substituteName
            else -> resolveAppLabel(context, attributedPackage)
        }

        // 仍落在代理包上：Mac 无法靠 package→app_icon 拿到正确图标，附带通知自带图
        val needInlineIcon = postedIsProxy && attributedPackage == postedPackage
        val inline = if (needInlineIcon) {
            AppIconExporter.exportNotificationIcon(context, n, appLabel)
        } else {
            null
        }

        Log.i(
            TAG,
            "identity posted=$postedPackage op=$opPkg iconRes=${iconResPackage ?: "-"} " +
                "attributed=$attributedPackage substitute=${substituteName.ifBlank { "-" }} " +
                "proxy=$postedIsProxy inlineIcon=${inline != null}"
        )

        val postTimeMs = sbn.postTime
        val id = buildId(sbn, attributedPackage, title, body, postTimeMs)
        val ongoing = (n.flags and Notification.FLAG_ONGOING_EVENT) != 0
        val groupSummary = (n.flags and Notification.FLAG_GROUP_SUMMARY) != 0

        return PhoneNotificationPayload(
            id = id,
            packageName = attributedPackage,
            appLabel = appLabel,
            title = title,
            body = body,
            ts = postTimeMs / 1000L,
            postTimeMs = postTimeMs,
            ongoing = ongoing,
            groupSummary = groupSummary,
            inlineIconPng = inline?.pngBytes,
            inlineIconHash = inline?.iconHash,
            inlineIconWidth = inline?.width,
            inlineIconHeight = inline?.height,
        )
    }

    private fun resolveAttributedPackage(
        context: Context,
        postedPackage: String,
        iconResPackage: String?,
        postedIsProxy: Boolean,
    ): String {
        if (!postedIsProxy) return postedPackage
        val candidate = iconResPackage?.trim().orEmpty()
        if (candidate.isBlank() || candidate == postedPackage) return postedPackage
        if (isProxyPackage(context, candidate)) return postedPackage
        if (!isPackageInstalled(context, candidate)) return postedPackage
        return candidate
    }

    private fun resolveIconResPackage(notification: Notification): String? {
        val icons = listOfNotNull(notification.smallIcon, notification.getLargeIconCompat())
        for (icon in icons) {
            val pkg = resPackageOf(icon) ?: continue
            if (pkg.isNotBlank()) return pkg
        }
        return null
    }

    private fun Notification.getLargeIconCompat(): Icon? {
        return try {
            getLargeIcon()
        } catch (_: Exception) {
            null
        }
    }

    private fun resPackageOf(icon: Icon): String? {
        return try {
            if (icon.type != Icon.TYPE_RESOURCE) return null
            // API 23+；minSdk 26
            icon.resPackage.takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    private fun isProxyPackage(context: Context, packageName: String): Boolean {
        if (packageName.isBlank()) return false
        if (KNOWN_PROXY_PACKAGES.contains(packageName)) return true
        val label = resolveAppLabel(context, packageName)
        if (label.isBlank()) return false
        // 华为/荣耀通知栏常见展示名
        return label == "智能服务" ||
            label.contains("智能服务") ||
            label.equals("Smart Services", ignoreCase = true) ||
            label.equals("Intelligent Services", ignoreCase = true)
    }

    private fun isPackageInstalled(context: Context, packageName: String): Boolean {
        return try {
            context.packageManager.getApplicationInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        } catch (_: Exception) {
            false
        }
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

    private fun composeBody(
        text: String,
        big: String,
        lines: String,
        sub: String,
    ): String {
        val parts = mutableListOf<String>()
        fun addUnique(raw: String) {
            val t = raw.trim()
            if (t.isEmpty()) return
            // 已有更长文案包含本段 → 跳过
            if (parts.any { it == t || it.contains(t) }) return
            // 本段更完整、包含已有短句 → 替换
            val idx = parts.indexOfFirst { t.contains(it) }
            if (idx >= 0) {
                parts[idx] = t
            } else {
                parts.add(t)
            }
        }
        // 优先 bigText（展开态通常最完整），再 text / lines / sub
        addUnique(big)
        addUnique(text)
        addUnique(lines)
        addUnique(sub)
        return parts.joinToString("\n")
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
