package com.campus.ledger.dto;

import java.util.List;

/**
 * 下月支出预估。
 *
 * status 取值：
 *   OK                   至少 3 个有支出的完整自然月，可以给出预估
 *   INSUFFICIENT_DATA    有支出历史，但有支出的完整自然月不足 3 个
 *   NO_DATA              读取窗口内没有任何支出记录
 *   NOT_APPLICABLE       参考月不是服务器当前月（过去或未来月份不做预估）
 *
 * 金额一律为字符串（项目既有约定：BigDecimal 汇总后格式化成两位小数）。
 */
public class SpendingForecastResponse {

    /** 参考月，即前端当前选中的月份 */
    private final String month;

    /** 被预估的月份（参考月的下一个月） */
    private final String targetMonth;

    private final String status;
    private final String message;

    /** HIGH / MEDIUM / LOW，非 OK 时为 NONE */
    private final String confidence;

    /** 高可信 / 中等可信 / 仅供参考，非 OK 时为空串 */
    private final String confidenceLabel;

    /** 置信度的客观依据（非 OK 时为空串） */
    private final String confidenceReason;

    private final String predictedAmount;
    private final String previousMonthAmount;

    /** 预估与最近有效月份的差额，非 OK 时为 null */
    private final String predictedDifference;

    /** 预估变化率（%），无法比较时为 null */
    private final String predictedChangePercent;

    /** 参考月（本月）至今的实际支出，只做事实陈述、不参与预估 */
    private final String currentMonthAmount;

    /** 本月已过天数 */
    private final int elapsedDays;

    /** 参与预估的历史月份（最多 3 条，按时间倒序） */
    private final List<ForecastSampleMonth> sampleMonths;

    public SpendingForecastResponse(String month, String targetMonth, String status, String message,
                                    String confidence, String confidenceLabel, String confidenceReason,
                                    String predictedAmount, String previousMonthAmount,
                                    String predictedDifference, String predictedChangePercent,
                                    String currentMonthAmount, int elapsedDays,
                                    List<ForecastSampleMonth> sampleMonths) {
        this.month = month;
        this.targetMonth = targetMonth;
        this.status = status;
        this.message = message;
        this.confidence = confidence;
        this.confidenceLabel = confidenceLabel;
        this.confidenceReason = confidenceReason;
        this.predictedAmount = predictedAmount;
        this.previousMonthAmount = previousMonthAmount;
        this.predictedDifference = predictedDifference;
        this.predictedChangePercent = predictedChangePercent;
        this.currentMonthAmount = currentMonthAmount;
        this.elapsedDays = elapsedDays;
        this.sampleMonths = sampleMonths;
    }

    public String getMonth() {
        return month;
    }

    public String getTargetMonth() {
        return targetMonth;
    }

    public String getStatus() {
        return status;
    }

    public String getMessage() {
        return message;
    }

    public String getConfidence() {
        return confidence;
    }

    public String getConfidenceLabel() {
        return confidenceLabel;
    }

    public String getConfidenceReason() {
        return confidenceReason;
    }

    public String getPredictedAmount() {
        return predictedAmount;
    }

    public String getPreviousMonthAmount() {
        return previousMonthAmount;
    }

    public String getPredictedDifference() {
        return predictedDifference;
    }

    public String getPredictedChangePercent() {
        return predictedChangePercent;
    }

    public String getCurrentMonthAmount() {
        return currentMonthAmount;
    }

    public int getElapsedDays() {
        return elapsedDays;
    }

    public List<ForecastSampleMonth> getSampleMonths() {
        return sampleMonths;
    }
}
