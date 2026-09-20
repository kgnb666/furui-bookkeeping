package com.campus.ledger.common;

/**
 * 账单收支类型：数据库存 1=支出 2=收入 3=不计收支。
 */
public enum BillType {

    EXPENSE(1, "支出"),
    INCOME(2, "收入"),
    NEUTRAL(3, "不计收支");

    private final int code;
    private final String label;

    BillType(int code, String label) {
        this.code = code;
        this.label = label;
    }

    public int getCode() {
        return code;
    }

    public String getLabel() {
        return label;
    }

    public static BillType of(Integer code) {
        if (code != null) {
            for (BillType type : values()) {
                if (type.code == code) {
                    return type;
                }
            }
        }
        return null;
    }

    /**
     * 兼容三种写法：1 / EXPENSE / 支出。
     */
    public static BillType parse(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String text = value.trim();
        for (BillType type : values()) {
            if (String.valueOf(type.code).equals(text)
                    || type.name().equalsIgnoreCase(text)
                    || type.label.equals(text)) {
                return type;
            }
        }
        return null;
    }
}
