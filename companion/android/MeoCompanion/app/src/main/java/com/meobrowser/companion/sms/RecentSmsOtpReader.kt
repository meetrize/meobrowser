package com.meobrowser.companion.sms

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.Telephony
import android.util.Log
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

data class RecentOtpSms(
    val address: String,
    val body: String,
    val dateMs: Long,
    val code: String,
    val rowId: Long = 0L,
) {
    fun dateLabel(): String {
        return SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(dateMs))
    }

    fun bodyPreview(maxLen: Int = 120): String {
        val oneLine = body.replace('\n', ' ').trim()
        return if (oneLine.length <= maxLen) oneLine else oneLine.take(maxLen) + "…"
    }
}

/**
 * 读取最近一条验证码短信。
 *
 * 排序优先级（高 → 低）：
 * 1. 正文含「深度求索」或发件人含 106866
 * 2. 时间 date 更新
 * 3. _id 更大
 *
 * 绝不能只按「扫描行号」或错误 _id 把 2023 的旧短信当成最新。
 */
object RecentSmsOtpReader {

    private const val TAG = "RecentSmsOtp"
    private val STALE_MS = TimeUnit.DAYS.toMillis(30)

    fun hasReadPermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(context, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun findLatest(context: Context, errorOut: ((String) -> Unit)? = null): RecentOtpSms? {
        if (!hasReadPermission(context)) {
            errorOut?.invoke("没有读取短信权限，请先在设置向导中授予短信权限")
            return null
        }

        val now = System.currentTimeMillis()
        val attempts = listOf(
            QueryAttempt(Uri.parse("content://sms"), "body LIKE ?", arrayOf("%深度求索%"), "_id DESC", "deepseek"),
            QueryAttempt(
                Uri.parse("content://sms"),
                "address LIKE ? OR address=?",
                arrayOf("%106866701000030%", "106866701000030"),
                "_id DESC",
                "addr-exact"
            ),
            QueryAttempt(Uri.parse("content://sms"), "address LIKE ?", arrayOf("%106866%"), "_id DESC", "addr-106866"),
            QueryAttempt(
                Uri.parse("content://sms"),
                "body LIKE ? OR body LIKE ?",
                arrayOf("%验证码%", "%驗證碼%"),
                "_id DESC",
                "body-otp"
            ),
            QueryAttempt(
                Uri.parse("content://sms/inbox"),
                "body LIKE ? OR body LIKE ?",
                arrayOf("%验证码%", "%驗證碼%"),
                "_id DESC",
                "inbox-otp"
            ),
            QueryAttempt(Uri.parse("content://sms/inbox"), null, null, "_id DESC", "inbox-all"),
            QueryAttempt(Uri.parse("content://sms"), null, null, "_id DESC", "sms-all"),
            QueryAttempt(Uri.parse("content://sms"), null, null, "date DESC", "sms-date"),
        )

        var bestRecent: RecentOtpSms? = null // 30 天内
        var bestAny: RecentOtpSms? = null
        val notes = mutableListOf<String>()

        for (attempt in attempts) {
            val result = scan(context, attempt, now)
            if (result == null) {
                notes.add("${attempt.label}=null")
                continue
            }
            notes.add(
                "${attempt.label}:n=${result.scanned},ds=${result.deepseekHits}," +
                    "best=${result.best?.code ?: "-"}@${result.best?.dateLabel() ?: "-"}"
            )

            val hit = result.best ?: continue
            bestAny = selectBetter(bestAny, hit, now)
            if (now - hit.dateMs <= STALE_MS) {
                bestRecent = selectBetter(bestRecent, hit, now)
            }

            // 定点查到「深度求索 / 106866」且不太旧 → 直接用
            if ((attempt.label.startsWith("deepseek") || attempt.label.startsWith("addr-")) &&
                isPreferredSender(hit) &&
                now - hit.dateMs <= STALE_MS
            ) {
                Log.i(TAG, "early preferred ${attempt.label} ${hit.code} ${hit.dateLabel()}")
                return hit
            }
        }

        // 只要有 30 天内的，绝不用 2023 那种陈年旧码
        val picked = bestRecent ?: bestAny
        if (picked != null) {
            if (bestRecent == null && now - picked.dateMs > STALE_MS) {
                // 仅有旧短信：仍返回，但调用方可看到时间异常
                Log.w(TAG, "only stale otp ${picked.dateLabel()} code=${picked.code}")
            }
            return picked
        }

        val dump = dumpNewestRaw(context, 8)
        errorOut?.invoke(
            "没有解析到验证码短信。\n${notes.take(8).joinToString("\n")}\n收件箱最新：\n$dump"
        )
        return null
    }

    private fun isPreferredSender(sms: RecentOtpSms): Boolean {
        return sms.body.contains("深度求索") ||
            sms.address.contains("106866") ||
            sms.address.contains("106866701000030")
    }

    /** 返回更「新 / 更相关」的一条 */
    private fun selectBetter(current: RecentOtpSms?, candidate: RecentOtpSms, now: Long): RecentOtpSms {
        if (current == null) return candidate
        val cs = score(current, now)
        val ns = score(candidate, now)
        if (ns != cs) return if (ns > cs) candidate else current
        if (candidate.dateMs != current.dateMs) {
            return if (candidate.dateMs > current.dateMs) candidate else current
        }
        return if (candidate.rowId > current.rowId) candidate else current
    }

    private fun score(sms: RecentOtpSms, now: Long): Int {
        var s = 0
        if (sms.body.contains("深度求索")) s += 10_000
        if (sms.address.contains("106866701000030")) s += 8_000
        if (sms.address.contains("106866")) s += 5_000

        val age = now - sms.dateMs
        when {
            age < TimeUnit.HOURS.toMillis(1) -> s += 3_000
            age < TimeUnit.HOURS.toMillis(24) -> s += 2_500
            age < TimeUnit.DAYS.toMillis(7) -> s += 2_000
            age < TimeUnit.DAYS.toMillis(30) -> s += 1_000
            age > TimeUnit.DAYS.toMillis(365) -> s -= 5_000
        }
        return s
    }

    @SuppressLint("Range")
    fun dumpNewestRaw(context: Context, limit: Int = 8): String {
        for (uri in listOf(Uri.parse("content://sms/inbox"), Uri.parse("content://sms"))) {
            val cursor = try {
                context.contentResolver.query(uri, null, null, null, "_id DESC")
            } catch (_: Exception) {
                null
            } ?: continue
            cursor.use { c ->
                val idxId = columnIndex(c, "_id", "id", Telephony.Sms._ID)
                val idxAddr = columnIndex(c, "address", Telephony.Sms.ADDRESS)
                val idxBody = columnIndex(c, "body", Telephony.Sms.BODY)
                val idxDate = columnIndex(c, "date", Telephony.Sms.DATE)
                val lines = mutableListOf<String>()
                var n = 0
                while (c.moveToNext() && n < limit) {
                    n++
                    val id = if (idxId >= 0) c.getLong(idxId) else -1
                    val addr = if (idxAddr >= 0) c.getString(idxAddr) ?: "?" else "?"
                    val body = if (idxBody >= 0) c.getString(idxBody) ?: "(空)" else "(无列)"
                    val rawDate = if (idxDate >= 0) c.getLong(idxDate) else 0L
                    val clip = body.replace('\n', ' ').let { if (it.length > 48) it.take(48) + "…" else it }
                    lines.add("$n. id=$id addr=$addr date=$rawDate\n   $clip")
                }
                if (lines.isNotEmpty()) return "uri=$uri\n" + lines.joinToString("\n")
            }
        }
        return "（读不到任何短信）"
    }

    @SuppressLint("Range")
    private fun scan(context: Context, attempt: QueryAttempt, now: Long): ScanResult? {
        val cursor = try {
            context.contentResolver.query(
                attempt.uri,
                null,
                attempt.selection,
                attempt.selectionArgs,
                attempt.sortOrder
            )
        } catch (e: Exception) {
            Log.w(TAG, "query ${attempt.label}", e)
            null
        } ?: return null

        cursor.use { c ->
            val idxId = columnIndex(c, "_id", "id", Telephony.Sms._ID)
            val idxAddr = columnIndex(c, "address", Telephony.Sms.ADDRESS)
            val idxBody = columnIndex(c, "body", Telephony.Sms.BODY)
            val idxDate = columnIndex(c, "date", Telephony.Sms.DATE)
            val idxSent = columnIndex(c, "date_sent", Telephony.Sms.DATE_SENT)
            if (idxBody < 0) return ScanResult(0, 0, null)

            val sortDescId = attempt.sortOrder?.contains("_id", true) == true &&
                attempt.sortOrder.contains("DESC", true)
            val sortDescDate = attempt.sortOrder?.contains("date", true) == true &&
                attempt.sortOrder.contains("DESC", true)

            var scanned = 0
            var deepseekHits = 0
            var best: RecentOtpSms? = null

            while (c.moveToNext()) {
                scanned++
                val body = c.getString(idxBody) ?: continue
                val address = if (idxAddr >= 0) c.getString(idxAddr).orEmpty() else ""
                val rawDate = if (idxDate >= 0) c.getLong(idxDate) else 0L
                val rawSent = if (idxSent >= 0) c.getLong(idxSent) else 0L
                var dateMs = coerceDateMs(rawDate, rawSent, now)

                // 缺 date 且按 _id/date DESC 扫描：越靠前越新，用 now 递减近似
                if (dateMs <= 0L) {
                    dateMs = if (sortDescId || sortDescDate) {
                        now - scanned
                    } else {
                        0L
                    }
                }

                // 真实 _id；没有列时：DESC 游标用大数递减，避免「行号越大越旧」却被当成更新
                val rowId = when {
                    idxId >= 0 -> c.getLong(idxId)
                    sortDescId || sortDescDate -> Long.MAX_VALUE - scanned
                    else -> scanned.toLong()
                }

                if (body.contains("深度求索") || address.contains("106866")) deepseekHits++

                val interested =
                    body.contains("深度求索") ||
                        address.contains("106866") ||
                        body.contains("验证码") ||
                        body.contains("驗證碼") ||
                        OtpParser.looksLikeOtpSms(body)
                if (!interested) {
                    if (scanned >= 5000) break
                    continue
                }

                val code = OtpParser.extractStrict(body)
                    ?: OtpParser.extract(body)
                    ?: Regex("""验证码\s*[:：]?\s*([0-9]{4,8})""")
                        .find(OtpParser.normalize(body))
                        ?.groupValues?.getOrNull(1)
                    ?: continue

                val cand = RecentOtpSms(
                    address = address.ifBlank { "未知发件人" },
                    body = body,
                    dateMs = if (dateMs > 0L) dateMs else now - scanned,
                    code = code,
                    rowId = rowId
                )
                best = selectBetter(best, cand, now)

                if (scanned >= 5000) break
            }

            Log.i(
                TAG,
                "${attempt.label}: n=$scanned ds=$deepseekHits " +
                    "best=${best?.code} date=${best?.dateLabel()} id=${best?.rowId}"
            )
            return ScanResult(scanned, deepseekHits, best)
        }
    }

    private fun coerceDateMs(rawDate: Long, rawSent: Long, nowMs: Long): Long {
        fun one(raw: Long): Long {
            if (raw <= 0L) return 0L
            if (raw in 1_000_000_000L..9_999_999_999L) return raw * 1000L
            if (raw >= 1_000_000_000_000L) return raw
            return raw
        }
        val best = maxOf(one(rawDate), one(rawSent))
        if (best > nowMs + TimeUnit.DAYS.toMillis(2)) return 0L
        return best
    }

    private fun columnIndex(cursor: Cursor, vararg names: String): Int {
        for (name in names) {
            val idx = cursor.getColumnIndex(name)
            if (idx >= 0) return idx
        }
        // 再试一遍忽略大小写
        val lower = names.map { it.lowercase(Locale.US) }
        for (i in 0 until cursor.columnCount) {
            val col = cursor.getColumnName(i)?.lowercase(Locale.US) ?: continue
            if (col in lower) return i
        }
        return -1
    }

    private data class QueryAttempt(
        val uri: Uri,
        val selection: String?,
        val selectionArgs: Array<String>?,
        val sortOrder: String?,
        val label: String,
    )

    private data class ScanResult(
        val scanned: Int,
        val deepseekHits: Int,
        val best: RecentOtpSms?,
    )
}
