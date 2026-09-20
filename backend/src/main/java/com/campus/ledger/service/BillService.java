package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BillRules;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.common.Category;
import com.campus.ledger.dto.BillRequest;
import com.campus.ledger.dto.BillResponse;
import com.campus.ledger.dto.PageResult;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;

/**
 * 账单增删改查。所有查询都带当前登录用户的 user_id，保证数据隔离。
 */
@Service
public class BillService {

    private final BillMapper billMapper;

    public BillService(BillMapper billMapper) {
        this.billMapper = billMapper;
    }

    public BillResponse create(Long userId, BillRequest request) {
        Bill bill = new Bill();
        bill.setUserId(userId);
        // 手动记账：来源固定 MANUAL，去重键为空，因此不会被判定为重复
        bill.setSource(BillSource.MANUAL.name());
        validateAndFill(bill, request);
        billMapper.insert(bill);
        return BillResponse.from(billMapper.selectById(bill.getId()));
    }

    public PageResult<BillResponse> page(Long userId, String month, String type, String category,
                                         String source, String keyword, BigDecimal minAmount,
                                         BigDecimal maxAmount, int page, int size) {
        BillType billType = null;
        if (StringUtils.hasText(type)) {
            billType = BillType.parse(type);
            if (billType == null) {
                throw new BizException(400, "收支类型只能是 1(支出)/2(收入)/3(不计收支)");
            }
        }
        BillSource billSource = null;
        if (StringUtils.hasText(source)) {
            billSource = BillSource.parse(source);
            if (billSource == null) {
                throw new BizException(400, "来源只能是 MANUAL/WECHAT/ALIPAY");
            }
        }
        LocalDate start = null;
        LocalDate end = null;
        BigDecimal min = checkAmountParam(minAmount, "最小金额");
        BigDecimal max = checkAmountParam(maxAmount, "最大金额");
        if (min != null && max != null && min.compareTo(max) > 0) {
            throw new BizException(400, "最小金额不能大于最大金额");
        }
        if (StringUtils.hasText(month)) {
            YearMonth yearMonth;
            try {
                yearMonth = YearMonth.parse(month.trim());
            } catch (DateTimeParseException e) {
                throw new BizException(400, "月份格式应为 yyyy-MM");
            }
            start = yearMonth.atDay(1);
            end = yearMonth.atEndOfMonth();
        }

        LambdaQueryWrapper<Bill> wrapper = new LambdaQueryWrapper<Bill>()
                .eq(Bill::getUserId, userId)
                .eq(billType != null, Bill::getType, billType == null ? null : billType.getCode())
                .eq(StringUtils.hasText(category), Bill::getCategory, category)
                .eq(billSource != null, Bill::getSource, billSource == null ? null : billSource.name())
                .ge(start != null, Bill::getBillDate, start)
                .le(end != null, Bill::getBillDate, end);
        if (StringUtils.hasText(keyword)) {
            String text = keyword.trim();
            wrapper.and(w -> w.like(Bill::getMerchant, text).or().like(Bill::getRemark, text));
        }
        // 金额区间：只填一个边界时按单边过滤，两个都给才构成区间
        wrapper.ge(min != null, Bill::getAmount, min)
                .le(max != null, Bill::getAmount, max);
        wrapper.orderByDesc(Bill::getBillDate).orderByDesc(Bill::getId);

        int current = Math.max(page, 1);
        int pageSize = Math.min(Math.max(size, 1), 100);
        Page<Bill> result = billMapper.selectPage(new Page<>(current, pageSize), wrapper);
        return PageResult.of(result, BillResponse::from);
    }

    public BillResponse detail(Long userId, Long id) {
        return BillResponse.from(requireOwned(userId, id));
    }

    public BillResponse update(Long userId, Long id, BillRequest request) {
        Bill bill = requireOwned(userId, id);
        validateAndFill(bill, request);
        billMapper.updateById(bill);
        return BillResponse.from(billMapper.selectById(id));
    }

    public void delete(Long userId, Long id) {
        requireOwned(userId, id);
        billMapper.delete(new LambdaQueryWrapper<Bill>()
                .eq(Bill::getId, id)
                .eq(Bill::getUserId, userId));
    }

    /** 查不到或不属于当前用户都返回 404，不泄露“该 id 是否存在” */
    private Bill requireOwned(Long userId, Long id) {
        Bill bill = billMapper.selectOne(new LambdaQueryWrapper<Bill>()
                .eq(Bill::getId, id)
                .eq(Bill::getUserId, userId));
        if (bill == null) {
            throw new BizException(404, "账单不存在");
        }
        return bill;
    }

    /** 金额筛选条件的校验：必须为非负数，最多两位小数 */
    private BigDecimal checkAmountParam(BigDecimal amount, String label) {
        if (amount == null) {
            return null;
        }
        if (amount.signum() < 0) {
            throw new BizException(400, label + "不能为负数");
        }
        if (amount.scale() > 2) {
            throw new BizException(400, label + "最多两位小数");
        }
        return amount;
    }

    /**
     * 校验请求参数并写入账单字段。
     * source / source_trade_id / dedup_key / import_batch_id 不支持通过接口修改。
     */
    private void validateAndFill(Bill bill, BillRequest request) {
        BillType type = BillType.parse(request.getType());
        if (type == null) {
            throw new BizException(400, "收支类型只能是 1(支出)/2(收入)/3(不计收支)");
        }
        String category = request.getCategory() == null ? "" : request.getCategory().trim();
        if (!Category.isValid(type, category)) {
            throw new BizException(400, "分类不合法，可选：" + String.join("、", Category.of(type)));
        }

        // 金额与日期规则统一放在 BillRules，手工记账与导入确认共用同一套判断
        BigDecimal amount = BillRules.checkAmount(request.getAmount());
        LocalDate billDate = BillRules.checkBillDate(request.getBillDate());

        bill.setType(type.getCode());
        bill.setAmount(amount);
        bill.setCategory(category);
        bill.setBillDate(billDate);
        bill.setMerchant(request.getMerchant() == null ? "" : request.getMerchant().trim());
        bill.setRemark(request.getRemark() == null ? "" : request.getRemark().trim());
    }
}
