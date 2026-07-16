package com.meobrowser.companion.channel

import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 长度前缀 JSON 客户端，对接 Mac CompanionBonjourServer。
 * 注意：disconnect / 主动重连时不可误触发 onClosed（否则 Service 会 stopSelf 杀掉连接）。
 */
class CompanionClient {
    private var socket: Socket? = null
    private var input: DataInputStream? = null
    private var output: DataOutputStream? = null
    private val running = AtomicBoolean(false)
    private val intentionalClose = AtomicBoolean(false)

    @Volatile
    var onMessage: ((JSONObject) -> Unit)? = null

    /** 仅非主动断开时回调（对端关闭 / 网络错误）。 */
    @Volatile
    var onClosed: (() -> Unit)? = null

    val isConnected: Boolean
        get() {
            val s = socket ?: return false
            return running.get() && s.isConnected && !s.isClosed
        }

    fun connect(host: String, port: Int, timeoutMs: Int = 8000) {
        // 主动重连：先安静关掉旧连接，勿走 onClosed → Service 自杀。
        disconnect(quiet = true)
        val s = Socket()
        s.connect(InetSocketAddress(host, port), timeoutMs)
        s.tcpNoDelay = true
        s.keepAlive = true
        socket = s
        input = DataInputStream(s.getInputStream())
        output = DataOutputStream(s.getOutputStream())
        intentionalClose.set(false)
        running.set(true)
        Thread({ readLoop() }, "meo-companion-read").start()
    }

    fun disconnect(quiet: Boolean = false) {
        if (quiet) {
            intentionalClose.set(true)
        }
        running.set(false)
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null
        input = null
        output = null
    }

    @Synchronized
    fun send(json: JSONObject) {
        val out = output ?: throw IllegalStateException("not connected")
        val s = socket
        if (s == null || s.isClosed || !running.get()) {
            throw IllegalStateException("not connected")
        }
        val bytes = json.toString().toByteArray(Charsets.UTF_8)
        if (bytes.size > 64 * 1024) throw IllegalArgumentException("payload too large")
        val header = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(bytes.size).array()
        out.write(header)
        out.write(bytes)
        out.flush()
    }

    private fun readLoop() {
        try {
            val inp = input ?: return
            while (running.get()) {
                val length = inp.readInt()
                if (length <= 0 || length > 64 * 1024) break
                val payload = ByteArray(length)
                inp.readFully(payload)
                val json = JSONObject(String(payload, Charsets.UTF_8))
                onMessage?.invoke(json)
            }
        } catch (_: Exception) {
            // connection closed or network error
        } finally {
            val wasIntentional = intentionalClose.getAndSet(false)
            running.set(false)
            if (!wasIntentional) {
                onClosed?.invoke()
            }
        }
    }
}
