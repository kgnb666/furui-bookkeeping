package com.campus.ledger.dto;

import java.util.List;

/**
 * 某个月的消费洞察。
 * summary 是给首页用的一句话摘要，insights 是给统计页用的卡片列表（最多 5 条）。
 */
public class MonthlyInsightsResponse {

    private final String month;
    private final String expense;
    private final String income;
    private final String balance;

    /** 环比变化率（%），无法比较时为 null */
    private final String expenseChangePercent;

    /** 本月支出占比最高的分类，没有支出时为 null */
    private final String topCategory;
    private final String topCategoryPercent;

    /** 一句话摘要，例如"本月支出 ¥1886.50，比上月 ↑12.30%，餐饮是主要支出类别" */
    private final String summary;

    private final List<Insight> insights;

    public MonthlyInsightsResponse(String month, String expense, String income, String balance,
                                   String expenseChangePercent, String topCategory,
                                   String topCategoryPercent, String summary, List<Insight> insights) {
        this.month = month;
        this.expense = expense;
        this.income = income;
        this.balance = balance;
        this.expenseChangePercent = expenseChangePercent;
        this.topCategory = topCategory;
        this.topCategoryPercent = topCategoryPercent;
        this.summary = summary;
        this.insights = insights;
    }

    public String getMonth() {
        return month;
    }

    public String getExpense() {
        return expense;
    }

    public String getIncome() {
        return income;
    }

    public String getBalance() {
        return balance;
    }

    public String getExpenseChangePercent() {
        return expenseChangePercent;
    }

    public String getTopCategory() {
        return topCategory;
    }

    public String getTopCategoryPercent() {
        return topCategoryPercent;
    }

    public String getSummary() {
        return summary;
    }

    public List<Insight> getInsights() {
        return insights;
    }
}
