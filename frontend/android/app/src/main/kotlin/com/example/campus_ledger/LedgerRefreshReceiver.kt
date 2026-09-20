package com.example.campus_ledger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

/**
 * 后台刷新常驻通知的执行体。
 *
 * 由 AlarmManager 定时触发，或在 App 内手动触发（记账后、切回前台）。
 *
 * onReceive 跑在主线程，网络请求不能直接在这里做，
 * 因此用 goAsync() + 子线程，做完再调用 pendingResult.finish()。
 */
class LedgerRefreshReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val prefs = LedgerPrefs(appContext)
        if (!prefs.enabled) return

        val pendingResult = goAsync()
        thread(name = "ledger-notify-refresh") {
            try {
                refresh(appContext, prefs)
            } finally {
                // 自续期：安排下一次。放在 finally 里，即使这次取数失败也不会断链。
                if (prefs.enabled) {
                    LedgerScheduler.scheduleNext(appContext, LedgerScheduler.intervalMs())
                }
                pendingResult.finish()
            }
        }
    }

    private fun refresh(context: Context, prefs: LedgerPrefs) {
        val token = prefs.token
        if (token.isNullOrBlank()) {
            LedgerNotifier.showProblem(context, "请先打开 App 登录")
            return
        }
        try {
            val snapshot = LedgerApi.fetch(prefs.baseUrl, token, LedgerApi.currentMonth())
            LedgerNotifier.show(context, snapshot)
        } catch (e: LedgerApiException) {
            if (e.statusCode == 401 || e.statusCode == 403) {
                // 凭证失效，等用户重新登录，重试没有意义
                LedgerNotifier.showProblem(context, "登录已过期，请打开 App 重新登录")
            } else {
                LedgerNotifier.showProblem(context, "网络异常，稍后自动重试")
            }
        } catch (e: Exception) {
            LedgerNotifier.showProblem(context, "网络异常，稍后自动重试")
        }
    }
}
