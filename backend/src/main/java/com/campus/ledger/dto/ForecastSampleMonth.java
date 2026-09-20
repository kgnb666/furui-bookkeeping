package com.campus.ledger.dto;

/**
 * 参与下月预估的一个历史月份样本。
 * 把月份、金额与权重一起返回，用户能按"最近月 ×3、次近月 ×2、第三近月 ×1"手工复核预测值。
 */
public class ForecastSampleMonth {

    /** 格式 yyyy-MM */
    private final String month;
    private final String amount;

    /** 参与加权时的权重（正常 3 / 2 / 1，被判定为异常月时降为 1） */
    private final int weight;

    public ForecastSampleMonth(String month, String amount, int weight) {
        this.month = month;
        this.amount = amount;
        this.weight = weight;
    }

    public String getMonth() {
        return month;
    }

    public String getAmount() {
        return amount;
    }

    public int getWeight() {
        return weight;
    }
}
