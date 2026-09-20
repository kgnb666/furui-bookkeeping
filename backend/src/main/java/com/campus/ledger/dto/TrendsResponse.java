package com.campus.ledger.dto;

/**
 * 消费趋势：本月与上月的支出对比，首页用来提示"比上月花得多还是少"。
 * previousHasData 为 false 表示上月没有任何收支记录，前端显示"暂无对比数据"。
 */
public class TrendsResponse {

    private final String month;
    private final String currentExpense;
    private final String currentIncome;
    private final String previousMonth;
    private final String previousExpense;
    private final boolean previousHasData;

    /** 支出变化率（%）：正数表示比上月多花，负数表示少花；无法比较时为 null */
    private final String expenseChangePercent;

    public TrendsResponse(String month, String currentExpense, String currentIncome,
                          String previousMonth, String previousExpense,
                          boolean previousHasData, String expenseChangePercent) {
        this.month = month;
        this.currentExpense = currentExpense;
        this.currentIncome = currentIncome;
        this.previousMonth = previousMonth;
        this.previousExpense = previousExpense;
        this.previousHasData = previousHasData;
        this.expenseChangePercent = expenseChangePercent;
    }

    public String getMonth() {
        return month;
    }

    public String getCurrentExpense() {
        return currentExpense;
    }

    public String getCurrentIncome() {
        return currentIncome;
    }

    public String getPreviousMonth() {
        return previousMonth;
    }

    public String getPreviousExpense() {
        return previousExpense;
    }

    public boolean isPreviousHasData() {
        return previousHasData;
    }

    public String getExpenseChangePercent() {
        return expenseChangePercent;
    }
}
