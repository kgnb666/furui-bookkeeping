package com.campus.ledger.common;

import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

/**
 * 金额与日期规则现在只写在 BillRules 一处，
 * 这里锁住"抛异常版本"和"返回原因版本"的判断结果一致。
 */
class BillRulesTest {

    @Test
    void 合法金额会被标准化为两位小数() {
        assertEquals(new BigDecimal("31.00"), BillRules.checkAmount(new BigDecimal("31")));
        assertEquals(new BigDecimal("31.50"), BillRules.checkAmount(new BigDecimal("31.5")));
        assertEquals(new BigDecimal("99999999.99"), BillRules.checkAmount(new BigDecimal("99999999.99")));
    }

    @Test
    void 非法金额被拒绝且提示一致() {
        assertEquals(400, assertThrows(BizException.class,
                () -> BillRules.checkAmount(new BigDecimal("0"))).getCode());
        assertEquals("金额必须大于 0", BillRules.amountError(new BigDecimal("-1"), "金额"));
        assertEquals("金额最多两位小数", BillRules.amountError(new BigDecimal("12.345"), "金额"));
        assertEquals("金额不能超过 99,999,999.99", BillRules.amountError(new BigDecimal("100000000"), "金额"));
    }

    @Test
    void 预算金额使用自己的提示文案() {
        assertEquals("预算金额必须大于 0", BillRules.amountError(new BigDecimal("0"), "预算金额"));
        assertEquals(400, assertThrows(BizException.class,
                () -> BillRules.checkAmount(new BigDecimal("0"), "预算金额")).getCode());
    }

    @Test
    void 日期不能为空也不能晚于今天() {
        assertEquals("日期不能为空", BillRules.billDateError(null));
        assertEquals("日期不能晚于今天", BillRules.billDateError(LocalDate.now().plusDays(1)));
        assertNull(BillRules.billDateError(LocalDate.now()));
        assertNull(BillRules.billDateError(LocalDate.now().minusDays(3)));
        assertEquals(400, assertThrows(BizException.class,
                () -> BillRules.checkBillDate(LocalDate.now().plusDays(1))).getCode());
    }

    @Test
    void 抛异常版本与返回原因版本判断一致() {
        BigDecimal[] amounts = {new BigDecimal("0"), new BigDecimal("-5"), new BigDecimal("12.345"),
                new BigDecimal("100000000"), new BigDecimal("0.01"), new BigDecimal("31.00")};
        for (BigDecimal amount : amounts) {
            String reason = BillRules.amountError(amount, "金额");
            if (reason == null) {
                assertEquals(amount.setScale(2), BillRules.checkAmount(amount));
            } else {
                assertEquals(reason, assertThrows(BizException.class,
                        () -> BillRules.checkAmount(amount)).getMessage());
            }
        }
    }
}
