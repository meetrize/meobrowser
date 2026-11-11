package com.meobrowser.companion.browser.newtab

import com.meobrowser.companion.browser.BrowserPrefs

/** 新标签页快捷方式网格外观（来自设置滑条）。 */
data class ShortcutGridStyle(
    val columns: Int = 4,
    val iconSizeDp: Int = 56,
    val iconSizeLevel: Int = 1,
    val rowSpacingDp: Int = 10
) {
    val letterTextSp: Float
        get() = when (iconSizeLevel) {
            0 -> 18f
            2 -> 28f
            else -> 22f
        }

    val titleTextSp: Float
        get() = when (iconSizeLevel) {
            0 -> 11f
            2 -> 13f
            else -> 12f
        }

    val cornerRadiusDp: Float
        get() = when (iconSizeLevel) {
            0 -> 11f
            2 -> 18f
            else -> 14f
        }

    val insetPadDp: Int
        get() = when (iconSizeLevel) {
            0 -> 7
            2 -> 12
            else -> 9
        }

    companion object {
        fun from(prefs: BrowserPrefs): ShortcutGridStyle = ShortcutGridStyle(
            columns = prefs.shortcutColumns,
            iconSizeDp = prefs.shortcutIconSizeDp(),
            iconSizeLevel = prefs.shortcutIconSize,
            rowSpacingDp = prefs.shortcutRowSpacingDp
        )
    }
}
