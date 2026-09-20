package com.campus.ledger.dto;

import java.util.List;

/**
 * 收支结余分析（我这个月存下了多少）。
 *
 * status 取值：
 *   OK                当月有收入记录，可以给出结余与收入结构
 *   NO_INCOME_DATA    当月有支出但没有任何收入记录，无法计算结余率（只返回支出事实）
 *   NO_DATA           当月既没有收入也没有支出
 *   NOT_APPLICABLE    参考月不是服务器当前月（过去与未来月份都不分析）
 *
 * 金额与百分比一律为字符串（项目既有约定：BigDecimal 汇总后格式化成两位小数）。
 */
public class IncomeBalanceResponse {

    private final String month;
    private final String status;
    private final String message;

    /** 当月收入合计 */
    private final String incomeAmount;

    /** 当月支出合计 */
    private final String expenseAmount;

    /** 当月结余 = 收入 − 支出（可能为负） */
    private final String balance;

    /** 结余率（%）= 结余 ÷ 收入 × 100；没有收入时为 "0.00" */
    private final String balanceRate;

    /** 当月收入笔数 */
    private final int incomeCount;

    /** 收入结构（按金额降序，最多 5 项） */
    private final List<IncomeCategoryItem> incomeItems;

    /** 上月结余；上月没有收支记录时为 "0.00" */
    private final String previousBalance;

    /** 与上月结余的差额；上月没有记录时为 null */
    private final String balanceChange;

    /** 上月是否有收支记录（决定前端是否展示对比） */
    private final boolean hasPreviousData;

    /** 一句话结论，非 OK 时为空串 */
    private final String summary;

    public IncomeBalanceResponse(String month, String status, String message, String incomeAmount,
                                 String expenseAmount, String balance, String balanceRate,
                                 int incomeCount, List<IncomeCategoryItem> incomeItems,
                                 String previousBalance, String balanceChange,
                                 boolean hasPreviousData, String summary) {
        this.month = month;
        this.status = status;
        this.message = message;
        this.incomeAmount = incomeAmount;
        this.expenseAmount = expenseAmount;
        this.balance = balance;
        this.balanceRate = balanceRate;
        this.incomeCount = incomeCount;
        this.incomeItems = incomeItems;
        this.previousBalance = previousBalance;
        this.balanceChange = balanceChange;
        this.hasPreviousData = hasPreviousData;
        this.summary = summary;
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

    public String getIncomeAmount() {
        return incomeAmount;
    }

    public String getExpenseAmount() {
        return expenseAmount;
    }

    public String getBalance() {
        return balance;
    }

    public String getBalanceRate() {
        return balanceRate;
    }

    public int getIncomeCount() {
        return incomeCount;
    }

    public List<IncomeCategoryItem> getIncomeItems() {
        return incomeItems;
    }

    public String getPreviousBalance() {
        return previousBalance;
    }

    public String getBalanceChange() {
        return balanceChange;
    }

    public boolean isHasPreviousData() {
        return hasPreviousData;
    }

    public String getSummary() {
        return summary;
    }
}
