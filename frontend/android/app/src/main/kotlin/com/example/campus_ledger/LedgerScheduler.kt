package com.example.campus_ledger

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * 常驻通知的刷新调度。
 *
 * 用系统自带的 AlarmManager，不引入任何第三方或 AndroidX 依赖：
 * 之前试过 WorkManager，但 release 构建的 R8 会把 WorkManager 依赖的 Room
 * 生成类削掉，App 启动即崩（NoSuchMethodException: WorkDatabase_Impl.<init>），
 * 而 AlarmManager 是平台 API，没有这层反射和代码生成，不存在该问题。
 *
 * 调度方式：setAndAllowWhileIdle 自续期——每次刷新完成后安排下一次。
 * 相比 setInexactRepeating，这种方式在 Doze 下也能按约 30 分钟触发；
 * 每个 App 在 Doze 下调用 setAndAllowWhileIdle 的频率上限约 9 分钟一次，
 * 30 分钟的间隔不会触到限制。
 */
object LedgerScheduler {

    /** 刷新间隔。改这一处即可调整频率。 */
    private const val INTERVAL_MS = 30 * 60 * 1000L

    private const val REQUEST_CODE = 8802

    private fun alarmManager(context: Context) =
        context.getSystemService(AlarmManager::class.java)

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, LedgerRefreshReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** 开启后台刷新：安排第一次，之后由接收器自续期。 */
    fun start(context: Context) {
        scheduleNext(context, INTERVAL_MS)
    }

    /** 关闭后台刷新。 */
    fun stop(context: Context) {
        alarmManager(context)?.cancel(pendingIntent(context))
    }

    /** 安排下一次刷新；由开启动作和每次刷新结束后的自续期调用。 */
    fun scheduleNext(context: Context, delayMs: Long) {
        val manager = alarmManager(context) ?: return
        manager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + delayMs,
            pendingIntent(context),
        )
    }

    /** 立即刷新一次（打开 App、记账后、切回前台时调用）。 */
    fun refreshNow(context: Context) {
        context.sendBroadcast(Intent(context, LedgerRefreshReceiver::class.java))
    }

    /** 刷新间隔（毫秒），供接收器自续期时使用。 */
    fun intervalMs(): Long = INTERVAL_MS
}
