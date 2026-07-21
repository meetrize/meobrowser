package com.meobrowser.companion.call

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.meobrowser.companion.channel.CompanionSession
import java.util.UUID
import java.util.concurrent.Executor

/**
 * 通话状态机：RINGING → active → ended/missed。
 * 号码优先来自 CallScreening；无号码时不推（私人号码除外）。
 */
object CallStateMonitor {
    private const val TAG = "MeoCallMonitor"

    @Volatile
    private var registered = false

    @Volatile
    private var activeCallId: String? = null

    @Volatile
    private var activeNumber: String = ""

    @Volatile
    private var activeNumberRaw: String = ""

    @Volatile
    private var activePresentation: String = "allowed"

    @Volatile
    private var wasRinging = false

    @Volatile
    private var wentOffhook = false

    @Volatile
    private var didPushRinging = false

    private var telephonyCallback: Any? = null
    private var phoneStateListener: PhoneStateListener? = null

    /** Call Screening 在响铃前注入号码。 */
    fun noteIncomingNumber(
        numberRaw: String?,
        presentation: String = "allowed",
    ) {
        val raw = numberRaw.orEmpty().trim()
        activeNumberRaw = raw
        activeNumber = NumberNormalizer.toE164(raw)
        activePresentation = presentation
        if (activeCallId == null) {
            activeCallId = UUID.randomUUID().toString()
        }
        Log.i(TAG, "noteIncomingNumber id=${activeCallId?.take(8)} rawLen=${raw.length}")
    }

    /** Screening 回调后立即推一条 ringing（避免等 Telephony 回调丢号）。 */
    fun onScreenedIncoming(context: Context) {
        wasRinging = true
        if (didPushRinging) return
        push(context, "ringing")
        didPushRinging = true
    }

    fun start(context: Context) {
        if (registered) return
        val app = context.applicationContext
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "READ_PHONE_STATE not granted; monitor not started")
            return
        }
        val tm = app.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) {
                        onNativeCallState(app, state)
                    }
                }
                val executor: Executor = ContextCompat.getMainExecutor(app)
                tm.registerTelephonyCallback(executor, cb)
                telephonyCallback = cb
            } else {
                @Suppress("DEPRECATION")
                val listener = object : PhoneStateListener() {
                    @Deprecated("Deprecated in Java")
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                        if (!phoneNumber.isNullOrBlank() && activeNumberRaw.isBlank()) {
                            noteIncomingNumber(phoneNumber)
                        }
                        onNativeCallState(app, state)
                    }
                }
                @Suppress("DEPRECATION")
                tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                phoneStateListener = listener
            }
            registered = true
            Log.i(TAG, "CallStateMonitor registered")
        } catch (e: Exception) {
            Log.e(TAG, "register failed", e)
        }
    }

    fun stop(context: Context) {
        if (!registered) return
        val app = context.applicationContext
        val tm = app.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val cb = telephonyCallback as? TelephonyCallback
                if (tm != null && cb != null) {
                    tm.unregisterTelephonyCallback(cb)
                }
            } else {
                @Suppress("DEPRECATION")
                phoneStateListener?.let { tm?.listen(it, PhoneStateListener.LISTEN_NONE) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "unregister failed", e)
        }
        telephonyCallback = null
        phoneStateListener = null
        registered = false
    }

    private fun onNativeCallState(context: Context, state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                wasRinging = true
                wentOffhook = false
                if (activeCallId == null) {
                    activeCallId = UUID.randomUUID().toString()
                }
                if (!didPushRinging) {
                    push(context, "ringing")
                    didPushRinging = true
                }
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                wentOffhook = true
                if (activeCallId == null) {
                    activeCallId = UUID.randomUUID().toString()
                }
                push(context, "active")
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                val id = activeCallId
                if (id != null && wasRinging) {
                    val endState = if (wentOffhook) "ended" else "missed"
                    push(context, endState)
                }
                resetCall()
            }
        }
    }

    private fun push(context: Context, state: String) {
        if (!CallAlertPrefs(context).callAlertEnabled) {
            Log.i(TAG, "call alert disabled; skip state=$state")
            return
        }
        // 设计 D1：无号码不推（私人号码除外用 presentation）
        val number = activeNumber
        val raw = activeNumberRaw
        if (number.isBlank() && raw.isBlank() && activePresentation == "allowed") {
            Log.i(TAG, "no number yet; skip state=$state (await screening)")
            return
        }
        val id = activeCallId ?: UUID.randomUUID().toString().also { activeCallId = it }
        val now = System.currentTimeMillis()
        val payload = CallEventPayload(
            id = id,
            state = state,
            number = number,
            numberRaw = raw.ifBlank { NumberNormalizer.digitsOnly(number) },
            presentation = activePresentation,
            contactName = "",
            ts = now / 1000L,
            eventMs = now,
        )
        CompanionSession.pushCallEvent(context, payload)
    }

    private fun resetCall() {
        activeCallId = null
        activeNumber = ""
        activeNumberRaw = ""
        activePresentation = "allowed"
        wasRinging = false
        wentOffhook = false
        didPushRinging = false
    }
}
