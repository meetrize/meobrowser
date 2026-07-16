package com.meobrowser.companion.sms

import java.text.Normalizer

object OtpParser {
    /**
     * 关键词（允许字间空白/零宽字符，兼容部分 ROM 入库变形）。
     * 例：验证码 / 验 证 码 / 驗證碼
     */
    private val keywordHint = Regex(
        """验\s*证\s*码|驗\s*證\s*碼|校\s*验\s*码|校\s*驗\s*碼|动\s*态\s*码|動\s*態\s*碼|登\s*录\s*码|登\s*錄\s*碼|确\s*认\s*码|確\s*認\s*碼|一\s*次\s*性\s*密\s*码|一\s*次\s*性\s*密\s*碼|\bOTP\b|verification\s*code|auth(?:entication)?\s*code""",
        RegexOption.IGNORE_CASE
    )

    /** 「码：123456」这类强信号，即使关键词正则漏网也能识别 */
    private val codeColonDigits = Regex(
        """[码碼][：:\s]{0,4}([0-9０-９]{4,8})"""
    )

    private val afterKeyword = Regex(
        """(?:验\s*证\s*码|驗\s*證\s*碼|校\s*验\s*码|动\s*态\s*码|登\s*录\s*码|确\s*认\s*码|一\s*次\s*性\s*密\s*码|OTP|code)[^\d０-９]{0,16}([0-9０-９]{4,8})""",
        RegexOption.IGNORE_CASE
    )
    private val digitGroup = Regex("""(?<![0-9０-９])([0-9０-９]{4,8})(?![0-9０-９])""")

    /** 规范化：全角数字→半角，去掉零宽字符，压缩空白 */
    fun normalize(text: String): String {
        var s = Normalizer.normalize(text, Normalizer.Form.NFKC)
        s = s.replace(Regex("[\\u200B-\\u200D\\uFEFF\\u00AD]"), "")
        s = s.replace(Regex("\\s+"), " ").trim()
        return s
    }

    private fun toAsciiDigits(raw: String): String {
        val sb = StringBuilder(raw.length)
        for (ch in raw) {
            when (ch) {
                in '０'..'９' -> sb.append(('0'.code + (ch.code - '０'.code)).toChar())
                else -> sb.append(ch)
            }
        }
        return sb.toString()
    }

    /** 是否像验证码短信（含关键词或「码：数字」），用于收件箱扫描。 */
    fun looksLikeOtpSms(text: String?): Boolean {
        if (text.isNullOrBlank()) return false
        val n = normalize(text)
        return keywordHint.containsMatchIn(n) || codeColonDigits.containsMatchIn(n)
    }

    /**
     * 严格解析：仅从带验证码关键词的短信中取码。
     * 例：【深度求索】验证码：483349，有效期 5 分钟 → 483349
     */
    fun extractStrict(text: String?): String? {
        if (text.isNullOrBlank() || !looksLikeOtpSms(text)) return null
        val n = normalize(text)

        afterKeyword.find(n)?.groupValues?.getOrNull(1)?.let { code ->
            val ascii = toAsciiDigits(code)
            if (isPlausibleOtp(ascii)) return ascii
        }
        codeColonDigits.find(n)?.groupValues?.getOrNull(1)?.let { code ->
            val ascii = toAsciiDigits(code)
            if (isPlausibleOtp(ascii)) return ascii
        }
        // 有关键词但格式特殊时，取文中最不像年份的 4～8 位数字
        return digitGroup.findAll(n)
            .mapNotNull { it.groupValues.getOrNull(1) }
            .map { toAsciiDigits(it) }
            .filter { isPlausibleOtp(it) }
            .lastOrNull()
    }

    /**
     * 宽松解析（实时广播等）：先严格，再退化到任意 4～8 位。
     */
    fun extract(text: String?): String? {
        extractStrict(text)?.let { return it }
        if (text.isNullOrBlank()) return null
        val n = normalize(text)
        return digitGroup.findAll(n)
            .mapNotNull { it.groupValues.getOrNull(1) }
            .map { toAsciiDigits(it) }
            .filter { isPlausibleOtp(it) }
            .lastOrNull()
    }

    /** 排除明显不是验证码的数字（年份、过短等）。 */
    private fun isPlausibleOtp(code: String): Boolean {
        if (code.length !in 4..8) return false
        // 常见年份误匹配
        if (code.length == 4 && code.toIntOrNull() in 1990..2099) return false
        return true
    }
}
