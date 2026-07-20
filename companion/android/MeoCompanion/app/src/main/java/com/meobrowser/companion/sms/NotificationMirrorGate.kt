package com.meobrowser.companion.sms

import java.util.concurrent.ConcurrentHashMap

/**
 * 通知镜像去重与限流：同 id 60s；全局约 5 条/秒。
 */
object NotificationMirrorGate {
    private const val DEDUPE_MS = 60_000L
    private const val MAX_PER_SECOND = 5

    private val recentIds = ConcurrentHashMap<String, Long>()
    private val secondBuckets = ConcurrentHashMap<Long, Int>()

    @Synchronized
    fun tryAdmit(id: String): Boolean {
        val now = System.currentTimeMillis()
        prune(now)
        val last = recentIds[id]
        if (last != null && now - last < DEDUPE_MS) {
            return false
        }
        val bucket = now / 1000L
        val count = secondBuckets[bucket] ?: 0
        if (count >= MAX_PER_SECOND) {
            return false
        }
        secondBuckets[bucket] = count + 1
        recentIds[id] = now
        return true
    }

    private fun prune(now: Long) {
        val idIter = recentIds.entries.iterator()
        while (idIter.hasNext()) {
            val e = idIter.next()
            if (now - e.value >= DEDUPE_MS) {
                idIter.remove()
            }
        }
        val currentBucket = now / 1000L
        val bucketIter = secondBuckets.keys.iterator()
        while (bucketIter.hasNext()) {
            val b = bucketIter.next()
            if (b < currentBucket - 2) {
                bucketIter.remove()
            }
        }
    }
}
