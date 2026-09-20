package com.campus.ledger.common;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;

/**
 * 账单与预算共用的金额、日期校验规则。
 * 手工记账、导入预览、导入确认、预算都调用这里，避免同一个规则在多处各写一遍导致不一致。
 */
public class BillRules {

    public static final BigDecimal MAX_AMOUNT = new BigDecimal("99999999.99");

    private BillRules() {
    }

    /** 校验并标准化金额（保留两位小数），不合法时抛业务异常 */
    public static BigDecimal checkAmount(BigDecimal amount) {
        return checkAmount(amount, "金额");
    }

    public static BigDecimal checkAmount(BigDecimal amount, String label) {
        String error = amountError(amount, label);
        if (error != null) {
            throw new BizException(400, error);
        }
        return amount.setScale(2, RoundingMode.HALF_UP);
    }

    /** 校验记账日期，不合法时抛业务异常 */
    public static LocalDate checkBillDate(LocalDate billDate) {
        String error = billDateError(billDate);
        if (error != null) {
            throw new BizException(400, error);
        }
        return billDate;
    }

    /** 供导入预览使用：返回错误原因，null 表示通过 */
    public static String amountError(BigDecimal amount, String label) {
        if (amount == null || amount.signum() <= 0) {
            return label + "必须大于 0";
        }
        if (amount.scale() > 2) {
            return label + "最多两位小数";
        }
        if (amount.setScale(2, RoundingMode.HALF_UP).compareTo(MAX_AMOUNT) > 0) {
            return label + "不能超过 99,999,999.99";
        }
        return null;
    }

    /** 供导入预览使用：返回错误原因，null 表示通过 */
    public static String billDateError(LocalDate billDate) {
        if (billDate == null) {
            return "日期不能为空";
        }
        if (billDate.isAfter(LocalDate.now())) {
            return "日期不能晚于今天";
        }
        return null;
    }
}
