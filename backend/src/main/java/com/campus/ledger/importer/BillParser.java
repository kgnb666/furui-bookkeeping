package com.campus.ledger.importer;

import com.campus.ledger.common.BillSource;

import java.util.List;

/**
 * 账单解析器：先确认是不是自己支持的账单格式，再把文件内容转成统一记录。
 */
public interface BillParser {

    BillSource source();

    /** 前 30 行里能否找到本平台个人账单的表头 */
    boolean supports(List<List<String>> rows);

    List<ParsedBill> parse(List<List<String>> rows);
}
