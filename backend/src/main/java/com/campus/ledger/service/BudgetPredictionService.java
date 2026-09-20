package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.BudgetPredictionItem;
import com.campus.ledger.dto.BudgetPredictionResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.CategoryDailySum;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.entity.Budget;
import com.campus.ledger.mapper.BillMapper;
import com.campus.ledger.mapper.BudgetMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 预算预测：按"本月已过天数 + 本月已支出金额"推算月末支出，判断是否可能超支。
 *
 * 设计要点（都是为了让结论可解释、可复核）：
 *   1. 只用当前登录用户自己的账单与预算，所有查询带 user_id；
 *   2. 日均口径固定为「本月支出 ÷ 本月已过天数」，用户能自己心算验证；
 *   3. 当月有支出的天数少于 {@link #MIN_SPENT_DAYS} 天时不给预测结论，
 *      避免月初一两笔消费被放大成虚假的超支预警；
 *   4. 只预测当前月份，过去与未来月份返回 NOT_APPLICABLE；
 *   5. 不新增表、不新增字段，全部基于已有的 bill / budget 数据。
 */
@Service
public class BudgetPredictionService {

    /** 低于该天数不生成预测结论，避免月初样本太少导致预测虚高 */
    static final int MIN_SPENT_DAYS = 3;

    static final BigDecimal SAFE_LINE = new BigDecimal("60");
    static final BigDecimal LOW_LINE = new BigDecimal("85");
    static final BigDecimal MEDIUM_LINE = new BigDecimal("100");
    static final BigDecimal HIGH_LINE = new BigDecimal("120");

    private final BudgetMapper budgetMapper;
    private final BillMapper billMapper;
    private final Clock clock;

    public BudgetPredictionService(BudgetMapper budgetMapper, BillMapper billMapper, Clock clock) {
        this.budgetMapper = budgetMapper;
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public BudgetPredictionResponse predict(Long userId, String month) {
        YearMonth target = Months.parse(month);
        YearMonth current = YearMonth.now(clock);
        int daysInMonth = target.lengthOfMonth();

        if (!target.equals(current)) {
            return BudgetPredictionResponse.notApplicable(target.toString(), daysInMonth);
        }

        LocalDate today = LocalDate.now(clock);
        int elapsedDays = Math.min(today.getDayOfMonth(), daysInMonth);
        int daysLeft = daysInMonth - elapsedDays;

        List<Budget> budgets = budgetMapper.selectList(new LambdaQueryWrapper<Budget>()
                .eq(Budget::getUserId, userId)
                .eq(Budget::getMonth, target.toString())
                .orderByAsc(Budget::getCategory));

        if (budgets.isEmpty()) {
            return BudgetPredictionResponse.noBudget(target.toString(), elapsedDays, daysInMonth, daysLeft);
        }

        // 一次按天聚合，既能拿到"有支出的天数"，也能拿到本月总支出
        Map<LocalDate, BigDecimal> dailyExpense = dailyExpense(userId, target);
        int monthSpentDays = dailyExpense.size();
        BigDecimal monthSpent = BigDecimal.ZERO;
        for (BigDecimal amount : dailyExpense.values()) {
            monthSpent = monthSpent.add(amount);
        }
        Map<String, BigDecimal> categoryExpense = categoryExpense(userId, target);
        Map<String, Integer> categorySpentDays = categorySpentDays(userId, target);

        List<BudgetPredictionItem> items = new ArrayList<>();
        boolean anyPredicted = false;
        for (Budget budget : budgets) {
            boolean isTotal = budget.getCategory().isEmpty();
            BigDecimal spent = isTotal
                    ? monthSpent
                    : categoryExpense.getOrDefault(budget.getCategory(), BigDecimal.ZERO);
            // 每个预算用各自的消费样本判断：某分类本月一次都没消费时，
            // 不该因为别的分类花过钱就给出这个分类的预测。
            int spentDays = isTotal
                    ? monthSpentDays
                    : categorySpentDays.getOrDefault(budget.getCategory(), 0);
            if (spentDays < MIN_SPENT_DAYS) {
                // 样本不足：只给事实（已花多少 / 预算多少），不给预测结论
                items.add(insufficientItem(budget, spent, spentDays, elapsedDays, daysLeft));
                continue;
            }
            anyPredicted = true;
            items.add(predictItem(budget, spent, spentDays, elapsedDays, daysLeft, daysInMonth, target));
        }

        String status = anyPredicted ? "OK" : "INSUFFICIENT_DATA";
        String message = anyPredicted
                ? summaryMessage(items, daysLeft)
                : "本月消费记录还不足 " + MIN_SPENT_DAYS + " 天，暂时无法预测月末支出";
        return new BudgetPredictionResponse(target.toString(), status, message,
                elapsedDays, daysInMonth, daysLeft, items);
    }

    /** 有预算但消费天数不足：不预测 */
    private BudgetPredictionItem insufficientItem(Budget budget, BigDecimal spent, int spentDays,
                                                  int elapsedDays, int daysLeft) {
        boolean isTotal = budget.getCategory().isEmpty();
        return new BudgetPredictionItem(budget.getId(), budget.getCategory(),
                categoryName(budget), isTotal, money(budget.getAmount()), money(spent),
                spentDays, elapsedDays, money(BigDecimal.ZERO), money(BigDecimal.ZERO),
                money(BigDecimal.ZERO), "0.00", null, daysLeft, "INSUFFICIENT_DATA",
                "已使用 " + money(spent) + " / 预算 " + money(budget.getAmount()));
    }

    /**
     * 正常预测：日均 = 已支出 ÷ 已过天数；月末预测 = 日均 × 当月天数。
     */
    private BudgetPredictionItem predictItem(Budget budget, BigDecimal spent, int spentDays,
                                             int elapsedDays, int daysLeft, int daysInMonth,
                                             YearMonth target) {
        BigDecimal dailyAverage = spent.divide(BigDecimal.valueOf(elapsedDays), 2, RoundingMode.HALF_UP);
        BigDecimal projected = dailyAverage.multiply(BigDecimal.valueOf(daysInMonth))
                .setScale(2, RoundingMode.HALF_UP);
        BigDecimal budgetAmount = budget.getAmount();
        BigDecimal over = projected.subtract(budgetAmount).max(BigDecimal.ZERO).setScale(2, RoundingMode.HALF_UP);
        BigDecimal usageRate = budgetAmount.signum() == 0
                ? BigDecimal.ZERO.setScale(2)
                : projected.multiply(BigDecimal.valueOf(100))
                        .divide(budgetAmount, 2, RoundingMode.HALF_UP);
        String risk = riskLevel(usageRate);

        return new BudgetPredictionItem(budget.getId(), budget.getCategory(), categoryName(budget),
                budget.getCategory().isEmpty(), money(budgetAmount), money(spent), spentDays, elapsedDays,
                money(dailyAverage), money(projected), money(over), usageRate.toPlainString(),
                overDate(dailyAverage, budgetAmount, target, daysInMonth), daysLeft, risk,
                buildMessage(spent, elapsedDays, dailyAverage, projected, budgetAmount, over, usageRate));
    }

    /**
     * 预测说明，把每一步算式都说清楚，用户能自己复核。
     */
    private String buildMessage(BigDecimal spent, int elapsedDays, BigDecimal dailyAverage,
                                BigDecimal projected, BigDecimal budgetAmount, BigDecimal over,
                                BigDecimal usageRate) {
        StringBuilder builder = new StringBuilder();
        builder.append("本月已过 ").append(elapsedDays).append(" 天，已支出 ¥").append(money(spent))
                .append("，日均 ¥").append(money(dailyAverage))
                .append("；按此推算月末约支出 ¥").append(money(projected))
                .append("，为预算的 ").append(trim(usageRate)).append("%");
        if (over.signum() > 0) {
            builder.append("，预计超出预算 ¥").append(money(over));
        } else {
            builder.append("，预计不会超出预算");
        }
        return builder.toString();
    }

    /**
     * 风险等级按"预测使用率"分级，而不是当前已用比例——
     * 月初花掉一半不代表一定超支，预测值才是有效信号。
     */
    private String riskLevel(BigDecimal usageRate) {
        if (usageRate.compareTo(SAFE_LINE) < 0) {
            return "SAFE";
        }
        if (usageRate.compareTo(LOW_LINE) < 0) {
            return "LOW";
        }
        if (usageRate.compareTo(MEDIUM_LINE) < 0) {
            return "MEDIUM";
        }
        if (usageRate.compareTo(HIGH_LINE) < 0) {
            return "HIGH";
        }
        return "OVER";
    }

    /**
     * 预计达到预算上限的日期：预算 ÷ 日均 向上取整。
     * 超出当月范围（即不会在月内触顶）时返回 null。
     */
    private String overDate(BigDecimal dailyAverage, BigDecimal budgetAmount,
                            YearMonth target, int daysInMonth) {
        if (dailyAverage.signum() <= 0) {
            return null;
        }
        int day = budgetAmount.divide(dailyAverage, 0, RoundingMode.CEILING).intValue();
        if (day < 1 || day > daysInMonth) {
            return null;
        }
        return target.atDay(day).toString();
    }

    /**
     * 顶部一句话：优先说最严重的那个预算，避免用户要自己逐条找重点。
     */
    private String summaryMessage(List<BudgetPredictionItem> items, int daysLeft) {
        BudgetPredictionItem worst = null;
        for (BudgetPredictionItem item : items) {
            if ("INSUFFICIENT_DATA".equals(item.getRiskLevel())) {
                continue;
            }
            if (worst == null || rank(item.getRiskLevel()) > rank(worst.getRiskLevel())) {
                worst = item;
            }
        }
        if (worst == null) {
            return "本月消费记录还不足 " + MIN_SPENT_DAYS + " 天，暂时无法预测月末支出";
        }
        String name = worst.isTotal() ? "本月总预算" : worst.getCategoryName();
        if (worst.getProjectedOver().equals("0.00")) {
            return name + "预计不会超支，本月还剩 " + daysLeft + " 天";
        }
        String date = worst.getOverDate() == null ? "" : "，预计 " + worst.getOverDate() + " 达到上限";
        return name + "预计超出 ¥" + worst.getProjectedOver() + date;
    }

    private static int rank(String riskLevel) {
        return switch (riskLevel) {
            case "OVER" -> 5;
            case "HIGH" -> 4;
            case "MEDIUM" -> 3;
            case "LOW" -> 2;
            default -> 1;
        };
    }

    /** 当月每天的支出合计（只算 type=1，不计收支不参与） */
    private Map<LocalDate, BigDecimal> dailyExpense(Long userId, YearMonth month) {
        Map<LocalDate, BigDecimal> result = new HashMap<>();
        for (DailySum sum : billMapper.sumByDay(userId, month.atDay(1), month.atEndOfMonth())) {
            if (sum.getBillDate() == null || sum.getType() == null
                    || sum.getType() != BillType.EXPENSE.getCode()) {
                continue;
            }
            BigDecimal amount = StatisticsService.nullToZero(sum.getAmount());
            if (amount.signum() <= 0) {
                continue;
            }
            result.merge(sum.getBillDate(), amount, BigDecimal::add);
        }
        return result;
    }

    private Map<String, BigDecimal> categoryExpense(Long userId, YearMonth month) {
        Map<String, BigDecimal> result = new HashMap<>();
        for (CategorySum sum : billMapper.sumByCategory(userId, month.atDay(1), month.atEndOfMonth())) {
            result.put(sum.getCategory(), StatisticsService.nullToZero(sum.getAmount()));
        }
        return result;
    }

    /**
     * 每个分类当月"有支出的天数"。一次查询覆盖全部分类，
     * 用于判断某个分类预算有没有足够样本做预测。
     */
    private Map<String, Integer> categorySpentDays(Long userId, YearMonth month) {
        Map<String, Integer> result = new HashMap<>();
        for (CategoryDailySum sum : billMapper.sumByDayAndCategory(
                userId, month.atDay(1), month.atEndOfMonth())) {
            if (sum.getCategory() == null || sum.getBillDate() == null) {
                continue;
            }
            result.merge(sum.getCategory(), 1, Integer::sum);
        }
        return result;
    }

    private static String categoryName(Budget budget) {
        return budget.getCategory().isEmpty() ? "月度总预算" : budget.getCategory();
    }

    private static String money(BigDecimal value) {
        return StatisticsService.money(value);
    }

    /** 去掉无意义的小数零：80.00 → 80 */
    private static String trim(BigDecimal value) {
        BigDecimal stripped = value.stripTrailingZeros();
        return stripped.scale() < 0 ? stripped.setScale(0).toPlainString() : stripped.toPlainString();
    }
}
