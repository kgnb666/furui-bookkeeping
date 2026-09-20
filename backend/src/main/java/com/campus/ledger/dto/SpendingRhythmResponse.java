package com.campus.ledger.dto;

import java.util.List;

/**
 * 消费节奏与时间分布分析。
 *
 * 回答的问题是：**我的钱通常在什么时候花掉？**
 *
 * status 取值：
 *   OK                 可以给出节奏分析
 *   INSUFFICIENT_DATA  当月有支出，但有消费记录的天数不足 3 天，无法判断节奏
 *   NO_DATA            当月没有任何支出
 *   NOT_APPLICABLE     参考月不是服务器当前月（过去或未来月份都不做分析）
 *
 * 金额与百分比一律为字符串（项目既有约定：BigDecimal 汇总后格式化成两位小数）。
 */
public class SpendingRhythmResponse {

    /** 参考月（yyyy-MM） */
    private final String month;
    private final String status;
    private final String message;

    /** 当月支出合计 */
    private final String totalAmount;

    /** 当月有支出记录的天数 */
    private final int coveredDays;

    /** 记账覆盖率（有支出的天数 ÷ 当月天数 × 100） */
    private final String coveredRate;

    /** 支出最高的星期名称，非 OK 时为空串 */
    private final String peakWeekday;

    /** 支出最高的月内阶段名称，非 OK 时为空串 */
    private final String peakPeriod;

    /** 消费集中度：最高星期的金额 ÷ 总支出 × 100 */
    private final String concentration;

    /** 一句话结论，非 OK 时为空串 */
    private final String summary;

    /** 固定 7 项：周一 ~ 周日 */
    private final List<WeekdaySpendingItem> weekdayItems;

    /** 固定 3 项：1-10 日 / 11-20 日 / 21 日-月底 */
    private final List<PeriodSpendingItem> periodItems;

    public SpendingRhythmResponse(String month, String status, String message, String totalAmount,
                                  int coveredDays, String coveredRate, String peakWeekday,
                                  String peakPeriod, String concentration, String summary,
                                  List<WeekdaySpendingItem> weekdayItems,
                                  List<PeriodSpendingItem> periodItems) {
        this.month = month;
        this.status = status;
        this.message = message;
        this.totalAmount = totalAmount;
        this.coveredDays = coveredDays;
        this.coveredRate = coveredRate;
        this.peakWeekday = peakWeekday;
        this.peakPeriod = peakPeriod;
        this.concentration = concentration;
        this.summary = summary;
        this.weekdayItems = weekdayItems;
        this.periodItems = periodItems;
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

    public String getTotalAmount() {
        return totalAmount;
    }

    public int getCoveredDays() {
        return coveredDays;
    }

    public String getCoveredRate() {
        return coveredRate;
    }

    public String getPeakWeekday() {
        return peakWeekday;
    }

    public String getPeakPeriod() {
        return peakPeriod;
    }

    public String getConcentration() {
        return concentration;
    }

    public String getSummary() {
        return summary;
    }

    public List<WeekdaySpendingItem> getWeekdayItems() {
        return weekdayItems;
    }

    public List<PeriodSpendingItem> getPeriodItems() {
        return periodItems;
    }
}
