package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BillRules;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.common.Category;
import com.campus.ledger.dto.ImportBatchResponse;
import com.campus.ledger.dto.ImportConfirmItem;
import com.campus.ledger.dto.ImportConfirmRequest;
import com.campus.ledger.dto.ImportPreviewItem;
import com.campus.ledger.dto.ImportPreviewResponse;
import com.campus.ledger.dto.ImportResultResponse;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.entity.ImportBatch;
import com.campus.ledger.importer.AlipayBillParser;
import com.campus.ledger.importer.BillFields;
import com.campus.ledger.importer.BillFileReader;
import com.campus.ledger.importer.BillParser;
import com.campus.ledger.importer.ParsedBill;
import com.campus.ledger.importer.WechatBillParser;
import com.campus.ledger.mapper.BillMapper;
import com.campus.ledger.mapper.ImportBatchMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 账单导入：预览只解析不写库，用户确认后才写入 bill 表并记录 import_batch。
 * 去重键一律由服务端计算，不使用客户端传来的任何去重信息。
 */
@Service
public class BillImportService {

    private static final int QUERY_BATCH_SIZE = 500;

    private final BillMapper billMapper;
    private final ImportBatchMapper importBatchMapper;
    private final WechatBillParser wechatBillParser;
    private final AlipayBillParser alipayBillParser;
    private final CategoryMatcher categoryMatcher;

    @Value("${ledger.import.max-records:2000}")
    private int maxRecords = 2000;

    public BillImportService(BillMapper billMapper,
                             ImportBatchMapper importBatchMapper,
                             WechatBillParser wechatBillParser,
                             AlipayBillParser alipayBillParser,
                             CategoryMatcher categoryMatcher) {
        this.billMapper = billMapper;
        this.importBatchMapper = importBatchMapper;
        this.wechatBillParser = wechatBillParser;
        this.alipayBillParser = alipayBillParser;
        this.categoryMatcher = categoryMatcher;
    }

    public ImportPreviewResponse preview(Long userId, MultipartFile file, String source) {
        BillSource billSource = parseImportSource(source);
        if (file == null || file.isEmpty()) {
            throw new BizException(400, "请选择要导入的账单文件");
        }
        String fileName = sanitizeFileName(file.getOriginalFilename());

        byte[] bytes;
        try {
            bytes = file.getBytes();
        } catch (IOException e) {
            throw new BizException(400, "账单文件读取失败，请重新上传");
        }

        List<List<String>> rows = BillFileReader.read(bytes, fileName);
        boolean blankContent = rows.stream()
                .allMatch(row -> row.stream().allMatch(cell -> BillFields.clean(cell).isEmpty()));
        if (blankContent) {
            throw new BizException(400, "账单文件内容为空，请确认导出的是个人对账账单文件");
        }
        BillParser parser = parserOf(billSource);
        if (!parser.supports(rows)) {
            BillParser other = otherParser(billSource);
            if (other.supports(rows)) {
                throw new BizException(400, "该文件是" + other.source().getLabel() + "账单，请把导入来源改为"
                        + other.source().getLabel() + "后重新导入");
            }
            throw new BizException(400, "暂不支持该账单格式，请导入微信/支付宝个人对账账单文件");
        }

        List<ParsedBill> parsed = parser.parse(rows);
        if (parsed.isEmpty()) {
            throw new BizException(400, "没有解析到任何交易记录，请确认账单文件内容");
        }
        if (parsed.size() > maxRecords) {
            throw new BizException(400, "账单记录数超过 " + maxRecords + " 条，请按月分批导入");
        }

        Map<ParsedBill, String> dedupKeys = buildDedupKeys(billSource, parsed);
        Set<String> existingKeys = loadExistingKeys(userId, dedupKeys.values());
        Set<String> seenKeys = new HashSet<>();

        List<ImportPreviewItem> items = new ArrayList<>(parsed.size());
        int newCount = 0;
        int duplicateCount = 0;
        int neutralCount = 0;
        int failedCount = 0;

        for (ParsedBill bill : parsed) {
            ImportPreviewItem item = new ImportPreviewItem();
            item.setRowIndex(bill.getRowIndex());
            item.setSourceTradeTime(bill.getSourceTradeTime());
            item.setMerchant(bill.getMerchant());
            item.setRemark(bill.getRemark());
            item.setBillDate(bill.getBillDate() == null ? "" : bill.getBillDate().toString());
            item.setAmount(bill.getAmount() == null ? "" : bill.getAmount().toPlainString());
            item.setSourceTradeId(bill.getSourceTradeId());
            if (bill.getType() != null) {
                item.setType(bill.getType().getCode());
                item.setTypeName(bill.getType().getLabel());
            }

            if (bill.isParseFailed()) {
                failedCount++;
                item.setImportable(false);
                item.setFailReason(bill.getFailReason());
                items.add(item);
                continue;
            }

            // 预览阶段就用与确认导入一致的规则检查一遍，
            // 避免预览显示“可导入”、点确认时才失败
            String invalid = checkImportable(bill);
            if (invalid != null) {
                failedCount++;
                item.setImportable(false);
                item.setFailReason(invalid);
                items.add(item);
                continue;
            }

            String key = dedupKeys.get(bill);
            if (key != null) {
                if (existingKeys.contains(key)) {
                    duplicateCount++;
                    item.setDuplicate(true);
                    item.setDuplicateReason("与已有记录重复");
                } else if (!seenKeys.add(key)) {
                    duplicateCount++;
                    item.setDuplicate(true);
                    item.setDuplicateReason("文件内重复");
                }
            }

            CategoryMatcher.Matched matched = categoryMatcher.match(
                    bill.getType(), bill.getMerchant(), bill.getRemark(), bill.getCategoryHint());
            item.setCategory(matched.category());
            item.setCategoryFrom(matched.from());

            item.setImportable(true);
            boolean neutral = bill.getType() == BillType.NEUTRAL;
            if (neutral) {
                neutralCount++;
            }
            // 重复记录与不计收支记录默认不勾选
            boolean selected = !item.isDuplicate() && !neutral;
            item.setDefaultSelected(selected);
            if (selected) {
                newCount++;
            }
            items.add(item);
        }

        ImportPreviewResponse response = new ImportPreviewResponse();
        response.setSource(billSource.name());
        response.setSourceName(billSource.getLabel());
        response.setFileName(fileName);
        response.setTotalCount(parsed.size());
        response.setNewCount(newCount);
        response.setDuplicateCount(duplicateCount);
        response.setNeutralCount(neutralCount);
        response.setFailedCount(failedCount);
        response.setItems(items);
        return response;
    }

