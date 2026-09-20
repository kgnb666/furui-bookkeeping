package com.example.campus_ledger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews

/**
 * 常驻通知的渲染与生命周期。
 *
 * 为什么用自定义布局：Android 通知的背景色由系统控制，普通通知改不了背景色，
 * 而需求是「预算充足=绿、快见底=红」。只有自定义布局（RemoteViews）能自己画背景色。
 *
 * 为什么不用前台服务：Android 15 起 dataSync 类型的前台服务每 24 小时最多跑 6 小时，
 * 系统会强制停止。而「常驻通知」本身由系统通知服务持有，App 进程被杀也会继续显示，
 * 配合 WorkManager 定时刷新即可，不需要前台服务。
 */
object LedgerNotifier {

    const val CHANNEL_ID = "ledger_dashboard_v2"

    /** 早期版本用过的渠道 id，升级时顺手删掉，避免在系统设置里留下两条 */
    private const val LEGACY_CHANNEL_ID = "ledger_dashboard"
    const val NOTIFICATION_ID = 1001

    /** 预算使用率阈值（百分数），与需求约定一致。 */
    private const val WARN_RATE = 70.0
    private const val DANGER_RATE = 90.0

    /** 预算状态：决定背景色与文案。 */
    enum class Level { OK, WARN, DANGER, NONE }

