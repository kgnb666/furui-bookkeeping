package com.example.campus_ledger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 开机后重新安排刷新。
 * AlarmManager 里的闹钟在重启后会全部丢失，所以需要这一步。
 */
class LedgerBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = LedgerPrefs(context.applicationContext)
        if (!prefs.enabled) return

        LedgerScheduler.start(context.applicationContext)
        // 开机后先补一次，免得通知栏停在上次关机前的数字
        LedgerScheduler.refreshNow(context.applicationContext)
    }
}
