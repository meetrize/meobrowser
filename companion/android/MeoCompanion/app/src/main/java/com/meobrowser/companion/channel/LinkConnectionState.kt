package com.meobrowser.companion.channel

/**
 * 底栏状态点与配对页状态卡片共用的互联状态。
 */
enum class LinkConnectionState {
    CONNECTED,
    CONNECTING,
    DISCONNECTED;

    companion object {
        fun from(statusText: String, isConnected: Boolean): LinkConnectionState {
            val text = statusText.trim()
            if (isConnected ||
                text.contains("已配对") ||
                text.contains("连接保持中") ||
                (text.startsWith("已连接") && !text.contains("失败"))
            ) {
                return CONNECTED
            }
            if (text.contains("正在连接") ||
                text.contains("自动连接") ||
                text.contains("重连") ||
                text.contains("等待 hello") ||
                text.contains("连接中")
            ) {
                return CONNECTING
            }
            return DISCONNECTED
        }
    }

    val title: String
        get() = when (this) {
            CONNECTED -> "已连接到 Mac"
            CONNECTING -> "正在连接…"
            DISCONNECTED -> "未连接"
        }

    /** 状态圆点颜色（ARGB） */
    val dotColor: Int
        get() = when (this) {
            CONNECTED -> 0xFF34C759.toInt()
            CONNECTING -> 0xFFFF9F0A.toInt()
            DISCONNECTED -> 0xFF8E8E93.toInt()
        }

    /** 状态卡片左侧圆形底色 */
    val iconBackgroundColor: Int
        get() = when (this) {
            CONNECTED -> 0x1A34C759
            CONNECTING -> 0x1AFF9F0A
            DISCONNECTED -> 0x148E8E93
        }
}