    fun levelOf(snapshot: LedgerSnapshot): Level {
        val rate = snapshot.usageRate ?: return Level.NONE
        return when {
            rate >= DANGER_RATE -> Level.DANGER
            rate >= WARN_RATE -> Level.WARN
            else -> Level.OK
        }
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "日常开支看板",
            // 用 DEFAULT：声音与振动都在下面关掉了，看板要「常驻但不打扰」。
            // 实测小米 HyperOS 无论渠道优先级高低，都会把这类通知收纳进「更多通知」，
            // 这是 ROM 自身策略，App 改不了，所以不为了绕它去抬高优先级
            // （HIGH 在原生 Android 上会弹悬浮窗，反而打扰用户）。
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "在通知栏常驻显示今日开支、本月预算与结余"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }

        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)

        // 渠道的优先级创建后无法用代码修改。若已存在的渠道优先级与预期不一致
        // （例如开发过程中调整过），删掉重建，保证升级后行为一致。
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            if (existing.importance == channel.importance) return
            manager.deleteNotificationChannel(CHANNEL_ID)
        }
        manager.createNotificationChannel(channel)
    }

    /** 渲染并发出（或更新）常驻通知。 */
    fun show(context: Context, snapshot: LedgerSnapshot) {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        val level = levelOf(snapshot)
        // 展开态放完整五行，收起态只放两行 + 进度条（系统给收起态的高度有限）
        val full = RemoteViews(context.packageName, R.layout.ledger_notification)
        val compact = RemoteViews(context.packageName, R.layout.ledger_notification_compact)

        // 背景色：这是「绿色 / 红色」预警的落点
        full.setInt(R.id.ledger_root, "setBackgroundColor", backgroundColor(level))
        compact.setInt(R.id.ledger_root_compact, "setBackgroundColor", backgroundColor(level))

        full.setTextViewText(R.id.ledger_title, titleOf(level, snapshot))
        full.setTextViewText(R.id.ledger_today, todayLine(snapshot))
        full.setTextViewText(R.id.ledger_budget, budgetLine(snapshot))
        full.setTextViewText(R.id.ledger_balance, "本月结余 ${money(snapshot.monthBalanceCents)}")

        compact.setTextViewText(R.id.ledger_compact_title, titleOf(level, snapshot))
        compact.setTextViewText(R.id.ledger_compact_line, compactLine(snapshot))

        applyProgress(full, level, snapshot.usageRate)
        applyProgressCompact(compact, level, snapshot.usageRate)

        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ledger)
            .setContentIntent(contentIntent)
            .setContentTitle(titleOf(level, snapshot))
            .setContentText(todayLine(snapshot))
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(compact)
            .setCustomBigContentView(full)
            .setOngoing(true)          // 划不掉
            .setOnlyAlertOnce(true)    // 刷新时不重复提醒
            .setShowWhen(false)
            .setColor(accentColor(level))
            .build()

        manager.notify(NOTIFICATION_ID, notification)
    }

    /**
     * 取数失败时更新通知内容，但保留常驻。
     * 登录过期与网络异常分开提示，避免用户误以为数据是新的。
     */
    fun showProblem(context: Context, message: String) {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val existing = manager.activeNotifications.firstOrNull { it.id == NOTIFICATION_ID }?.notification
        if (existing == null) {
            return // 还没有常驻通知时不主动弹一条，避免打扰
        }
        val full = RemoteViews(context.packageName, R.layout.ledger_notification)
        val compact = RemoteViews(context.packageName, R.layout.ledger_notification_compact)

        full.setInt(R.id.ledger_root, "setBackgroundColor", backgroundColor(Level.NONE))
        full.setTextViewText(R.id.ledger_title, "⚪ 暂时取不到数据")
        full.setTextViewText(R.id.ledger_today, message)
        full.setTextViewText(R.id.ledger_budget, "打开 App 可手动刷新")
        full.setTextViewText(R.id.ledger_balance, "")
        applyProgress(full, Level.NONE, null)

        compact.setInt(R.id.ledger_root_compact, "setBackgroundColor", backgroundColor(Level.NONE))
        compact.setTextViewText(R.id.ledger_compact_title, "⚪ 暂时取不到数据")
        compact.setTextViewText(R.id.ledger_compact_line, message)
        applyProgressCompact(compact, Level.NONE, null)

        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ledger)
            .setContentTitle("暂时取不到数据")
            .setContentText(message)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(compact)
            .setCustomBigContentView(full)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
    }

    // ---- 渲染细节 ----

    private fun titleOf(level: Level, snapshot: LedgerSnapshot): String = when (level) {
        Level.OK -> "🟢 预算充足"
        Level.WARN -> "🟡 注意控制"
        Level.DANGER -> "🔴 预算告急"
        Level.NONE -> "⚪ 未设置预算"
    }.let { base ->
        if (level != Level.NONE && snapshot.usageRate != null) {
            // 自定义布局上方系统已经显示了应用名，这里不再重复「福瑞记账」
            "$base · 已用 ${trimRate(snapshot.usageRate)}%"
        } else {
            base
        }
    }

    /** 今日一行：今日支出与今日收入 */
    private fun todayLine(snapshot: LedgerSnapshot): String =
        "今日 支出 ${moneyShort(snapshot.todayExpenseCents)} · 收入 ${moneyShort(snapshot.todayIncomeCents)}"

    /** 收起态的第二行：把今日与结余压到一行，保证不用展开也能看到关键数字 */
    private fun compactLine(snapshot: LedgerSnapshot): String =
        "今日支 ${moneyShort(snapshot.todayExpenseCents)} · 收 ${moneyShort(snapshot.todayIncomeCents)}" +
            " · 结余 ${moneyShort(snapshot.monthBalanceCents)}"

    private fun budgetLine(snapshot: LedgerSnapshot): String {
        val budget = snapshot.budgetCents
        if (budget == null || budget <= 0L) {
            return "本月支出 ${moneyShort(snapshot.monthExpenseCents)} · 尚未设置月度预算"
        }
        val remaining = budget - snapshot.budgetUsedCents
        return if (remaining >= 0) {
            "预算 ${moneyShort(budget)} · 已用 ${moneyShort(snapshot.budgetUsedCents)} · 剩余 ${moneyShort(remaining)}"
        } else {
            "预算 ${moneyShort(budget)} · 已用 ${moneyShort(snapshot.budgetUsedCents)} · 超支 ${moneyShort(-remaining)}"
        }
    }

    /** 按状态只显示对应颜色的进度条。 */
    private fun applyProgress(views: RemoteViews, level: Level, rate: Double?) {
        val progress = (rate ?: 0.0).coerceIn(0.0, 100.0).toInt()
        val visible = android.view.View.VISIBLE
        val gone = android.view.View.GONE

        views.setViewVisibility(R.id.ledger_bar_ok, if (level == Level.OK) visible else gone)
        views.setViewVisibility(R.id.ledger_bar_warn, if (level == Level.WARN) visible else gone)
        views.setViewVisibility(R.id.ledger_bar_danger, if (level == Level.DANGER) visible else gone)

        when (level) {
            Level.OK -> views.setProgressBar(R.id.ledger_bar_ok, 100, progress, false)
            Level.WARN -> views.setProgressBar(R.id.ledger_bar_warn, 100, progress, false)
            Level.DANGER -> views.setProgressBar(R.id.ledger_bar_danger, 100, progress, false)
            Level.NONE -> Unit
        }
    }

    private fun backgroundColor(level: Level): Int = when (level) {
        Level.OK -> Color.parseColor("#E4F2EC")
        Level.WARN -> Color.parseColor("#FFF1D6")
        Level.DANGER -> Color.parseColor("#FCE4E4")
        Level.NONE -> Color.parseColor("#FFF6E8")
    }

    private fun accentColor(level: Level): Int = when (level) {
        Level.OK -> Color.parseColor("#2E9E6B")
        Level.WARN -> Color.parseColor("#F5A524")
        Level.DANGER -> Color.parseColor("#D64545")
        Level.NONE -> Color.parseColor("#F5A524")
    }

    /** 分值 -> ¥1,238.33 */
    fun money(cents: Long): String {
        val negative = cents < 0
        val abs = Math.abs(cents)
        val yuan = abs / 100
        val fen = abs % 100
        val grouped = java.text.DecimalFormat("#,###").format(yuan)
        return (if (negative) "-¥" else "¥") + grouped + "." + "%02d".format(fen)
    }

    private fun trimRate(rate: Double?): String {
        if (rate == null) return "0"
        return if (kotlin.math.abs(rate - kotlin.math.round(rate)) < 0.005) {
            kotlin.math.round(rate).toInt().toString()
        } else {
            "%.1f".format(rate)
        }
    }

    /** 收起态的进度条：与展开态逻辑相同，控件 id 不同 */
    private fun applyProgressCompact(views: RemoteViews, level: Level, rate: Double?) {
        val progress = (rate ?: 0.0).coerceIn(0.0, 100.0).toInt()
        val visible = android.view.View.VISIBLE
        val gone = android.view.View.GONE

        views.setViewVisibility(R.id.ledger_cbar_ok, if (level == Level.OK) visible else gone)
        views.setViewVisibility(R.id.ledger_cbar_warn, if (level == Level.WARN) visible else gone)
        views.setViewVisibility(R.id.ledger_cbar_danger, if (level == Level.DANGER) visible else gone)

        when (level) {
            Level.OK -> views.setProgressBar(R.id.ledger_cbar_ok, 100, progress, false)
            Level.WARN -> views.setProgressBar(R.id.ledger_cbar_warn, 100, progress, false)
            Level.DANGER -> views.setProgressBar(R.id.ledger_cbar_danger, 100, progress, false)
            Level.NONE -> Unit
        }
    }

    /** 通知里用紧凑写法：整数金额省略末尾的 .00 */
    private fun moneyShort(cents: Long): String {
        val text = money(cents)
        return if (text.endsWith(".00")) text.dropLast(3) else text
    }
}
