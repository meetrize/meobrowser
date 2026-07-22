package com.meobrowser.companion.a11y

import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import java.lang.reflect.Method

/**
 * 后台调起微信：应对 Android BAL 与 MIUI「后台弹出界面」(AppOps 10021)。
 */
object WeChatReplyLaunchHelper {
    private const val TAG = "WeChatReplyLaunch"
    /** MIUI / HyperOS：后台弹出界面 */
    private const val MIUI_OP_BACKGROUND_START = 10021

    fun sendPendingIntent(pi: PendingIntent): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= 34) {
                val opts = ActivityOptions.makeBasic().apply {
                    setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED,
                    )
                }
                pi.send(null, 0, null, null, null, null, opts.toBundle())
            } else {
                pi.send()
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "PendingIntent.send failed", e)
            false
        }
    }

    fun launchWeChatPackage(context: Context): Boolean {
        val launch = context.packageManager.getLaunchIntentForPackage(WeChatReplyIntentCache.WECHAT_PACKAGE)
            ?: return false
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        return try {
            if (Build.VERSION.SDK_INT >= 34) {
                val opts = ActivityOptions.makeBasic()
                context.startActivity(launch, opts.toBundle())
            } else {
                context.startActivity(launch)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "startActivity WeChat failed", e)
            false
        }
    }

    fun startTrampoline(context: Context, contact: String, contentIntent: PendingIntent?) {
        val i = Intent(context, WeChatReplyTrampolineActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(WeChatReplyTrampolineActivity.EXTRA_CONTACT, contact)
            if (contentIntent != null) {
                putExtra(WeChatReplyTrampolineActivity.EXTRA_CONTENT_INTENT, contentIntent)
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                context.startActivity(i, ActivityOptions.makeBasic().toBundle())
            } else {
                context.startActivity(i)
            }
            Log.i(TAG, "trampoline started")
        } catch (e: Exception) {
            Log.w(TAG, "trampoline failed", e)
        }
    }

    /**
     * @return null=非 MIUI 或无法探测；true=允许；false=拒绝/忽略（后台无法弹微信）
     */
    fun isMiuiBackgroundStartAllowed(context: Context): Boolean? {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) ?: return null
            val checkOp: Method = appOps.javaClass.getMethod(
                "checkOpNoThrow",
                Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType,
                String::class.java,
            )
            val mode = checkOp.invoke(
                appOps,
                MIUI_OP_BACKGROUND_START,
                android.os.Process.myUid(),
                context.packageName,
            ) as Int
            // 0=MODE_ALLOWED, 1=MODE_IGNORED, 2=MODE_ERRORED, …
            when (mode) {
                0 -> true
                else -> false
            }
        } catch (e: Exception) {
            Log.i(TAG, "miui op probe skip: ${e.message}")
            null
        }
    }

    fun openBackgroundPopupSettings(context: Context): Boolean {
        val pkg = context.packageName
        val candidates = listOf(
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                putExtra("extra_pkgname", pkg)
                setPackage("com.miui.securitycenter")
            },
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                )
                putExtra("extra_pkgname", pkg)
            },
            Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                component = ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
                )
                putExtra("extra_pkgname", pkg)
            },
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", pkg, null)
            },
        )
        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                    return true
                }
            } catch (_: Exception) {
            }
        }
        return false
    }
}
