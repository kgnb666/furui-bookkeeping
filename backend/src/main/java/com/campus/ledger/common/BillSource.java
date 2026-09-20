package com.campus.ledger.common;

/**
 * 账单来源：手动记账 / 微信导入 / 支付宝导入。
 */
public enum BillSource {

    MANUAL("手动记录"),
    WECHAT("微信"),
    ALIPAY("支付宝");

    private final String label;

    BillSource(String label) {
        this.label = label;
    }

    public String getLabel() {
        return label;
    }

    public static BillSource parse(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String text = value.trim();
        for (BillSource source : values()) {
            if (source.name().equalsIgnoreCase(text) || source.label.equals(text)) {
                return source;
            }
        }
        return null;
    }
}
