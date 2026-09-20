package com.campus.ledger.dto;

/**
 * 单条预算的预测结果。
 *
 * 一条预测必须能回答"为什么是这个结论"，因此同时给出输入（日均、已过天数）
 * 与输出（月末预测、超支金额、触顶日期），用户可以自己复核算式。
 */
public class BudgetPredictionItem {

    /** 预算 id */
    private final Long budgetId;

    /** 空串表示月度总预算 */
    private final String category;
    private final String categoryName;

    /** 是否月度总预算，前端据此决定展示位置 */
    private final boolean total;

    private final String budgetAmount;
    private final String spent;

    /** 当月有支出记录的天数，用于说明样本是否充分 */
    private final int spentDays;

    /** 已过天数（含当天） */
    private final int elapsedDays;

    /** 日均支出 = 已支出 / 已过天数 */
    private final String dailyAverage;

    /** 月末预测支出 = 日均 × 当月天数 */
    private final String projected;

    /** 预计超出预算的金额，未超出为 0 */
    private final String projectedOver;

    /** 预测使用率（%）= 月末预测 / 预算 × 100 */
    private final String projectedUsageRate;

    /** 预计触顶日期 yyyy-MM-dd，无法预测时为 null */
    private final String overDate;

    /** 剩余天数，用于提示"还剩几天" */
    private final int daysLeft;

    /** SAFE / LOW / MEDIUM / HIGH / OVER */
    private final String riskLevel;

    /** 中文说明，直接展示给用户 */
    private final String message;

    public BudgetPredictionItem(Long budgetId, String category, String categoryName, boolean total,
                                String budgetAmount, String spent, int spentDays, int elapsedDays,
                                String dailyAverage, String projected, String projectedOver,
                                String projectedUsageRate, String overDate, int daysLeft,
                                String riskLevel, String message) {
        this.budgetId = budgetId;
        this.category = category;
        this.categoryName = categoryName;
        this.total = total;
        this.budgetAmount = budgetAmount;
        this.spent = spent;
        this.spentDays = spentDays;
        this.elapsedDays = elapsedDays;
        this.dailyAverage = dailyAverage;
        this.projected = projected;
        this.projectedOver = projectedOver;
        this.projectedUsageRate = projectedUsageRate;
        this.overDate = overDate;
        this.daysLeft = daysLeft;
        this.riskLevel = riskLevel;
        this.message = message;
    }

    public Long getBudgetId() {
        return budgetId;
    }

    public String getCategory() {
        return category;
    }

    public String getCategoryName() {
        return categoryName;
    }

    public boolean isTotal() {
        return total;
    }

    public String getBudgetAmount() {
        return budgetAmount;
    }

    public String getSpent() {
        return spent;
    }

    public int getSpentDays() {
        return spentDays;
    }

    public int getElapsedDays() {
        return elapsedDays;
    }

    public String getDailyAverage() {
        return dailyAverage;
    }

    public String getProjected() {
        return projected;
    }

    public String getProjectedOver() {
        return projectedOver;
    }

    public String getProjectedUsageRate() {
        return projectedUsageRate;
    }

    public String getOverDate() {
        return overDate;
    }

    public int getDaysLeft() {
        return daysLeft;
    }

    public String getRiskLevel() {
        return riskLevel;
    }

    public String getMessage() {
        return message;
    }
}
