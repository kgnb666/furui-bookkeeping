package com.example.campus_ledger

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart 与原生之间的桥。
 *
 * Flutter 侧负责把 token 与接口地址传下来、以及触发「立即刷新」；
 * 后台的定时刷新由 WorkManager 独立完成，不依赖 Flutter 引擎存活。
 */
class LedgerNotificationPlugin(
    private val activity: Activity,
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "campus_ledger/notification"
        private const val REQUEST_CODE_NOTIFICATION = 8801
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isEnabled" -> result.success(LedgerPrefs(context).enabled)
            "hasPermission" -> result.success(hasNotificationPermission())
            "enable" -> handleEnable(call, result)
            "disable" -> handleDisable(result)
            "refresh" -> handleRefresh(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleEnable(call: MethodCall, result: MethodChannel.Result) {
        val prefs = LedgerPrefs(context)
        call.argument<String>("token")?.let { prefs.token = it }
        call.argument<String>("baseUrl")?.let { prefs.baseUrl = it }
        prefs.enabled = true

        LedgerNotifier.ensureChannel(context)
        LedgerScheduler.start(context)
        LedgerScheduler.refreshNow(context) // 立刻出第一条，用户不用等 30 分钟

        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        // Android 13 起通知需要运行时授权：挂起结果，等用户点完再回给 Dart
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_CODE_NOTIFICATION,
        )
    }

    private fun handleDisable(result: MethodChannel.Result) {
        val prefs = LedgerPrefs(context)
        prefs.enabled = false
        LedgerScheduler.stop(context)
        LedgerNotifier.cancel(context)
        result.success(true)
    }

    private fun handleRefresh(call: MethodCall, result: MethodChannel.Result) {
        val prefs = LedgerPrefs(context)
        call.argument<String>("token")?.let { prefs.token = it }
        call.argument<String>("baseUrl")?.let { prefs.baseUrl = it }
        if (prefs.enabled) {
            LedgerScheduler.refreshNow(context)
        }
        result.success(true)
    }

    /** 供 MainActivity 转发权限回调；返回是否已消费该请求。 */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE_NOTIFICATION) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    private fun hasNotificationPermission(): Boolean {
        // Android 13 以下不需要该权限，装上即生效
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }
}
