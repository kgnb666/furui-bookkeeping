package com.campus.ledger.service;

import com.campus.ledger.SampleFiles;
import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.ImportConfirmItem;
import com.campus.ledger.dto.ImportConfirmRequest;
import com.campus.ledger.dto.ImportPreviewItem;
import com.campus.ledger.dto.ImportPreviewResponse;
import com.campus.ledger.dto.ImportResultResponse;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.entity.ImportBatch;
import com.campus.ledger.importer.AlipayBillParser;
import com.campus.ledger.importer.WechatBillParser;
import com.campus.ledger.mapper.BillMapper;
import com.campus.ledger.mapper.ImportBatchMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.mock.web.MockMultipartFile;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BillImportServiceTest {

    private static final Long USER_ID = 7L;

    @Mock
    private BillMapper billMapper;

    @Mock
    private ImportBatchMapper importBatchMapper;

    private BillImportService service;

    @BeforeEach
    void setUp() {
        service = new BillImportService(billMapper, importBatchMapper,
                new WechatBillParser(), new AlipayBillParser(), new CategoryMatcher());
    }

    @Test
    void 有交易号时去重键用来源加交易号() {
        String key = BillImportService.buildDedupKey(BillSource.WECHAT, "4200002000202608031234567890",
                "2026-08-03 12:15:26", new BigDecimal("31.00"), "星巴克", com.campus.ledger.common.BillType.EXPENSE);

        assertEquals("WECHAT:4200002000202608031234567890", key);
    }

    @Test
    void 没有交易号时用组合字段指纹且结果稳定() {
        String first = BillImportService.buildDedupKey(BillSource.ALIPAY, "/", "2026-08-30 11:20:00",
                new BigDecimal("12.00"), "校医院", com.campus.ledger.common.BillType.EXPENSE);
        String same = BillImportService.buildDedupKey(BillSource.ALIPAY, "", "2026-08-30 11:20:00",
                new BigDecimal("12.00"), "校医院", com.campus.ledger.common.BillType.EXPENSE);
        String otherAmount = BillImportService.buildDedupKey(BillSource.ALIPAY, null, "2026-08-30 11:20:00",
                new BigDecimal("12.01"), "校医院", com.campus.ledger.common.BillType.EXPENSE);
        String otherTime = BillImportService.buildDedupKey(BillSource.ALIPAY, null, "2026-08-31 11:20:00",
                new BigDecimal("12.00"), "校医院", com.campus.ledger.common.BillType.EXPENSE);

        assertEquals(first, same, "斜杠、空值与 null 都应视为没有交易号");
        assertNotEquals(first, otherAmount);
        assertNotEquals(first, otherTime);
        assertTrue(first.startsWith("ALIPAY:"));
        assertEquals(39, first.length());
    }

    @Test
    void 交易号过长时改用MD5且不超过字段长度() {
        String key = BillImportService.buildDedupKey(BillSource.WECHAT, "9".repeat(80),
                null, new BigDecimal("1.00"), "某商户", com.campus.ledger.common.BillType.EXPENSE);

        assertTrue(key.length() <= 80, "去重键不能超过 dedup_key 字段长度");
        assertEquals("WECHAT:", key.substring(0, 7));
    }

    @Test
    void 文件名只保留文件名本身() {
        assertEquals("账单.csv", BillImportService.sanitizeFileName("C:\\Users\\a\\账单.csv"));
        assertEquals("账单.csv", BillImportService.sanitizeFileName("../../账单.csv"));
        assertEquals("未命名账单", BillImportService.sanitizeFileName(null));
    }

    @Test
    void 预览微信账单会标记重复并给出默认勾选与推荐分类() {
        when(billMapper.selectExistingDedupKeys(eq(USER_ID), anyList()))
                .thenReturn(List.of("WECHAT:4200002000202608031234567890"));

        ImportPreviewResponse response = service.preview(USER_ID, wechatFile(), "WECHAT");

        assertEquals(13, response.getTotalCount());
        assertEquals(1, response.getDuplicateCount());
        assertEquals(1, response.getNeutralCount());
        assertEquals(0, response.getFailedCount());
        assertEquals(11, response.getNewCount());

        ImportPreviewItem duplicated = response.getItems().stream()
                .filter(ImportPreviewItem::isDuplicate).findFirst().orElseThrow();
        assertFalse(duplicated.isDefaultSelected(), "重复记录默认不勾选");
        assertEquals("与已有记录重复", duplicated.getDuplicateReason());

        ImportPreviewItem neutral = response.getItems().stream()
                .filter(item -> Integer.valueOf(3).equals(item.getType())).findFirst().orElseThrow();
        assertFalse(neutral.isDefaultSelected(), "不计收支记录默认不勾选");
        assertTrue(neutral.isImportable());

        assertEquals("星巴克", duplicated.getMerchant(), "重复的应该是库中已存在的那一笔");

        ImportPreviewItem normal = response.getItems().stream()
                .filter(item -> "瑞幸咖啡".equals(item.getMerchant())).findFirst().orElseThrow();
        assertTrue(normal.isDefaultSelected(), "新增记录默认勾选");
        assertEquals("餐饮", normal.getCategory());
        assertEquals("KEYWORD", normal.getCategoryFrom());
        assertEquals("19.90", normal.getAmount());
    }

    @Test
    void 预览支付宝账单能识别GBK编码与不计收支() {
        when(billMapper.selectExistingDedupKeys(eq(USER_ID), anyList())).thenReturn(List.of());

        MockMultipartFile file = new MockMultipartFile("file", "alipay-sample.csv", "text/csv",
                SampleFiles.bytes("alipay-sample.csv"));
        ImportPreviewResponse response = service.preview(USER_ID, file, "ALIPAY");

        assertEquals(12, response.getTotalCount());
        assertEquals(0, response.getDuplicateCount());
        assertEquals(1, response.getNeutralCount());
        assertEquals(11, response.getNewCount());
    }

    @Test
    void 来源与文件不匹配时给出明确提示() {
        MockMultipartFile file = new MockMultipartFile("file", "alipay-sample.csv", "text/csv",
                SampleFiles.bytes("alipay-sample.csv"));

        BizException e = assertThrows(BizException.class, () -> service.preview(USER_ID, file, "WECHAT"));

        assertEquals(400, e.getCode());
        assertTrue(e.getMessage().contains("支付宝"), e.getMessage());
    }

    @Test
    void 商户版账单会被拒绝而不是猜字段() {
        byte[] merchantBill = ("交易时间,微信支付单号,商户订单号,交易金额(元),交易状态\n"
                + "2026-08-03 12:15:26,4200001,M20260803001,31.00,买家已支付\n")
                .getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "商户账单.csv", "text/csv", merchantBill);

        BizException e = assertThrows(BizException.class, () -> service.preview(USER_ID, file, "WECHAT"));

        assertTrue(e.getMessage().contains("暂不支持"), e.getMessage());
    }

    @Test
    void 确认导入时服务端重新计算去重键并记录批次() {
        when(importBatchMapper.insert(any(ImportBatch.class))).thenAnswer(invocation -> {
            ImportBatch batch = invocation.getArgument(0);
            batch.setId(9L);
            return 1;
        });
        when(billMapper.insert(any(Bill.class))).thenReturn(1);

        ImportConfirmRequest request = confirmRequest(item("4200002000202608031234567890", "星巴克", "餐饮"));
        ImportResultResponse response = service.confirm(USER_ID, request);

        assertEquals(1, response.getImportedCount());
        assertEquals(0, response.getDuplicateCount());
        assertEquals(0, response.getFailedCount());
        assertEquals(9L, response.getBatchId());

        ArgumentCaptor<Bill> billCaptor = ArgumentCaptor.forClass(Bill.class);
        verify(billMapper).insert(billCaptor.capture());
        Bill inserted = billCaptor.getValue();
        assertEquals("WECHAT:4200002000202608031234567890", inserted.getDedupKey());
        assertEquals(BillSource.WECHAT.name(), inserted.getSource());
        assertEquals(USER_ID, inserted.getUserId());
        assertEquals(9L, inserted.getImportBatchId());
        assertEquals(1, inserted.getType());
    }

    @Test
    void 数据库唯一约束冲突会被计入重复而不是报错() {
        when(importBatchMapper.insert(any(ImportBatch.class))).thenAnswer(invocation -> {
            ImportBatch batch = invocation.getArgument(0);
            batch.setId(10L);
            return 1;
        });
        when(billMapper.insert(any(Bill.class)))
                .thenThrow(new DuplicateKeyException("duplicate"))
                .thenReturn(1);

        ImportConfirmRequest request = confirmRequest(
                item("4200001", "星巴克", "餐饮"),
                item("4200002", "瑞幸咖啡", "餐饮"));
        ImportResultResponse response = service.confirm(USER_ID, request);

        assertEquals(1, response.getImportedCount());
        assertEquals(1, response.getDuplicateCount());
        assertEquals(0, response.getFailedCount());

        ArgumentCaptor<ImportBatch> batchCaptor = ArgumentCaptor.forClass(ImportBatch.class);
        verify(importBatchMapper).updateById(batchCaptor.capture());
        assertEquals(1, batchCaptor.getValue().getImportedCount());
        assertEquals(1, batchCaptor.getValue().getDuplicateCount());
    }

    @Test
    void 确认导入时不合法的分类会被拒绝并给出原因() {
        when(importBatchMapper.insert(any(ImportBatch.class))).thenReturn(1);

        ImportConfirmRequest request = confirmRequest(item("4200003", "星巴克", "不存在的分类"));
        ImportResultResponse response = service.confirm(USER_ID, request);

        assertEquals(0, response.getImportedCount());
        assertEquals(1, response.getFailedCount());
        assertEquals(1, response.getFailures().size());
        assertTrue(response.getFailures().get(0).reason().contains("分类不合法"));
    }

    @Test
    void 金额与日期不合法的确认记录会被拒绝() {
        when(importBatchMapper.insert(any(ImportBatch.class))).thenReturn(1);

        ImportConfirmItem zeroAmount = item("4200004", "星巴克", "餐饮");
        zeroAmount.setAmount(new BigDecimal("0.00"));
        ImportConfirmItem futureDate = item("4200005", "星巴克", "餐饮");
        futureDate.setBillDate(LocalDate.now().plusDays(1));

        ImportResultResponse response = service.confirm(USER_ID, confirmRequest(zeroAmount, futureDate));

        assertEquals(2, response.getFailedCount());
        assertEquals(0, response.getImportedCount());
    }

    @Test
    void 手动来源与空文件会被拒绝() {
        BizException manual = assertThrows(BizException.class,
                () -> service.preview(USER_ID, wechatFile(), "MANUAL"));
        assertEquals(400, manual.getCode());

        MockMultipartFile empty = new MockMultipartFile("file", "empty.csv", "text/csv", new byte[0]);
        BizException emptyFile = assertThrows(BizException.class, () -> service.preview(USER_ID, empty, "WECHAT"));
        assertEquals(400, emptyFile.getCode());
    }

    @Test
    void 只有BOM的空白账单会被拒绝() {
        byte[] bomOnly = {(byte) 0xEF, (byte) 0xBB, (byte) 0xBF};
        MockMultipartFile file = new MockMultipartFile("file", "empty.csv", "text/csv", bomOnly);

        BizException e = assertThrows(BizException.class, () -> service.preview(USER_ID, file, "WECHAT"));

        assertEquals(400, e.getCode());
        assertTrue(e.getMessage().contains("内容为空"), e.getMessage());
    }

    @Test
    void 预览阶段就会拦下未来日期的交易() {
        // 与确认导入的规则保持一致：预览显示可导入的，确认时就不应该再失败
        String tomorrow = LocalDate.now().plusDays(1).toString();
        byte[] csv = ("交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注\n"
                + tomorrow + " 12:00:00,商户消费,星巴克,拿铁,支出,¥31.00,零钱,支付成功,FUTURE0001,FUTUREM1,/\n")
                .getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "future.csv", "text/csv", csv);

        ImportPreviewResponse response = service.preview(USER_ID, file, "WECHAT");

        assertEquals(1, response.getTotalCount());
        assertEquals(1, response.getFailedCount());
        assertEquals(0, response.getNewCount());
        ImportPreviewItem item = response.getItems().get(0);
        assertFalse(item.isImportable());
        assertFalse(item.isDefaultSelected());
        assertTrue(item.getFailReason().contains("日期不能晚于今天"), item.getFailReason());
    }

    private MockMultipartFile wechatFile() {
        return new MockMultipartFile("file", "wechat-sample.csv", "text/csv", SampleFiles.bytes("wechat-sample.csv"));
    }

    private ImportConfirmItem item(String tradeId, String merchant, String category) {
        ImportConfirmItem item = new ImportConfirmItem();
        item.setBillDate(LocalDate.now().minusDays(1));
        item.setSourceTradeTime("2026-08-03 12:15:26");
        item.setMerchant(merchant);
        item.setRemark("拿铁");
        item.setAmount(new BigDecimal("31.00"));
        item.setType("1");
        item.setCategory(category);
        item.setSourceTradeId(tradeId);
        return item;
    }

    private ImportConfirmRequest confirmRequest(ImportConfirmItem... items) {
        ImportConfirmRequest request = new ImportConfirmRequest();
        request.setSource("WECHAT");
        request.setFileName("wechat-sample.csv");
        request.setTotalCount(items.length);
        request.setItems(List.of(items));
        return request;
    }
}
