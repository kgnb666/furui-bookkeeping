package com.campus.ledger.dto;

import java.util.List;

/**
 * 消费对象分析（我的钱花给谁了）。
 *
 * status 取值：
 *   OK                 消费数据充分，可以给出对象排行与集中度
 *   INSUFFICIENT_DATA  有支出，但消费天数或交易对象信息不足，无法分析
 *   NO_DATA            当月没有任何支出
 *   NOT_APPLICABLE     参考月不是服务器当前月（过去与未来月份都不分析）
 *
 * 金额与百分比一律为字符串（项目既有约定：BigDecimal 汇总后格式化成两位小数）。
 */
public class SpendingMerchantResponse {

    /** 参考月（yyyy-MM） */
    private final String month;
    private final String status;
    private final String message;

    /** 当月支出合计 */
    private final String totalAmount;

    /** 当月支出笔数 */
    private final int totalCount;

    /** 整体客单价：支出合计 ÷ 笔数 */
    private final String averageAmount;

    /** 有效消费对象数量（归一化去重后，不含"未填写"） */
    private final int merchantCount;

    /** 交易对象覆盖率（%）：填写了交易对象的笔数 ÷ 总笔数 */
    private final String merchantCoverage;

    /** 未填写交易对象的支出合计 */
    private final String unknownMerchantAmount;

    /** 未填写交易对象的金额占比（%） */
    private final String unknownMerchantRate;

    /** Top3 消费对象的金额集中度（%） */
    private final String top3Concentration;

    /** 一句话结论，非 OK 时为空串 */
    private final String summary;

    /** 消费对象排行（最多 5 项，按金额 → 笔数 → 名称排序） */
    private final List<MerchantSpendingItem> topMerchants;

    public SpendingMerchantResponse(String month, String status, String message, String totalAmount,
                                    int totalCount, String averageAmount, int merchantCount,
                                    String merchantCoverage, String unknownMerchantAmount,
                                    String unknownMerchantRate, String top3Concentration,
                                    String summary, List<MerchantSpendingItem> topMerchants) {
        this.month = month;
        this.status = status;
        this.message = message;
        this.totalAmount = totalAmount;
        this.totalCount = totalCount;
        this.averageAmount = averageAmount;
        this.merchantCount = merchantCount;
        this.merchantCoverage = merchantCoverage;
        this.unknownMerchantAmount = unknownMerchantAmount;
        this.unknownMerchantRate = unknownMerchantRate;
        this.top3Concentration = top3Concentration;
        this.summary = summary;
        this.topMerchants = topMerchants;
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

    public int getTotalCount() {
        return totalCount;
    }

    public String getAverageAmount() {
        return averageAmount;
    }

    public int getMerchantCount() {
        return merchantCount;
    }

    public String getMerchantCoverage() {
        return merchantCoverage;
    }

    public String getUnknownMerchantAmount() {
        return unknownMerchantAmount;
    }

    public String getUnknownMerchantRate() {
        return unknownMerchantRate;
    }

    public String getTop3Concentration() {
        return top3Concentration;
    }

    public String getSummary() {
        return summary;
    }

    public List<MerchantSpendingItem> getTopMerchants() {
        return topMerchants;
    }
}