    @Transactional
    public ImportResultResponse confirm(Long userId, ImportConfirmRequest request) {
        BillSource source = parseImportSource(request.getSource());
        if (request.getItems() == null || request.getItems().isEmpty()) {
            throw new BizException(400, "没有需要导入的记录");
        }

        ImportBatch batch = new ImportBatch();
        batch.setUserId(userId);
        batch.setSource(source.name());
        batch.setFileName(sanitizeFileName(request.getFileName()));
        batch.setTotalCount(request.getTotalCount() == null ? request.getItems().size() : request.getTotalCount());
        batch.setImportedCount(0);
        batch.setDuplicateCount(0);
        batch.setFailedCount(0);
        importBatchMapper.insert(batch);

        int importedCount = 0;
        int duplicateCount = 0;
        int failedCount = 0;
        List<ImportResultResponse.FailItem> failures = new ArrayList<>();

        for (int i = 0; i < request.getItems().size(); i++) {
            ImportConfirmItem item = request.getItems().get(i);
            Bill bill;
            try {
                bill = toBill(userId, source, batch.getId(), item);
            } catch (BizException e) {
                failedCount++;
                failures.add(new ImportResultResponse.FailItem(i + 1, safe(item.getMerchant()), e.getMessage()));
                continue;
            }
            try {
                billMapper.insert(bill);
                importedCount++;
            } catch (DuplicateKeyException e) {
                // 数据库唯一约束兜底：并发提交或重复确认时不会产生重复数据
                duplicateCount++;
            }
        }

        batch.setImportedCount(importedCount);
        batch.setDuplicateCount(duplicateCount);
        batch.setFailedCount(failedCount);
        importBatchMapper.updateById(batch);

        ImportResultResponse response = new ImportResultResponse();
        response.setBatchId(batch.getId());
        response.setTotalCount(batch.getTotalCount());
        response.setImportedCount(importedCount);
        response.setDuplicateCount(duplicateCount);
        response.setFailedCount(failedCount);
        response.setFailures(failures);
        return response;
    }

    public List<ImportBatchResponse> batches(Long userId) {
        List<ImportBatch> list = importBatchMapper.selectList(new LambdaQueryWrapper<ImportBatch>()
                .eq(ImportBatch::getUserId, userId)
                .orderByDesc(ImportBatch::getId)
                .last("LIMIT 50"));
        return list.stream().map(ImportBatchResponse::from).toList();
    }

    /** 服务端二次校验，并把用户确认后的数据转成账单实体 */
    private Bill toBill(Long userId, BillSource source, Long batchId, ImportConfirmItem item) {
        BillType type = BillType.parse(item.getType());
        if (type == null) {
            throw new BizException(400, "收支类型不合法");
        }
        String category = item.getCategory() == null ? "" : item.getCategory().trim();
        if (!Category.isValid(type, category)) {
            throw new BizException(400, "分类不合法：" + category);
        }
        // 与手工记账共用 BillRules 的金额与日期规则
        BigDecimal amount = BillRules.checkAmount(item.getAmount());
        LocalDate billDate = BillRules.checkBillDate(item.getBillDate());
        String merchant = item.getMerchant() == null ? "" : item.getMerchant().trim();
        String remark = item.getRemark() == null ? "" : item.getRemark().trim();
        if (merchant.length() > 64) {
            throw new BizException(400, "交易对象长度不能超过 64 位");
        }
        if (remark.length() > 255) {
            throw new BizException(400, "备注长度不能超过 255 位");
        }

        Bill bill = new Bill();
        bill.setUserId(userId);
        bill.setType(type.getCode());
        bill.setAmount(amount);
        bill.setCategory(category);
        bill.setBillDate(billDate);
        bill.setMerchant(merchant);
        bill.setRemark(remark);
        bill.setSource(source.name());
        bill.setSourceTradeId(emptyToNull(item.getSourceTradeId()));
        bill.setDedupKey(buildDedupKey(source, item.getSourceTradeId(), item.getSourceTradeTime(),
                amount, merchant, type));
        bill.setImportBatchId(batchId);
        return bill;
    }

