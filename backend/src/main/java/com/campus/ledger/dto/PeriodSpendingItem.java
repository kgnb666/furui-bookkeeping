package com.campus.ledger.dto;

/**
 * 月内阶段的支出分布。
 * 固定三段：1-10 日、11-20 日、21 日-月底（endDay 随当月天数变化，支持 28/29/30/31 天）。
 */
public class PeriodSpendingItem {

    private final String periodName;
    private final int startDay;

    /** 该阶段的结束日：第三段等于当月天数 */
    private final int endDay;
    private final String amount;

    /** 占总支出的百分比，保留两位小数 */
    private final String percentage;

    public PeriodSpendingItem(String periodName, int startDay, int endDay,
                              String amount, String percentage) {
        this.periodName = periodName;
        this.startDay = startDay;
        this.endDay = endDay;
        this.amount = amount;
        this.percentage = percentage;
    }

    public String getPeriodName() {
        return periodName;
    }

    public int getStartDay() {
        return startDay;
    }

    public int getEndDay() {
        return endDay;
    }

    public String getAmount() {
        return amount;
    }

    public String getPercentage() {
        return percentage;
    }
}
