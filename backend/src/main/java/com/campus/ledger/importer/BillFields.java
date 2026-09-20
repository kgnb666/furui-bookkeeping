package com.campus.ledger.importer;

import com.campus.ledger.common.BillType;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 解析账单时共用的单元格清洗与字段转换。
 * 微信和支付宝的账单里都可能有制表符、对齐空格、货币符号和引号，统一在这里处理。
 */
public class BillFields {

    /** 交易时间可能出现的几种写法 */
    private static final DateTimeFormatter[] DATE_PATTERNS = {
            DateTimeFormatter.ofPattern("yyyy-M-d H:m:s"),
            DateTimeFormatter.ofPattern("yyyy-M-d H:m"),
            DateTimeFormatter.ofPattern("yyyy-M-d"),
            DateTimeFormatter.ofPattern("yyyy/M/d H:m:s"),
            DateTimeFormatter.ofPattern("yyyy/M/d H:m"),
            DateTimeFormatter.ofPattern("yyyy/M/d")
    };

    /** 资金在自己账户之间流转的交易类型，这类交易一律归为不计收支 */
    private static final List<String> NEUTRAL_KEYWORDS = List.of(
            "零钱提现", "零钱充值", "零钱通", "理财通", "信用卡还款", "转出到余额", "转入余额宝");

    private BillFields() {
    }

    /** 去掉 BOM、制表符、首尾空格与包裹的引号 */
    public static String clean(String value) {
        if (value == null) {
            return "";
        }
        String text = value.replace("\uFEFF", "").replace("\t", " ").trim();
        if (text.length() >= 2 && text.startsWith("\"") && text.endsWith("\"")) {
            text = text.substring(1, text.length() - 1).trim();
        }
        return text;
    }

    public static String cell(List<String> row, Integer column) {
        if (column == null || column < 0 || column >= row.size()) {
            return "";
        }
        return row.get(column);
    }

    /** 类似 2026-08-03 12:15:26 或 2026/8/3 才可能是数据行 */
    public static boolean looksLikeDate(String value) {
        return clean(value).matches("^\\d{4}[-/.]\\d{1,2}[-/.]\\d{1,2}.*");
    }

    public static LocalDate parseDate(String value) {
        String text = clean(value);
        if (text.isEmpty()) {
            return null;
        }
        for (DateTimeFormatter formatter : DATE_PATTERNS) {
            try {
                return LocalDate.parse(text, formatter);
            } catch (DateTimeParseException ignored) {
                // 换下一种格式继续尝试
            }
        }
        return null;
    }

    /** 把 "¥28.16"、 " 1,280.00 " 之类的文本转成两位小数的金额，失败返回 null */
    public static BigDecimal parseAmount(String value) {
        String text = clean(value)
                .replace("¥", "")
                .replace("￥", "")
                .replace(",", "")
                .replace("，", "")
                .replace(" ", "");
        if (text.isEmpty()) {
            return null;
        }
        try {
            return new BigDecimal(text).setScale(2, RoundingMode.HALF_UP);
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * 判断收支类型：以账单的“收/支”列为主，资金流转类交易统一归为不计收支。
     */
    public static BillType resolveType(String payDirection, String... neutralHints) {
        String direction = clean(payDirection);
        BillType type;
        if ("支出".equals(direction)) {
            type = BillType.EXPENSE;
        } else if ("收入".equals(direction)) {
            type = BillType.INCOME;
        } else {
            type = BillType.NEUTRAL;
        }
        if (type != BillType.NEUTRAL) {
            for (String hint : neutralHints) {
                String text = clean(hint);
                for (String keyword : NEUTRAL_KEYWORDS) {
                    if (text.contains(keyword)) {
                        return BillType.NEUTRAL;
                    }
                }
            }
        }
        return type;
    }

    /** 把 " / " 之类的占位值转成空字符串 */
    public static String cleanOptional(String value) {
        String text = clean(value);
        return "/".equals(text) || "-".equals(text) ? "" : text;
    }

    /** 在前 30 行里找表头行，要求同时包含指定的列名 */
    public static int findHeaderRow(List<List<String>> rows, String... keywords) {
        int limit = Math.min(rows.size(), 30);
        for (int i = 0; i < limit; i++) {
            List<String> row = rows.get(i);
            boolean matched = true;
            for (String keyword : keywords) {
                boolean found = false;
                for (String cell : row) {
                    if (clean(cell).contains(keyword)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    matched = false;
                    break;
                }
            }
            if (matched) {
                return i;
            }
        }
        return -1;
    }

    /** 用表头行建立“列名 → 列下标”的映射，不按固定列号解析 */
    public static Map<String, Integer> headerIndex(List<String> headerRow) {
        Map<String, Integer> index = new LinkedHashMap<>();
        for (int i = 0; i < headerRow.size(); i++) {
            String name = clean(headerRow.get(i));
            if (!name.isEmpty()) {
                index.putIfAbsent(name, i);
            }
        }
        return index;
    }

    /** 取第一个存在的列下标 */
    public static Integer column(Map<String, Integer> index, String... names) {
        for (String name : names) {
            Integer column = index.get(name);
            if (column != null) {
                return column;
            }
        }
        return null;
    }

    public static String md5(String text) {
        try {
            MessageDigest digest = MessageDigest.getInstance("MD5");
            byte[] bytes = digest.digest(text.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(bytes.length * 2);
            for (byte b : bytes) {
                sb.append(Character.forDigit((b >> 4) & 0xF, 16));
                sb.append(Character.forDigit(b & 0xF, 16));
            }
            return sb.toString();
        } catch (Exception e) {
            throw new IllegalStateException("MD5 计算失败", e);
        }
    }
}
