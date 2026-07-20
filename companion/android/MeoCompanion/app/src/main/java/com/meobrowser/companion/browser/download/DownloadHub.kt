package com.meobrowser.companion.browser.download

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import android.webkit.URLUtil

data class DownloadEntry(
    val id: Long,
    val url: String,
    val fileName: String,
    val status: Int
)

class DownloadHub(private val context: Context) {
    private val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    fun enqueue(url: String, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        val fileName = URLUtil.guessFileName(url, contentDisposition, mimeType)
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setMimeType(mimeType)
            setTitle(fileName)
            setDescription(url)
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, fileName)
            val cookie = CookieManager.getInstance().getCookie(url)
            if (!cookie.isNullOrBlank()) addRequestHeader("Cookie", cookie)
            if (!userAgent.isNullOrBlank()) addRequestHeader("User-Agent", userAgent)
            allowScanningByMediaScanner()
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
        }
        dm.enqueue(request)
    }

    fun recent(limit: Int = 30): List<DownloadEntry> {
        val q = DownloadManager.Query().setFilterByStatus(
            DownloadManager.STATUS_SUCCESSFUL or
                DownloadManager.STATUS_RUNNING or
                DownloadManager.STATUS_PENDING or
                DownloadManager.STATUS_FAILED
        )
        val out = mutableListOf<DownloadEntry>()
        dm.query(q)?.use { c ->
            val idIdx = c.getColumnIndex(DownloadManager.COLUMN_ID)
            val urlIdx = c.getColumnIndex(DownloadManager.COLUMN_URI)
            val nameIdx = c.getColumnIndex(DownloadManager.COLUMN_TITLE)
            val statusIdx = c.getColumnIndex(DownloadManager.COLUMN_STATUS)
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    DownloadEntry(
                        id = c.getLong(idIdx),
                        url = c.getString(urlIdx) ?: "",
                        fileName = c.getString(nameIdx) ?: "",
                        status = c.getInt(statusIdx)
                    )
                )
            }
        }
        return out
    }
}
