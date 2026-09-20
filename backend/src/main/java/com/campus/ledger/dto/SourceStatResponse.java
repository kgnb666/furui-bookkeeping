package com.campus.ledger.dto;

import java.math.BigDecimal;

/** 支付来源统计：金额与占比都由后端算好 */
public class SourceStatResponse {

    private final String source;
    private final String sourceName;
    private final String amount;
    private final BigDecimal percentage;

    public SourceStatResponse(String source, String sourceName, String amount, BigDecimal percentage) {
        this.source = source;
        this.sourceName = sourceName;
        this.amount = amount;
        this.percentage = percentage;
    }

    public String getSource() {
        return source;
    }

    public String getSourceName() {
        return sourceName;
    }

    public String getAmount() {
        return amount;
    }

    public BigDecimal getPercentage() {
        return percentage;
    }
}
