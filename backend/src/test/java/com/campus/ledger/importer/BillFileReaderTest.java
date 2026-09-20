package com.campus.ledger.importer;

import com.campus.ledger.SampleFiles;
import com.campus.ledger.common.BizException;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BillFileReaderTest {

    @Test
    void 微信样例是UTF8编码() {
        assertEquals(StandardCharsets.UTF_8, BillFileReader.detectCharset(SampleFiles.bytes("wechat-sample.csv")));
    }

    @Test
    void 带BOM的UTF8文件读取后第一格没有BOM() {
        byte[] content = "交易时间,金额\n2026-08-03,31.00\n".getBytes(StandardCharsets.UTF_8);
        byte[] withBom = new byte[content.length + 3];
        withBom[0] = (byte) 0xEF;
        withBom[1] = (byte) 0xBB;
        withBom[2] = (byte) 0xBF;
        System.arraycopy(content, 0, withBom, 3, content.length);

        List<List<String>> rows = BillFileReader.read(withBom, "bill.csv");

        assertEquals("交易时间", rows.get(0).get(0));
        assertFalse(rows.get(0).get(0).contains("\uFEFF"));
    }

    @Test
    void 非UTF8的内容会按GB18030读取() {
        String text = "交易时间,交易分类,收/支,金额\n2026-08-02 12:30:00,餐饮美食,支出,31.00\n";
        byte[] gbk = text.getBytes(Charset.forName("GBK"));

        List<List<String>> rows = BillFileReader.read(gbk, "bill.csv");

        assertEquals("交易时间", rows.get(0).get(0));
        assertEquals("餐饮美食", rows.get(1).get(1));
    }

    @Test
    void 引号里的逗号不会把单元格拆开() {
        byte[] bytes = "交易时间,商品,金额\n2026-08-05,\"总共消费:15.00,含配送费\",15.00\n"
                .getBytes(StandardCharsets.UTF_8);

        List<List<String>> rows = BillFileReader.read(bytes, "bill.csv");

        assertEquals(3, rows.get(1).size());
        assertEquals("总共消费:15.00,含配送费", rows.get(1).get(1));
    }

    @Test
    void 不支持的扩展名会被拒绝() {
        BizException e = assertThrows(BizException.class,
                () -> BillFileReader.read("abc".getBytes(StandardCharsets.UTF_8), "账单.txt"));

        assertEquals(400, e.getCode());
    }

    @Test
    void 空文件会被拒绝() {
        BizException e = assertThrows(BizException.class, () -> BillFileReader.read(new byte[0], "账单.csv"));

        assertEquals(400, e.getCode());
    }

    @Test
    void 可以读取xlsx格式的账单() throws Exception {
        byte[] xlsx = buildWechatXlsx();

        List<List<String>> rows = BillFileReader.read(xlsx, "账单.xlsx");
        WechatBillParser parser = new WechatBillParser();

        assertTrue(parser.supports(rows));
        List<ParsedBill> bills = parser.parse(rows);
        assertEquals(1, bills.size());
        assertEquals("星巴克", bills.get(0).getMerchant());
        assertEquals("31.00", bills.get(0).getAmount().toPlainString());
    }

    private byte[] buildWechatXlsx() throws Exception {
        try (XSSFWorkbook workbook = new XSSFWorkbook(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Sheet sheet = workbook.createSheet("账单");
            String[] header = {"交易时间", "交易类型", "交易对方", "商品", "收/支", "金额(元)",
                    "支付方式", "当前状态", "交易单号", "商户单号", "备注"};
            Row headerRow = sheet.createRow(0);
            for (int i = 0; i < header.length; i++) {
                headerRow.createCell(i).setCellValue(header[i]);
            }
            String[] data = {"2026-08-03 12:15:26", "商户消费", "星巴克", "拿铁", "支出", "¥31.00",
                    "零钱", "支付成功", "4200002000202608031234567890", "4200001234567801", "/"};
            Row dataRow = sheet.createRow(1);
            for (int i = 0; i < data.length; i++) {
                dataRow.createCell(i).setCellValue(data[i]);
            }
            workbook.write(out);
            return out.toByteArray();
        }
    }
}
