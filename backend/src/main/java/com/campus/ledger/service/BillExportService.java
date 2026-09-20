package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.ExportResult;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.CellType;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.StringWriter;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * 账单导出：CSV / XLSX / JSON 三种格式。
 *
 * 约束：
 *   1. 只导出当前登录用户的账单，查询条件永远带 user_id；
 *   2. 单次最多 MAX_ROWS 条，超出时明确报错而不是截断；
 *   3. 金额一律 BigDecimal，输出保留两位小数。
 */
@Service
public class BillExportService {

    /** 单次导出的最大条数，xlsx 使用 XSSFWorkbook，避免一次导入过多导致内存压力 */
    public static final int MAX_ROWS = 10000;

    private static final DateTimeFormatter FILE_STAMP = DateTimeFormatter.ofPattern("yyyyMMddHHmmss");
    private static final List<String> HEADERS =
            List.of("日期", "类型", "金额", "分类", "备注", "来源");

    private final BillMapper billMapper;

    public BillExportService(BillMapper billMapper) {
        this.billMapper = billMapper;
    }

    public ExportResult export(Long userId, String format, String month) {
        String normalized = format == null ? "csv" : format.trim().toLowerCase();
        if (!List.of("csv", "xlsx", "json").contains(normalized)) {
            throw new BizException(400, "导出格式只支持 csv / xlsx / json");
        }
        String monthLabel = normalizeMonth(month);
        List<Bill> bills = load(userId, month);

        String fileName = buildFileName(normalized, monthLabel);
        byte[] content = switch (normalized) {
            case "xlsx" -> toXlsx(bills);
            case "json" -> toJson(bills);
            default -> toCsv(bills);
        };
        return new ExportResult(fileName, contentType(normalized), content);
    }

    /** 月份为空表示导出全部账单 */
    private String normalizeMonth(String month) {
        if (!StringUtils.hasText(month)) {
            return null;
        }
        return Months.parse(month.trim()).toString();
    }

    private List<Bill> load(Long userId, String month) {
        LambdaQueryWrapper<Bill> wrapper = new LambdaQueryWrapper<Bill>()
                .eq(Bill::getUserId, userId);
        YearMonth yearMonth = month == null ? null : YearMonth.parse(month);
        if (yearMonth != null) {
            wrapper.ge(Bill::getBillDate, yearMonth.atDay(1))
                    .le(Bill::getBillDate, yearMonth.atEndOfMonth());
        }

        long total = billMapper.selectCount(wrapper);
        if (total > MAX_ROWS) {
            // 明确报错，不做静默截断，避免用户以为导出完整
            throw new BizException(400, "账单数量过多，请按月份导出");
        }

        wrapper.orderByDesc(Bill::getBillDate).orderByDesc(Bill::getId);
        return billMapper.selectList(wrapper);
    }

    private String buildFileName(String format, String month) {
        String stamp = LocalDateTime.now().format(FILE_STAMP);
        String suffix = month == null ? stamp : month.replace("-", "") + "_" + stamp;
        return "furui_bill_" + suffix + "." + format;
    }

    private String contentType(String format) {
        return switch (format) {
            case "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
            case "json" -> "application/json;charset=UTF-8";
            default -> "text/csv;charset=UTF-8";
        };
    }

    // ==================== CSV ====================

    /**
     * 带 UTF-8 BOM，Excel 直接双击打开不会乱码。
     */
    byte[] toCsv(List<Bill> bills) {
        StringBuilder builder = new StringBuilder("\uFEFF");
        builder.append(String.join(",", HEADERS)).append("\r\n");
        for (Bill bill : bills) {
            builder.append(csvCell(bill.getBillDate() == null ? "" : bill.getBillDate().toString())).append(',')
                    .append(csvCell(typeName(bill.getType()))).append(',')
                    .append(csvCell(money(bill.getAmount()))).append(',')
                    .append(csvCell(bill.getCategory())).append(',')
                    .append(csvCell(bill.getRemark())).append(',')
                    .append(csvCell(sourceName(bill.getSource())))
                    .append("\r\n");
        }
        return builder.toString().getBytes(StandardCharsets.UTF_8);
    }

    /**
     * CSV 单元格转义：含逗号/引号/换行时加引号；
     * 以 = + - @ 开头的内容加前缀单引号，避免被 Excel 当成公式执行。
     */
    private static String csvCell(String raw) {
        String value = raw == null ? "" : raw;
        if (!value.isEmpty() && "=+-@".indexOf(value.charAt(0)) >= 0) {
            value = "'" + value;
        }
        if (value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")) {
            return "\"" + value.replace("\"", "\"\"") + "\"";
        }
        return value;
    }

