package com.campus.ledger.common;

import java.time.YearMonth;
import java.time.format.DateTimeParseException;

/**
 * 统计与预算都要按月查询，月份统一按 yyyy-MM 解析。
 */
public class Months {

    private Months() {
    }

    public static YearMonth parse(String month) {
        if (month == null || month.isBlank()) {
            throw new BizException(400, "月份不能为空");
        }
        try {
            return YearMonth.parse(month.trim());
        } catch (DateTimeParseException e) {
            throw new BizException(400, "月份格式应为 yyyy-MM");
        }
    }

}
