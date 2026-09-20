package com.campus.ledger.dto;

import java.util.List;

/**
 * 某个月的消费异常检测结果。
 *
 * status 说明：
 *   OK                    检测到至少 1 条异常
 *   NO_DATA               目标月份没有支出记录
 *   NOT_ENOUGH_BASELINE   有支出，但前 3 个月完全没有数据，无法建立基线
 *   NO_ANOMALY            基线可用且未检测到异常
 */
public class AnomaliesResponse {

    private final String month;
    private final String status;
    private final String message;

    /** 参与对比的前 3 个自然月，按时间升序 */
    private final List<String> baselineMonths;
    private final List<AnomalyItem> items;

    public AnomaliesResponse(String month, String status, String message,
                             List<String> baselineMonths, List<AnomalyItem> items) {
        this.month = month;
        this.status = status;
        this.message = message;
        this.baselineMonths = baselineMonths;
        this.items = items;
    }

    public static AnomaliesResponse of(String month, String status, String message,
                                       List<String> baselineMonths, List<AnomalyItem> items) {
        return new AnomaliesResponse(month, status, message, baselineMonths, items);
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

    public List<String> getBaselineMonths() {
        return baselineMonths;
    }

    public List<AnomalyItem> getItems() {
        return items;
    }
}
