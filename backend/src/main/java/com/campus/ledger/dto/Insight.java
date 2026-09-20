package com.campus.ledger.dto;

/**
 * 一条消费洞察。每条都必须能解释"为什么会有这条提示"：
 * title + message 用中文说清楚，type 供前端选图标，amount 是支撑该结论的金额。
 */
public class Insight {

    /** BUDGET_OVER / BUDGET_WARNING / CATEGORY_GROWTH / SPENDING_CHANGE / CATEGORY_FOCUS */
    private final String type;

    /** 展示优先级：数字越小越靠前 */
    private final int priority;

    /** WARNING / INFO */
    private final String level;

    private final String title;
    private final String message;
    private final String amount;

    public Insight(String type, int priority, String level, String title, String message, String amount) {
        this.type = type;
        this.priority = priority;
        this.level = level;
        this.title = title;
        this.message = message;
        this.amount = amount;
    }

    public String getType() {
        return type;
    }

    public int getPriority() {
        return priority;
    }

    public String getLevel() {
        return level;
    }

    public String getTitle() {
        return title;
    }

    public String getMessage() {
        return message;
    }

    public String getAmount() {
        return amount;
    }
}
