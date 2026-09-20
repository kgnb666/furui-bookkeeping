package com.campus.ledger.importer;

import com.campus.ledger.common.BizException;
import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVParser;
import org.apache.commons.csv.CSVRecord;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.Charset;
import java.nio.charset.CharsetDecoder;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 把上传的账单文件读成一张二维表格。
 * CSV 需要探测编码（微信是 UTF-8，支付宝是 GBK/GB18030），Excel 用 POI 读取。
 */
public class BillFileReader {

    private BillFileReader() {
    }

    public static List<List<String>> read(byte[] bytes, String fileName) {
        if (bytes == null || bytes.length == 0) {
            throw new BizException(400, "上传的账单文件是空文件");
        }
        String name = fileName == null ? "" : fileName.toLowerCase(Locale.ROOT);
        if (name.endsWith(".csv")) {
            return readCsv(bytes);
        }
        if (name.endsWith(".xlsx")) {
            return readExcel(bytes);
        }
        throw new BizException(400, "仅支持 CSV 或 Excel(.xlsx) 格式的账单文件");
    }

    static List<List<String>> readCsv(byte[] bytes) {
        int offset = hasUtf8Bom(bytes) ? 3 : 0;
        String text = new String(bytes, offset, bytes.length - offset, detectCharset(bytes));
        List<List<String>> rows = new ArrayList<>();
        try (CSVParser parser = CSVParser.parse(text, CSVFormat.DEFAULT.builder()
                .setIgnoreEmptyLines(false)
                .setIgnoreSurroundingSpaces(true)
                .build())) {
            for (CSVRecord record : parser) {
                List<String> cells = new ArrayList<>(record.size());
                for (String value : record) {
                    cells.add(value);
                }
                rows.add(cells);
            }
        } catch (IOException e) {
            throw new BizException(400, "账单文件读取失败，请确认文件未损坏");
        }
        return rows;
    }

    static List<List<String>> readExcel(byte[] bytes) {
        DataFormatter formatter = new DataFormatter(Locale.CHINA);
        List<List<String>> rows = new ArrayList<>();
        try (Workbook workbook = new XSSFWorkbook(new ByteArrayInputStream(bytes))) {
            Sheet sheet = workbook.getSheetAt(0);
            for (Row row : sheet) {
                List<String> cells = new ArrayList<>();
                int lastCell = row.getLastCellNum();
                for (int c = 0; c < lastCell; c++) {
                    Cell cell = row.getCell(c, Row.MissingCellPolicy.RETURN_BLANK_AS_NULL);
                    cells.add(cell == null ? "" : formatter.formatCellValue(cell));
                }
                rows.add(cells);
            }
        } catch (IOException | RuntimeException e) {
            throw new BizException(400, "Excel 账单解析失败，请确认文件未损坏或改用 CSV 文件");
        }
        return rows;
    }

    /**
     * 先看 BOM，再用严格模式尝试 UTF-8，失败则按 GB18030 处理。
     */
    static Charset detectCharset(byte[] bytes) {
        if (hasUtf8Bom(bytes)) {
            return StandardCharsets.UTF_8;
        }
        CharsetDecoder decoder = StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT);
        try {
            decoder.decode(ByteBuffer.wrap(bytes));
            return StandardCharsets.UTF_8;
        } catch (CharacterCodingException e) {
            return Charset.forName("GB18030");
        }
    }

    static boolean hasUtf8Bom(byte[] bytes) {
        return bytes.length >= 3
                && (bytes[0] & 0xFF) == 0xEF
                && (bytes[1] & 0xFF) == 0xBB
                && (bytes[2] & 0xFF) == 0xBF;
    }
}
