package com.campus.ledger.dto;

/**
 * 星期维度的支出分布。
 * 固定 7 项（周一 ~ 周日），金额与占比都返回字符串，前端直接用。
 */
public class WeekdaySpendingItem {

    /** 1 = 周一 … 7 = 周日（与 LocalDate.getDayOfWeek() 一致） */
    private final int weekday;
    private final String weekdayName;
    private final String amount;

    /** 占总支出的百分比，保留两位小数 */
    private final String percentage;

    public WeekdaySpendingItem(int weekday, String weekdayName, String amount, String percentage) {
        this.weekday = weekday;
        this.weekdayName = weekdayName;
        this.amount = amount;
        this.percentage = percentage;
    }

    public int getWeekday() {
        return weekday;
    }

    public String getWeekdayName() {
        return weekdayName;
    }

    public String getAmount() {
        return amount;
    }

    public String getPercentage() {
        return percentage;
    }
}
