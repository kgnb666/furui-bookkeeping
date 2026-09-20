package com.campus.ledger.importer;

import com.campus.ledger.common.BillType;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BillFieldsTest {

    @Test
    void 清洗单元格会去掉BOM制表符多余空格和引号() {
        assertEquals("31.00", BillFields.clean("\uFEFF \"31.00\"\t "));
        assertEquals("星巴克", BillFields.clean("  星巴克  "));
        assertEquals("", BillFields.clean(null));
    }

    @Test
    void 金额清洗支持货币符号与千分位() {
        assertEquals(new BigDecimal("28.16"), BillFields.parseAmount("¥28.16"));
        assertEquals(new BigDecimal("1280.00"), BillFields.parseAmount(" 1,280.00 "));
        assertEquals(new BigDecimal("31.00"), BillFields.parseAmount("\"¥31.00\"\t"));
    }

    @Test
    void 无法识别的金额返回null() {
        assertNull(BillFields.parseAmount(""));
        assertNull(BillFields.parseAmount("¥--"));
        assertNull(BillFields.parseAmount("/"));
        assertNull(BillFields.parseAmount("abc"));
    }

    @Test
    void 日期解析支持多种写法() {
        assertEquals(LocalDate.of(2026, 8, 3), BillFields.parseDate("2026-08-03 12:15:26"));
        assertEquals(LocalDate.of(2026, 8, 3), BillFields.parseDate("2026/8/3"));
        assertEquals(LocalDate.of(2026, 9, 14), BillFields.parseDate("2026-09-14"));
        assertNull(BillFields.parseDate("共13笔记录"));
    }

    @Test
    void 只有像日期的行才被当作交易数据() {
        assertTrue(BillFields.looksLikeDate("2026-08-03 12:15:26"));
        assertTrue(BillFields.looksLikeDate("2026/8/3"));
        assertFalse(BillFields.looksLikeDate("共13笔记录"));
        assertFalse(BillFields.looksLikeDate(""));
    }

    @Test
    void 收支类型判断以收支列为主() {
        assertEquals(BillType.EXPENSE, BillFields.resolveType("支出"));
        assertEquals(BillType.INCOME, BillFields.resolveType("收入"));
        assertEquals(BillType.NEUTRAL, BillFields.resolveType("/"));
        assertEquals(BillType.NEUTRAL, BillFields.resolveType("不计收支"));
    }

    @Test
    void 资金流转类交易归为不计收支() {
        assertEquals(BillType.NEUTRAL, BillFields.resolveType("支出", "零钱提现"));
        assertEquals(BillType.NEUTRAL, BillFields.resolveType("支出", "转入零钱通-来自工商银行(9876)"));
        // 普通消费不会被误判
        assertEquals(BillType.EXPENSE, BillFields.resolveType("支出", "扫二维码付款", "拿铁"));
    }

    @Test
    void 表头行在前三十行内按列名定位() {
        List<List<String>> rows = List.of(
                List.of("微信支付账单明细"),
                List.of(""),
                List.of("交易时间", "交易类型", "收/支", "金额(元)", "交易单号"),
                List.of("2026-08-03 12:15:26", "商户消费", "支出", "¥31.00", "4200"));

        assertEquals(2, BillFields.findHeaderRow(rows, "交易时间", "金额", "收/支"));
        assertEquals(-1, BillFields.findHeaderRow(rows, "交易时间", "交易订单号"));
    }

    @Test
    void md5结果稳定且长度固定() {
        String first = BillFields.md5("WECHAT|2026-08-03 12:15:26|31.00|星巴克|1");
        String second = BillFields.md5("WECHAT|2026-08-03 12:15:26|31.00|星巴克|1");

        assertEquals(first, second);
        assertEquals(32, first.length());
        assertNotEquals(first, BillFields.md5("WECHAT|2026-08-03 12:15:26|31.01|星巴克|1"));
    }
}
