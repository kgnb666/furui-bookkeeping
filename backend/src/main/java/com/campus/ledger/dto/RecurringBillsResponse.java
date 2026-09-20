package com.campus.ledger.dto;

import java.util.List;

/**
 * 周期性账单识别的总览。
 *
 * status 说明：
 *   OK                   至少识别到 1 项周期支出
 *   NO_DATA              窗口内支出账单少于 5 条，样本太少
 *   NOT_ENOUGH_HISTORY   有账单但最早一笔距今天不足 60 天，用得太短
 *   NO_RECURRING         数据量与时间跨度都满足，但没识别出周期
 */
public class RecurringBillsResponse {

    /** 分析窗口天数，固定 180 */
    private final int windowDays;
    private final String status;
    private final String message;
    private final List<RecurringBillResponse> items;

    public RecurringBillsResponse(int windowDays, String status, String message,
                                  List<RecurringBillResponse> items) {
        this.windowDays = windowDays;
        this.status = status;
        this.message = message;
        this.items = items;
    }

    public static RecurringBillsResponse of(int windowDays, String status, String message,
                                            List<RecurringBillResponse> items) {
        return new RecurringBillsResponse(windowDays, status, message, items);
    }

    public int getWindowDays() {
        return windowDays;
    }

    public String getStatus() {
        return status;
    }

    public String getMessage() {
        return message;
    }

    public List<RecurringBillResponse> getItems() {
        return items;
    }
}
