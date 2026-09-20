package com.campus.ledger.importer;

import com.campus.ledger.SampleFiles;
import com.campus.ledger.common.BillType;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AlipayBillParserTest {

    private final AlipayBillParser parser = new AlipayBillParser();
    private List<ParsedBill> bills;

    @BeforeEach
    void parseSample() {
        List<List<String>> rows = BillFileReader.read(SampleFiles.bytes("alipay-sample.csv"), "alipay-sample.csv");
        assertTrue(parser.supports(rows), "应该能识别支付宝个人对账账单");
        bills = parser.parse(rows);
    }

    @Test
    void 样例文件确实是GBK编码() {
        byte[] utf8 = "交易时间,交易分类,收/支,金额,交易订单号\n2026-08-02 12:30:00,餐饮美食,支出,31.00,20260802\n"
                .getBytes(StandardCharsets.UTF_8);

        assertEquals(StandardCharsets.UTF_8, BillFileReader.detectCharset(utf8));
        assertEquals("GB18030", BillFileReader.detectCharset(SampleFiles.bytes("alipay-sample.csv")).name());
    }

    @Test
    void 解析出全部交易且没有误判失败行() {
        assertEquals(12, bills.size());
        assertEquals(0, bills.stream().filter(ParsedBill::isParseFailed).count());
    }

    @Test
    void 收支类型识别正确() {
        assertEquals(10, bills.stream().filter(b -> b.getType() == BillType.EXPENSE).count());
        assertEquals(1, bills.stream().filter(b -> b.getType() == BillType.INCOME).count());
        assertEquals(1, bills.stream().filter(b -> b.getType() == BillType.NEUTRAL).count());
    }

    @Test
    void 金额与交易号解析正确() {
        ParsedBill first = bills.get(0);
        assertEquals(new BigDecimal("31.00"), first.getAmount());
        assertEquals("20260802xxxx0001", first.getSourceTradeId());
        assertEquals("星巴克(武汉光谷店)", first.getMerchant());
    }

    @Test
    void 交易订单号为空时视为没有交易号() {
        ParsedBill noTradeId = bills.stream()
                .filter(b -> "校医院".equals(b.getMerchant()))
                .findFirst()
                .orElseThrow();

        assertTrue(noTradeId.getSourceTradeId().isEmpty());
    }

    @Test
    void 收入与不计收支识别正确() {
        ParsedBill income = bills.stream().filter(b -> b.getType() == BillType.INCOME).findFirst().orElseThrow();
        assertEquals(new BigDecimal("1500.00"), income.getAmount());
        assertEquals("妈妈", income.getMerchant());

        ParsedBill neutral = bills.stream().filter(b -> b.getType() == BillType.NEUTRAL).findFirst().orElseThrow();
        assertEquals("余额宝-转出到余额", neutral.getRemark().trim());
    }

    @Test
    void 支付宝自带交易分类被作为分类提示保留() {
        assertEquals("餐饮美食", bills.get(0).getCategoryHint());
    }

    @Test
    void 微信账单不会被支付宝解析器接受() {
        List<List<String>> wechatRows = BillFileReader.read(SampleFiles.bytes("wechat-sample.csv"), "wechat-sample.csv");

        assertFalse(parser.supports(wechatRows));
    }
}
