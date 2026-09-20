package com.campus.ledger.dto;

import java.util.List;

/**
 * 某个月的预算与执行情况。total 为空表示还没设置月度总预算。
 */
public class BudgetResponse {

    private final String month;
    private final String monthExpense;
    private final BudgetItemResponse total;
    private final List<BudgetItemResponse> categories;

    public BudgetResponse(String month, String monthExpense, BudgetItemResponse total,
                          List<BudgetItemResponse> categories) {
        this.month = month;
        this.monthExpense = monthExpense;
        this.total = total;
        this.categories = categories;
    }

    public String getMonth() {
        return month;
    }

    public String getMonthExpense() {
        return monthExpense;
    }

    public BudgetItemResponse getTotal() {
        return total;
    }

    public List<BudgetItemResponse> getCategories() {
        return categories;
    }
}
