package com.campus.ledger.dto;

/**
 * 收入结构里的一项：某个收入分类的金额与占当月收入的比例。
 */
public class IncomeCategoryItem {

    private final String category;
    private final String amount;

    /** 该分类当月的收入笔数 */
    private final int count;

    /** 占当月总收入的百分比，保留两位小数 */
    private final String percentage;

    public IncomeCategoryItem(String category, String amount, int count, String percentage) {
        this.category = category;
        this.amount = amount;
        this.count = count;
        this.percentage = percentage;
    }

    public String getCategory() {
        return category;
    }

    public String getAmount() {
        return amount;
    }

    public int getCount() {
        return count;
    }

    public String getPercentage() {
        return percentage;
    }
}