    // ==================== XLSX ====================

    byte[] toXlsx(List<Bill> bills) {
        try (Workbook workbook = new XSSFWorkbook();
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Sheet sheet = workbook.createSheet("账单");
            CellStyle headerStyle = workbook.createCellStyle();
            Font headerFont = workbook.createFont();
            headerFont.setBold(true);
            headerStyle.setFont(headerFont);

            Row header = sheet.createRow(0);
            for (int i = 0; i < HEADERS.size(); i++) {
                Cell cell = header.createCell(i);
                cell.setCellValue(HEADERS.get(i));
                cell.setCellStyle(headerStyle);
                sheet.setColumnWidth(i, i == 4 ? 8000 : 4000);
            }

            int rowIndex = 1;
            for (Bill bill : bills) {
                Row row = sheet.createRow(rowIndex++);
                writeText(row, 0, bill.getBillDate() == null ? "" : bill.getBillDate().toString());
                writeText(row, 1, typeName(bill.getType()));
                // 金额写成数值，Excel 里可以直接求和
                Cell amountCell = row.createCell(2);
                amountCell.setCellValue(nullToZero(bill.getAmount()).doubleValue());
                writeText(row, 3, bill.getCategory());
                writeText(row, 4, bill.getRemark());
                writeText(row, 5, sourceName(bill.getSource()));
            }

            workbook.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new BizException(500, "生成表格文件失败：" + e.getMessage());
        }
    }

    private static void writeText(Row row, int index, String value) {
        Cell cell = row.createCell(index, CellType.STRING);
        cell.setCellValue(value == null ? "" : value);
    }

    // ==================== JSON ====================

    byte[] toJson(List<Bill> bills) {
        StringWriter writer = new StringWriter();
        writer.write('{');
        writer.write("\"app\":\"福瑞记账\",");
        writer.write("\"exportedAt\":\"" + LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME) + "\",");
        writer.write("\"count\":" + bills.size() + ",");
        writer.write("\"bills\":[");
        for (int i = 0; i < bills.size(); i++) {
            Bill bill = bills.get(i);
            if (i > 0) {
                writer.write(',');
            }
            writer.write('{');
            writer.write("\"id\":" + bill.getId() + ",");
            writer.write("\"billDate\":" + json(bill.getBillDate() == null ? "" : bill.getBillDate().toString()) + ",");
            writer.write("\"type\":" + (bill.getType() == null ? 0 : bill.getType()) + ",");
            writer.write("\"typeName\":" + json(typeName(bill.getType())) + ",");
            writer.write("\"amount\":" + json(money(bill.getAmount())) + ",");
            writer.write("\"category\":" + json(bill.getCategory()) + ",");
            writer.write("\"merchant\":" + json(bill.getMerchant()) + ",");
            writer.write("\"remark\":" + json(bill.getRemark()) + ",");
            writer.write("\"source\":" + json(bill.getSource() == null ? "" : bill.getSource()) + ",");
            writer.write("\"sourceName\":" + json(sourceName(bill.getSource())));
            writer.write('}');
        }
        writer.write("]}");
        return writer.toString().getBytes(StandardCharsets.UTF_8);
    }

    private static String json(String value) {
        if (value == null) {
            return "null";
        }
        StringBuilder builder = new StringBuilder(value.length() + 2);
        builder.append('"');
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"' -> builder.append("\\\"");
                case '\\' -> builder.append("\\\\");
                case '\n' -> builder.append("\\n");
                case '\r' -> builder.append("\\r");
                case '\t' -> builder.append("\\t");
                default -> {
                    if (c < 0x20) {
                        builder.append(String.format("\\u%04x", (int) c));
                    } else {
                        builder.append(c);
                    }
                }
            }
        }
        return builder.append('"').toString();
    }

    // ==================== 公共工具 ====================

    private static String typeName(Integer type) {
        BillType billType = BillType.of(type);
        return billType == null ? "" : billType.getLabel();
    }

    private static String sourceName(String source) {
        BillSource billSource = BillSource.parse(source);
        return billSource == null ? (source == null ? "" : source) : billSource.getLabel();
    }

    private static String money(BigDecimal amount) {
        return nullToZero(amount).setScale(2, RoundingMode.HALF_UP).toPlainString();
    }

    private static BigDecimal nullToZero(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value;
    }

    /** 供测试断言使用：导出的表头顺序 */
    public static List<String> headers() {
        return HEADERS;
    }
}
