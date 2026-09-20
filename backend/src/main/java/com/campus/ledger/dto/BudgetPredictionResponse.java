package com.campus.ledger.dto;

import java.util.List;

/**
 * 某个月的预算预测。
 *
 * status 说明：
 *   OK            预测可用（当前月 + 有预算 + 消费天数足够）
 *   INSUFFICIENT_DATA 有预算但消费天数不足 3 天，不给出预测结论
 *   NO_BUDGET     该月没有设置任何预算，items 为空
 *   NOT_APPLICABLE 不是当前月份，只有当前月才做预测
 */
public class BudgetPredictionResponse {

    private final String month;
    private final String status;

    /** 给用户看的一句话说明，任何 status 下都不为空 */
    private final String message;

    /** 当月已过天数（含当天），非当前月为 0 */
    private final int elapsedDays;
    private final int daysInMonth;
    private final int daysLeft;

    /** 总预算预测 + 各分类预算预测；没有预算时为空列表 */
    private final List<BudgetPredictionItem> items;

    public BudgetPredictionResponse(String month, String status, String message,
                                    int elapsedDays, int daysInMonth, int daysLeft,
                                    List<BudgetPredictionItem> items) {
        this.month = month;
        this.status = status;
        this.message = message;
        this.elapsedDays = elapsedDays;
        this.daysInMonth = daysInMonth;
        this.daysLeft = daysLeft;
        this.items = items;
    }

    /** 没有设置预算 */
    public static BudgetPredictionResponse noBudget(String month, int elapsedDays,
                                                    int daysInMonth, int daysLeft) {
        return new BudgetPredictionResponse(month, "NO_BUDGET",
                "本月还没有设置预算，设置后可以预测月末支出", elapsedDays, daysInMonth, daysLeft, List.of());
    }

    /** 不是当前月份 */
    public static BudgetPredictionResponse notApplicable(String month, int daysInMonth) {
        return new BudgetPredictionResponse(month, "NOT_APPLICABLE",
                "仅支持预测本月支出", 0, daysInMonth, 0, List.of());
    }

    public String getMonth() {
        return month;
    }

    public String getStatus() {
        return status;
    }

    public String getMessage() {
        return message;
    }

    public int getElapsedDays() {
        return elapsedDays;
    }

    public int getDaysInMonth() {
        return daysInMonth;
    }

    public int getDaysLeft() {
        return daysLeft;
    }

    public List<BudgetPredictionItem> getItems() {
        return items;
    }
}
