package com.campus.ledger.dto;

/**
 * 某一天的收支概览，首页「今日收入 / 今日支出」使用。
 */
public class DailySummaryResponse {

    private final String date;
    private final String income;
    private final String expense;

    public DailySummaryResponse(String date, String income, String expense) {
        this.date = date;
        this.income = income;
        this.expense = expense;
    }

    public String getDate() {
        return date;
    }

    public String getIncome() {
        return income;
    }

    public String getExpense() {
        return expense;
    }
}
