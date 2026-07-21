package com.meobrowser.companion.call

import android.telecom.Call
import android.telecom.CallScreeningService
import android.util.Log

/**
 * 仅用于获取来电号码；一律放行（本期不做拒接/黑名单）。
 * 用户须授予 ROLE_CALL_SCREENING。
 */
class MeoCallScreeningService : CallScreeningService() {
    override fun onScreenCall(callDetails: Call.Details) {
        val handle = callDetails.handle
        val raw = handle?.schemeSpecificPart.orEmpty().trim()
        // 部分 SDK stub 无 getCallerNumberPresentation；用号码是否为空推断。
        val presentation = when {
            raw.isBlank() -> "restricted"
            else -> "allowed"
        }
        Log.i(TAG, "onScreenCall presentation=$presentation numberLen=${raw.length}")
        CallStateMonitor.noteIncomingNumber(
            numberRaw = raw,
            presentation = presentation,
        )
        val response = CallResponse.Builder()
            .setDisallowCall(false)
            .setRejectCall(false)
            .setSkipCallLog(false)
            .setSkipNotification(false)
            .build()
        respondToCall(callDetails, response)

        if (CallAlertPrefs(this).callAlertEnabled) {
            CallStateMonitor.onScreenedIncoming(this)
        }
    }

    companion object {
        private const val TAG = "MeoCallScreening"
    }
}
