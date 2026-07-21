package com.meobrowser.companion.call

import org.json.JSONObject

data class CallEventPayload(
    val id: String,
    val state: String,
    val number: String,
    val numberRaw: String,
    val presentation: String,
    val contactName: String,
    val ts: Long,
    val eventMs: Long,
) {
    fun toJson(deviceToken: String): JSONObject {
        return JSONObject().apply {
            put("v", 1)
            put("type", "call_event")
            put("deviceToken", deviceToken)
            put("id", id)
            put("state", state)
            put("number", number)
            put("numberRaw", numberRaw)
            put("presentation", presentation)
            if (contactName.isNotBlank()) {
                put("contactName", contactName)
            }
            put("ts", ts)
            put("eventMs", eventMs)
        }
    }
}

object NumberNormalizer {
    /** 尽量产出 +86…；失败则返回清洗后的数字串。 */
    fun toE164(raw: String?): String {
        val digits = raw.orEmpty().filter { it.isDigit() }
        if (digits.isEmpty()) return ""
        if (digits.startsWith("86") && digits.length >= 13) {
            return "+$digits"
        }
        if (digits.length == 11 && digits.startsWith("1")) {
            return "+86$digits"
        }
        return if (raw.orEmpty().startsWith("+")) {
            "+" + digits
        } else {
            digits
        }
    }

    fun digitsOnly(raw: String?): String = raw.orEmpty().filter { it.isDigit() }
}
