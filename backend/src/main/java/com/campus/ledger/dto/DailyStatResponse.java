package com.campus.ledger.dto;

/** 每日趋势中的一天 */
public class DailyStatResponse {

    private final String date;
    private final String income;
    private final String expense;

    public DailyStatResponse(String date, String income, String expense) {
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
