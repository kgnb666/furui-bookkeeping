package com.campus.ledger.importer;

import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BillType;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 微信支付“用于个人对账”账单解析器。
 * 文件为 UTF-8，正文前有说明信息，业务表头在中间位置，因此按表头列名映射取值。
 */
@Component
public class WechatBillParser implements BillParser {

    private static final String KEY_TIME = "交易时间";
    private static final String KEY_DIRECTION = "收/支";
    private static final String KEY_AMOUNT = "金额(元)";
    private static final String KEY_TRADE_ID = "交易单号";

    @Override
    public BillSource source() {
        return BillSource.WECHAT;
    }

    @Override
    public boolean supports(List<List<String>> rows) {
        return BillFields.findHeaderRow(rows, KEY_TIME, "金额", KEY_DIRECTION, KEY_TRADE_ID) >= 0;
    }

    @Override
    public List<ParsedBill> parse(List<List<String>> rows) {
        int headerRow = BillFields.findHeaderRow(rows, KEY_TIME, "金额", KEY_DIRECTION, KEY_TRADE_ID);
        Map<String, Integer> index = BillFields.headerIndex(rows.get(headerRow));

        Integer timeColumn = BillFields.column(index, KEY_TIME);
        Integer directionColumn = BillFields.column(index, KEY_DIRECTION);
        Integer amountColumn = BillFields.column(index, KEY_AMOUNT, "金额");
        Integer merchantColumn = BillFields.column(index, "交易对方");
        Integer productColumn = BillFields.column(index, "商品");
        Integer remarkColumn = BillFields.column(index, "备注");
        Integer tradeIdColumn = BillFields.column(index, KEY_TRADE_ID);
        Integer tradeTypeColumn = BillFields.column(index, "交易类型");

        List<ParsedBill> bills = new ArrayList<>();
        for (int i = headerRow + 1; i < rows.size(); i++) {
            List<String> row = rows.get(i);
            String rawTime = BillFields.cell(row, timeColumn);
            // 说明行、结尾的“共X笔记录”等不是交易数据，直接跳过
            if (!BillFields.looksLikeDate(rawTime)) {
                continue;
            }

            ParsedBill bill = new ParsedBill();
            bill.setRowIndex(i + 1);
            bill.setSourceTradeTime(BillFields.clean(rawTime));

            LocalDate billDate = BillFields.parseDate(rawTime);
            if (billDate == null) {
                bill.fail("交易时间无法识别: " + BillFields.clean(rawTime));
                bills.add(bill);
                continue;
            }
            bill.setBillDate(billDate);

            String rawAmount = BillFields.cell(row, amountColumn);
            BigDecimal amount = BillFields.parseAmount(rawAmount);
            if (amount == null) {
                bill.fail("金额无法识别: " + BillFields.clean(rawAmount));
                bills.add(bill);
                continue;
            }
            if (amount.signum() <= 0) {
                bill.fail("金额必须大于 0: " + BillFields.clean(rawAmount));
                bills.add(bill);
                continue;
            }
            bill.setAmount(amount);

            String tradeType = BillFields.clean(BillFields.cell(row, tradeTypeColumn));
            String product = BillFields.cleanOptional(BillFields.cell(row, productColumn));
            bill.setType(BillFields.resolveType(BillFields.cell(row, directionColumn), tradeType, product));
            bill.setMerchant(BillFields.cleanOptional(BillFields.cell(row, merchantColumn)));
            bill.setRemark(joinRemark(product, BillFields.cleanOptional(BillFields.cell(row, remarkColumn))));
            bill.setSourceTradeId(BillFields.cleanOptional(BillFields.cell(row, tradeIdColumn)));
            bills.add(bill);
        }
        return bills;
    }

    private String joinRemark(String product, String remark) {
        if (product.isEmpty()) {
            return remark;
        }
        if (remark.isEmpty()) {
            return product;
        }
        return product + " " + remark;
    }
}
