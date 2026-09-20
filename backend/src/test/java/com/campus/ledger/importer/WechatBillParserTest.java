package com.campus.ledger.importer;

import com.campus.ledger.SampleFiles;
import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BillType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class WechatBillParserTest {

    private final WechatBillParser parser = new WechatBillParser();
    private List<ParsedBill> bills;

    @BeforeEach
    void parseSample() {
        List<List<String>> rows = BillFileReader.read(SampleFiles.bytes("wechat-sample.csv"), "wechat-sample.csv");
        assertTrue(parser.supports(rows), "应该能识别微信个人对账账单");
        bills = parser.parse(rows);
    }

    @Test
    void 解析出全部交易且没有误判失败行() {
        assertEquals(13, bills.size());
        // 说明行与结尾的“共13笔记录”不应该被当成解析失败的数据行
        assertEquals(0, bills.stream().filter(ParsedBill::isParseFailed).count());
    }

    @Test
    void 收支类型识别正确() {
        assertEquals(11, bills.stream().filter(b -> b.getType() == BillType.EXPENSE).count());
        assertEquals(1, bills.stream().filter(b -> b.getType() == BillType.INCOME).count());
        assertEquals(1, bills.stream().filter(b -> b.getType() == BillType.NEUTRAL).count());
    }

    @Test
    void 金额带货币符号也能正确解析() {
        ParsedBill first = bills.get(0);
        assertEquals(new BigDecimal("31.00"), first.getAmount());
        assertEquals(LocalDate.of(2026, 8, 3), first.getBillDate());
        assertEquals("星巴克", first.getMerchant());

        ParsedBill income = bills.stream().filter(b -> b.getType() == BillType.INCOME).findFirst().orElseThrow();
        assertEquals(new BigDecimal("500.00"), income.getAmount());
        assertEquals(BillSource.WECHAT, parser.source());
    }

    @Test
    void 制表符与多出来的空格被清理() {
        ParsedBill last = bills.get(bills.size() - 1);
        assertEquals("4200002000202609121620007733", last.getSourceTradeId());
        assertEquals("拼多多", last.getMerchant());
        assertEquals(new BigDecimal("45.60"), last.getAmount());
    }

    @Test
    void 交易单号为斜杠时视为没有交易号() {
        ParsedBill noTradeId = bills.stream()
                .filter(b -> "蜜雪冰城".equals(b.getMerchant()))
                .findFirst()
                .orElseThrow();

        assertTrue(noTradeId.getSourceTradeId().isEmpty(), "斜杠应被当成没有交易号，用于走备用去重规则");
    }

    @Test
    void 提现类交易被识别为不计收支() {
        ParsedBill withdraw = bills.stream()
                .filter(b -> b.getType() == BillType.NEUTRAL)
                .findFirst()
                .orElseThrow();

        assertEquals("招商银行()", withdraw.getMerchant());
    }

    @Test
    void 说明行里的关键词不会被误当成数据行() {
        assertEquals(0, bills.stream().filter(b -> b.getMerchant().contains("充值/提现")).count());
    }

    @Test
    void 商户版账单不被支持() {
        List<List<String>> merchantBill = List.of(
                List.of("微信支付商户账单"),
                List.of("交易时间", "微信支付单号", "商户订单号", "交易金额(元)", "交易状态"),
                List.of("2026-08-03 12:15:26", "4200001", "M20260803001", "31.00", "买家已支付"));

        assertFalse(parser.supports(merchantBill));
    }

    @Test
    void 支付宝账单不会被微信解析器接受() {
        List<List<String>> alipayRows = BillFileReader.read(SampleFiles.bytes("alipay-sample.csv"), "alipay-sample.csv");

        assertFalse(parser.supports(alipayRows));
    }
}
