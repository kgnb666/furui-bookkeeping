package com.campus.ledger.dto;

/**
 * 消费对象（商户）排行里的一项：金额、笔数与占当月总支出的比例。
 * 金额与占比都是字符串（项目既有约定：BigDecimal 汇总后格式化成两位小数）。
 */
public class MerchantSpendingItem {

    private final String merchantName;
    private final String amount;

    /** 该消费对象在目标月里的支出笔数 */
    private final int count;

    /** 占当月总支出的百分比，保留两位小数 */
    private final String percentage;

    public MerchantSpendingItem(String merchantName, String amount, int count, String percentage) {
        this.merchantName = merchantName;
        this.amount = amount;
        this.count = count;
        this.percentage = percentage;
    }

    public String getMerchantName() {
        return merchantName;
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
