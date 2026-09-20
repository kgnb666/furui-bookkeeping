package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BillRules;
import com.campus.ledger.common.BizException;
import com.campus.ledger.common.Category;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.BudgetItemResponse;
import com.campus.ledger.dto.BudgetRequest;
import com.campus.ledger.dto.BudgetResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.entity.Budget;
import com.campus.ledger.mapper.BillMapper;
import com.campus.ledger.mapper.BudgetMapper;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 预算：月度总预算（category 为空串）与分类预算。
 * 已使用金额一律由后端按账单统计（只算 type=1 的支出），前端不自己算。
 */
@Service
public class BudgetService {

    private final BudgetMapper budgetMapper;
    private final BillMapper billMapper;

    public BudgetService(BudgetMapper budgetMapper, BillMapper billMapper) {
        this.budgetMapper = budgetMapper;
        this.billMapper = billMapper;
    }

    public BudgetResponse list(Long userId, String month) {
        YearMonth yearMonth = Months.parse(month);
        String monthText = yearMonth.toString();

        List<Budget> budgets = budgetMapper.selectList(new LambdaQueryWrapper<Budget>()
                .eq(Budget::getUserId, userId)
                .eq(Budget::getMonth, monthText)
                .orderByAsc(Budget::getCategory));

        BigDecimal monthExpense = monthExpense(userId, yearMonth);
        Map<String, BigDecimal> categoryExpense = categoryExpense(userId, yearMonth);

        BudgetItemResponse total = null;
        List<BudgetItemResponse> categories = new ArrayList<>();
        for (Budget budget : budgets) {
            BigDecimal used = budget.getCategory().isEmpty()
                    ? monthExpense
                    : categoryExpense.getOrDefault(budget.getCategory(), BigDecimal.ZERO);
            BudgetItemResponse item = BudgetItemResponse.of(budget, used);
            if (budget.getCategory().isEmpty()) {
                total = item;
            } else {
                categories.add(item);
            }
        }
        return new BudgetResponse(monthText, StatisticsService.money(monthExpense), total, categories);
    }

    public BudgetItemResponse create(Long userId, BudgetRequest request) {
        YearMonth yearMonth = Months.parse(request.getMonth());
        String category = normalizeCategory(request.getCategory());
        BigDecimal amount = validateAmount(request.getAmount());

        Long exists = budgetMapper.selectCount(new LambdaQueryWrapper<Budget>()
                .eq(Budget::getUserId, userId)
                .eq(Budget::getMonth, yearMonth.toString())
                .eq(Budget::getCategory, category));
        if (exists != null && exists > 0) {
            throw new BizException(409, category.isEmpty() ? "该月份的总预算已设置" : "该分类预算已设置");
        }

        Budget budget = new Budget();
        budget.setUserId(userId);
        budget.setMonth(yearMonth.toString());
        budget.setCategory(category);
        budget.setAmount(amount);
        try {
            budgetMapper.insert(budget);
        } catch (DuplicateKeyException e) {
            // 唯一约束兜底，避免同一用户同一月份同一分类出现两条预算
            throw new BizException(409, "该预算已存在");
        }
        return BudgetItemResponse.of(budgetMapper.selectById(budget.getId()), usedOf(userId, yearMonth, category));
    }

    /**
     * 修改预算：只允许改金额，月份与分类是这条预算的身份，不允许通过接口改。
     */
    public BudgetItemResponse update(Long userId, Long id, BudgetRequest request) {
        Budget budget = requireOwned(userId, id);
        budget.setAmount(validateAmount(request.getAmount()));
        budgetMapper.updateById(budget);
        Budget saved = budgetMapper.selectById(id);
        return BudgetItemResponse.of(saved, usedOf(userId, YearMonth.parse(saved.getMonth()), saved.getCategory()));
    }

    public void delete(Long userId, Long id) {
        requireOwned(userId, id);
        budgetMapper.delete(new LambdaQueryWrapper<Budget>()
                .eq(Budget::getId, id)
                .eq(Budget::getUserId, userId));
    }

    private Budget requireOwned(Long userId, Long id) {
        Budget budget = budgetMapper.selectOne(new LambdaQueryWrapper<Budget>()
                .eq(Budget::getId, id)
                .eq(Budget::getUserId, userId));
        if (budget == null) {
            throw new BizException(404, "预算不存在");
        }
        return budget;
    }

    private BigDecimal usedOf(Long userId, YearMonth month, String category) {
        if (category.isEmpty()) {
            return monthExpense(userId, month);
        }
        return categoryExpense(userId, month).getOrDefault(category, BigDecimal.ZERO);
    }

    private BigDecimal monthExpense(Long userId, YearMonth month) {
        for (TypeSum sum : billMapper.sumByType(userId, month.atDay(1), month.atEndOfMonth())) {
            if (sum.getType() != null && sum.getType() == BillType.EXPENSE.getCode()) {
                return StatisticsService.nullToZero(sum.getAmount());
            }
        }
        return BigDecimal.ZERO;
    }

    private Map<String, BigDecimal> categoryExpense(Long userId, YearMonth month) {
        Map<String, BigDecimal> result = new HashMap<>();
        for (CategorySum sum : billMapper.sumByCategory(userId, month.atDay(1), month.atEndOfMonth())) {
            result.put(sum.getCategory(), StatisticsService.nullToZero(sum.getAmount()));
        }
        return result;
    }

    /** 空串表示月度总预算；分类预算只能是合法的支出分类 */
    private String normalizeCategory(String category) {
        String value = category == null ? "" : category.trim();
        if (value.isEmpty()) {
            return "";
        }
        if (!Category.isValid(BillType.EXPENSE, value)) {
            throw new BizException(400, "分类预算只能是支出分类，可选："
                    + String.join("、", Category.of(BillType.EXPENSE)));
        }
        return value;
    }

    private BigDecimal validateAmount(BigDecimal amount) {
        return BillRules.checkAmount(amount, "预算金额");
    }
}
