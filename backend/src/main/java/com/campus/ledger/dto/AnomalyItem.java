package com.campus.ledger.dto;

/**
 * 单条消费异常。
 *
 * 字段严格限定为前端展示所需，不附加技术性辅助字段：
 * 判定依据（基线、当前值、偏离幅度）全部写进 message，用户可以直接核对。
 */
public class AnomalyItem {

    /** CATEGORY_SPIKE / LARGE_TRANSACTION / FREQUENCY_SPIKE */
    private final String type;

    /** HIGH / MEDIUM */
    private final String severity;

    /** 中文严重度，如"需注意" */
    private final String severityLabel;

    private final String category;
    private final String title;
    private final String message;

    private final String currentAmount;
    private final String baselineAmount;

    /** 与基线的差额（金额类为金额差额，频次类为多出的笔数） */
    private final String difference;

    /** 相对基线的变化百分比，保留两位小数 */
    private final String changePercent;

    /** 仅 LARGE_TRANSACTION 有值，其余为 null */
    private final String merchant;
    private final String billDate;

    public AnomalyItem(String type, String severity, String severityLabel, String category,
                       String title, String message, String currentAmount, String baselineAmount,
                       String difference, String changePercent, String merchant, String billDate) {
        this.type = type;
        this.severity = severity;
        this.severityLabel = severityLabel;
        this.category = category;
        this.title = title;
        this.message = message;
        this.currentAmount = currentAmount;
        this.baselineAmount = baselineAmount;
        this.difference = difference;
        this.changePercent = changePercent;
        this.merchant = merchant;
        this.billDate = billDate;
    }

    public String getType() {
        return type;
    }

    public String getSeverity() {
        return severity;
    }

    public String getSeverityLabel() {
        return severityLabel;
    }

    public String getCategory() {
        return category;
    }

    public String getTitle() {
        return title;
    }

    public String getMessage() {
        return message;
    }

    public String getCurrentAmount() {
        return currentAmount;
    }

    public String getBaselineAmount() {
        return baselineAmount;
    }

    public String getDifference() {
        return difference;
    }

    public String getChangePercent() {
        return changePercent;
    }

    public String getMerchant() {
        return merchant;
    }

    public String getBillDate() {
        return billDate;
    }
}
