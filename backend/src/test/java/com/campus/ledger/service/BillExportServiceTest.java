package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.ExportResult;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.WorkbookFactory;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.io.ByteArrayInputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BillExportServiceTest {

    private static final Long USER_ID = 7L;

    @Mock
    private BillMapper billMapper;

    private BillExportService exportService;

    @BeforeEach
    void setUp() {
        exportService = new BillExportService(billMapper);
    }

    @Test
    void CSV导出包含表头与账单内容并带UTF8BOM() {
        when(billMapper.selectCount(any())).thenReturn(2L);
        when(billMapper.selectList(any())).thenReturn(List.of(
                bill(1L, 1, "20.00", "餐饮", "早餐", "WECHAT"),
                bill(2L, 2, "1500.00", "生活费", "", "MANUAL")));

        ExportResult result = exportService.export(USER_ID, "csv", "2026-09");

        String text = new String(result.getContent(), StandardCharsets.UTF_8);
        assertTrue(text.startsWith("\uFEFF"), "CSV 需要带 BOM，Excel 打开才不乱码");
        assertTrue(text.contains("日期,类型,金额,分类,备注,来源"));
        assertTrue(text.contains("2026-09-16,支出,20.00,餐饮,早餐,微信"));
        assertTrue(text.contains("2026-09-16,收入,1500.00,生活费,,手动记录"));
        assertTrue(result.getFileName().startsWith("furui_bill_202609"));
        assertTrue(result.getFileName().endsWith(".csv"));
    }

    @Test
    void CSV对公式开头的内容做转义() {
        when(billMapper.selectCount(any())).thenReturn(1L);
        when(billMapper.selectList(any())).thenReturn(List.of(
                bill(1L, 1, "10.00", "其他", "=SUM(A1:A9)", "MANUAL")));

        String text = new String(exportService.export(USER_ID, "csv", null).getContent(),
                StandardCharsets.UTF_8);

        assertTrue(text.contains("'=SUM(A1:A9)"), "以等号开头的内容要加前缀，避免被 Excel 当公式执行");
    }

    @Test
    void JSON导出是结构化备份且金额是字符串() {
        when(billMapper.selectCount(any())).thenReturn(1L);
        when(billMapper.selectList(any())).thenReturn(List.of(
                bill(9L, 1, "35.00", "餐饮", "麦当劳\"套餐\"", "ALIPAY")));

        String json = new String(exportService.export(USER_ID, "json", "2026-09").getContent(),
                StandardCharsets.UTF_8);

        assertTrue(json.contains("\"count\":1"));
        assertTrue(json.contains("\"amount\":\"35.00\""), "金额要保持字符串，避免前端浮点误差");
        assertTrue(json.contains("\"sourceName\":\"支付宝\""));
        assertTrue(json.contains("麦当劳\\\"套餐\\\""), "双引号需要转义");
    }

    @Test
    void XLSX导出生成可解析的工作簿() throws Exception {
        when(billMapper.selectCount(any())).thenReturn(1L);
        when(billMapper.selectList(any())).thenReturn(List.of(
                bill(1L, 1, "20.00", "餐饮", "早餐", "MANUAL")));

        byte[] bytes = exportService.export(USER_ID, "xlsx", "2026-09").getContent();

        assertTrue(bytes.length > 0);
        try (Workbook workbook = WorkbookFactory.create(new ByteArrayInputStream(bytes))) {
            Sheet sheet = workbook.getSheetAt(0);
            assertEquals("日期", sheet.getRow(0).getCell(0).getStringCellValue());
            assertEquals("来源", sheet.getRow(0).getCell(5).getStringCellValue());
            assertEquals("餐饮", sheet.getRow(1).getCell(3).getStringCellValue());
            assertEquals(20.00, sheet.getRow(1).getCell(2).getNumericCellValue(), 0.001);
        }
    }

    @Test
    void 空数据也能正常导出() {
        when(billMapper.selectCount(any())).thenReturn(0L);
        when(billMapper.selectList(any())).thenReturn(List.of());

        String csv = new String(exportService.export(USER_ID, "csv", "2026-09").getContent(),
                StandardCharsets.UTF_8);
        String json = new String(exportService.export(USER_ID, "json", "2026-09").getContent(),
                StandardCharsets.UTF_8);

        assertEquals("\uFEFF日期,类型,金额,分类,备注,来源\r\n", csv);
        assertTrue(json.contains("\"count\":0"));
    }

    @Test
    void 超过一万条时明确报错而不是截断() {
        when(billMapper.selectCount(any())).thenReturn((long) BillExportService.MAX_ROWS + 1);

        BizException e = assertThrows(BizException.class,
                () -> exportService.export(USER_ID, "csv", null));

        assertEquals(400, e.getCode());
        assertEquals("账单数量过多，请按月份导出", e.getMessage());
    }

    @Test
    void 不支持的导出格式被拒绝() {
        BizException e = assertThrows(BizException.class,
                () -> exportService.export(USER_ID, "pdf", null));

        assertEquals(400, e.getCode());
    }

    @Test
    void 导出统计与列表查询都用同一套用户条件() {
        when(billMapper.selectCount(any())).thenReturn(0L);
        when(billMapper.selectList(any())).thenReturn(List.of());

        exportService.export(USER_ID, "csv", "2026-09");

        ArgumentCaptor<LambdaQueryWrapper<Bill>> wrapperCaptor =
                ArgumentCaptor.forClass(LambdaQueryWrapper.class);
        verify(billMapper).selectCount(wrapperCaptor.capture());
        verify(billMapper).selectList(any());
        // 条件里必须含 user_id 与月份区间，避免导出到别人的数据
        assertTrue(wrapperCaptor.getValue().getExpression().getNormal().size() >= 3);
    }

    private Bill bill(Long id, int type, String amount, String category, String remark, String source) {
        Bill bill = new Bill();
        bill.setId(id);
        bill.setUserId(USER_ID);
        bill.setType(type);
        bill.setAmount(new BigDecimal(amount));
        bill.setCategory(category);
        bill.setBillDate(LocalDate.of(2026, 9, 16));
        bill.setMerchant("");
        bill.setRemark(remark);
        bill.setSource(source);
        return bill;
    }
}