    /**
     * 与 toBill() 保持一致的校验规则，供预览阶段使用。
     * 返回 null 表示这条记录可以导入。
     */
    private String checkImportable(ParsedBill bill) {
        String dateError = BillRules.billDateError(bill.getBillDate());
        if (dateError != null) {
            return dateError;
        }
        String amountError = BillRules.amountError(bill.getAmount(), "金额");
        if (amountError != null) {
            return amountError;
        }
        if (bill.getMerchant().length() > 64) {
            return "交易对象长度不能超过 64 位";
        }
        if (bill.getRemark().length() > 255) {
            return "备注长度不能超过 255 位";
        }
        return null;
    }

    private Map<ParsedBill, String> buildDedupKeys(BillSource source, List<ParsedBill> parsed) {
        Map<ParsedBill, String> keys = new LinkedHashMap<>();
        for (ParsedBill bill : parsed) {
            if (!bill.isParseFailed()) {
                keys.put(bill, buildDedupKey(source, bill.getSourceTradeId(), bill.getSourceTradeTime(),
                        bill.getAmount(), bill.getMerchant(), bill.getType()));
            }
        }
        return keys;
    }

    /**
     * 首选“来源 + 原始交易号”；没有交易号时用
     * “来源 + 交易时间 + 金额 + 交易对象 + 收支类型”的 MD5 指纹。
     */
    static String buildDedupKey(BillSource source, String sourceTradeId, String sourceTradeTime,
                                BigDecimal amount, String merchant, BillType type) {
        // 账单里没有交易号时可能是 "/" 或 "-"，统一按没有交易号处理
        String tradeId = BillFields.cleanOptional(sourceTradeId);
        if (!tradeId.isEmpty()) {
            // 交易号过长时先做一次 MD5，保证不会超出 dedup_key 字段长度
            String value = tradeId.length() > 60 ? BillFields.md5(tradeId) : tradeId;
            return source.name() + ":" + value;
        }
        String fingerprint = String.join("|",
                BillFields.clean(sourceTradeTime),
                amount == null ? "" : amount.setScale(2, RoundingMode.HALF_UP).toPlainString(),
                BillFields.clean(merchant),
                type == null ? "" : String.valueOf(type.getCode()));
        return source.name() + ":" + BillFields.md5(fingerprint);
    }

    private Set<String> loadExistingKeys(Long userId, Iterable<String> keys) {
        List<String> all = new ArrayList<>();
        for (String key : keys) {
            if (key != null) {
                all.add(key);
            }
        }
        Set<String> existing = new HashSet<>();
        for (int i = 0; i < all.size(); i += QUERY_BATCH_SIZE) {
            List<String> chunk = all.subList(i, Math.min(i + QUERY_BATCH_SIZE, all.size()));
            existing.addAll(billMapper.selectExistingDedupKeys(userId, chunk));
        }
        return existing;
    }

    private BillSource parseImportSource(String source) {
        BillSource billSource = BillSource.parse(source);
        if (billSource == null || billSource == BillSource.MANUAL) {
            throw new BizException(400, "账单来源只能是 WECHAT 或 ALIPAY");
        }
        return billSource;
    }

    private BillParser parserOf(BillSource source) {
        return source == BillSource.WECHAT ? wechatBillParser : alipayBillParser;
    }

    private BillParser otherParser(BillSource source) {
        return source == BillSource.WECHAT ? alipayBillParser : wechatBillParser;
    }

    /** 只保留文件名本身，避免路径拼接 */
    static String sanitizeFileName(String fileName) {
        if (fileName == null || fileName.isBlank()) {
            return "未命名账单";
        }
        String name = fileName.replace("\\", "/");
        int slash = name.lastIndexOf('/');
        if (slash >= 0) {
            name = name.substring(slash + 1);
        }
        name = name.trim();
        if (name.isEmpty()) {
            return "未命名账单";
        }
        return name.length() > 128 ? name.substring(0, 128) : name;
    }

    private String emptyToNull(String value) {
        String text = BillFields.clean(value);
        return text.isEmpty() ? null : text;
    }

    private String safe(String value) {
        return value == null ? "" : value;
    }
}
