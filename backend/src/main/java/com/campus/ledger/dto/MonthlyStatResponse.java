package com.campus.ledger.dto;

/** 月度概览：收入、支出、结余 */
public class MonthlyStatResponse {

    private final String month;
    private final String income;
    private final String expense;
    private final String balance;

    public MonthlyStatResponse(String month, String income, String expense, String balance) {
        this.month = month;
        this.income = income;
        this.expense = expense;
        this.balance = balance;
    }

    public String getMonth() {
        return month;
    }

    public String getIncome() {
        return income;
    }

    public String getExpense() {
        return expense;
    }

    public String getBalance() {
        return balance;
    }
}
