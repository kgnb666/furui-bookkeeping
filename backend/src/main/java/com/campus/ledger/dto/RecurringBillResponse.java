package com.campus.ledger.dto;

/**
 * 一条周期性账单识别结果。
 *
 * 必须能直接给前端展示，也必须能解释"为什么认为它是周期性的"：
 * reason 里会写清楚次数、间隔区间与金额稳定性，用户可以自己翻账单核对。
 */
public class RecurringBillResponse {

    /** 展示用商户名（取该组中出现次数最多的原始写法） */
    private final String merchant;

    /** 主导分类 */
    private final String category;

    /** WEEKLY / BIWEEKLY / MONTHLY */
    private final String cycleType;

    /** 中文周期名，如"每月一次" */
    private final String cycleLabel;

    /** HIGH / MEDIUM */
    private final String confidence;

    /** 中文置信度，如"高" */
    private final String confidenceLabel;

    private final int sampleCount;
    private final String averageAmount;
    private final int averageInterval;

    /** 间隔区间展示文本，如"29~31 天" */
    private final String intervalRange;

    /** 金额变异系数，保留两位小数 */
    private final String amountCv;

    /** 主导分类占比（%），保留两位小数 */
    private final String categoryRatio;

    private final String lastDate;
    private final String nextDate;

    private final String reason;

    public RecurringBillResponse(String merchant, String category, String cycleType, String cycleLabel,
                                 String confidence, String confidenceLabel, int sampleCount,
                                 String averageAmount, int averageInterval, String intervalRange,
                                 String amountCv, String categoryRatio, String lastDate,
                                 String nextDate, String reason) {
        this.merchant = merchant;
        this.category = category;
        this.cycleType = cycleType;
        this.cycleLabel = cycleLabel;
        this.confidence = confidence;
        this.confidenceLabel = confidenceLabel;
        this.sampleCount = sampleCount;
        this.averageAmount = averageAmount;
        this.averageInterval = averageInterval;
        this.intervalRange = intervalRange;
        this.amountCv = amountCv;
        this.categoryRatio = categoryRatio;
        this.lastDate = lastDate;
        this.nextDate = nextDate;
        this.reason = reason;
    }

    public String getMerchant() {
        return merchant;
    }

    public String getCategory() {
        return category;
    }

    public String getCycleType() {
        return cycleType;
    }

    public String getCycleLabel() {
        return cycleLabel;
    }

    public String getConfidence() {
        return confidence;
    }

    public String getConfidenceLabel() {
        return confidenceLabel;
    }

    public int getSampleCount() {
        return sampleCount;
    }

    public String getAverageAmount() {
        return averageAmount;
    }

    public int getAverageInterval() {
        return averageInterval;
    }

    public String getIntervalRange() {
        return intervalRange;
    }

    public String getAmountCv() {
        return amountCv;
    }

    public String getCategoryRatio() {
        return categoryRatio;
    }

    public String getLastDate() {
        return lastDate;
    }

    public String getNextDate() {
        return nextDate;
    }

    public String getReason() {
        return reason;
    }
}
