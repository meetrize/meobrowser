package com.meobrowser.companion.sms

import android.app.Notification
import android.service.notification.StatusBarNotification

/**
 * 全部通知镜像时的噪音过滤：ongoing / 汇总 / 自身 / 空内容。
 */
object NotificationNoiseFilter {

    fun shouldSkip(sbn: StatusBarNotification, selfPackage: String): Boolean {
        if (sbn.packageName == selfPackage) return true
        val n = sbn.notification ?: return true
        if ((n.flags and Notification.FLAG_ONGOING_EVENT) != 0) return true
        if ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return true
        val extras = n.extras ?: return true
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty().trim()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty().trim()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty().trim()
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n") { it?.toString().orEmpty() }
            .orEmpty()
            .trim()
        val sub = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty().trim()
        return title.isEmpty() && text.isEmpty() && big.isEmpty() && lines.isEmpty() && sub.isEmpty()
    }
}
