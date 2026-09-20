package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.BudgetItemResponse;
import com.campus.ledger.dto.BudgetResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.Insight;
import com.campus.ledger.dto.MonthlyInsightsResponse;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * 消费洞察：全部基于已有统计数据与简单阈值规则，不使用任何大模型。
 *
 * 每条洞察都必须可解释：说出触发条件、涉及金额与分类，用户可以自行复核。
 * 所有查询都以当前登录用户为条件，不读取他人数据。
 */
@Service
public class InsightsService {

    /** 最多返回的洞察条数，避免首页/统计页堆满文字 */
    static final int MAX_INSIGHTS = 5;

    /** 某分类占总支出超过该比例时提示"支出集中" */
    static final BigDecimal CATEGORY_FOCUS_PERCENT = new BigDecimal("30");

    /** 分类环比增长超过该比例时提示"明显增加" */
    static final BigDecimal CATEGORY_GROWTH_PERCENT = new BigDecimal("20");

    /** 预算使用率达到该比例时提醒 */
    static final BigDecimal BUDGET_WARNING_PERCENT = new BigDecimal("80");

    private final BillMapper billMapper;
    private final BudgetService budgetService;

    public InsightsService(BillMapper billMapper, BudgetService budgetService) {
        this.billMapper = billMapper;
        this.budgetService = budgetService;
    }

    public MonthlyInsightsResponse monthly(Long userId, String month) {
        YearMonth current = Months.parse(month);
        YearMonth previous = current.minusMonths(1);

        BigDecimal income = BigDecimal.ZERO;
        BigDecimal expense = BigDecimal.ZERO;
        for (TypeSum sum : billMapper.sumByType(userId, current.atDay(1), current.atEndOfMonth())) {
            Integer type = sum.getType();
            if (type == null) {
                continue;
            }
            if (type == BillType.INCOME.getCode()) {
                income = income.add(nullToZero(sum.getAmount()));
            } else if (type == BillType.EXPENSE.getCode()) {
                expense = expense.add(nullToZero(sum.getAmount()));
            }
        }

        BigDecimal previousExpense = BigDecimal.ZERO;
        boolean previousHasData = false;
        for (TypeSum sum : billMapper.sumByType(userId, previous.atDay(1), previous.atEndOfMonth())) {
            previousHasData = true;
            Integer type = sum.getType();
            if (type != null && type == BillType.EXPENSE.getCode()) {
                previousExpense = previousExpense.add(nullToZero(sum.getAmount()));
            }
        }

        List<CategorySum> currentCategories = billMapper.sumByCategory(userId,
                current.atDay(1), current.atEndOfMonth());
        List<CategorySum> previousCategories = billMapper.sumByCategory(userId,
                previous.atDay(1), previous.atEndOfMonth());

        String changePercent = changePercent(expense, previousExpense, previousHasData);
        String topCategory = null;
        String topCategoryPercent = null;
        if (!currentCategories.isEmpty() && expense.signum() > 0) {
            CategorySum top = currentCategories.get(0);
            topCategory = top.getCategory();
            topCategoryPercent = percentage(nullToZero(top.getAmount()), expense);
        }

        List<Insight> insights = new ArrayList<>();
        addBudgetInsights(userId, current, insights);
        addCategoryGrowthInsights(currentCategories, previousCategories, previousHasData, insights);
        addSpendingChangeInsight(expense, previousExpense, previousHasData, changePercent, insights);
        addCategoryFocusInsight(topCategory, topCategoryPercent, insights);

        List<Insight> top = insights.stream()
                .sorted(Comparator.comparingInt(Insight::getPriority))
                .limit(MAX_INSIGHTS)
                .toList();

        return new MonthlyInsightsResponse(current.toString(), money(expense), money(income),
                money(income.subtract(expense)), changePercent, topCategory, topCategoryPercent,
                summary(expense, changePercent, topCategory), top);
    }

    /** 规则 6/7：预算达到 80% 提醒，超过 100% 告警 */
    private void addBudgetInsights(Long userId, YearMonth month, List<Insight> insights) {
        BudgetResponse budget = budgetService.list(userId, month.toString());
        List<BudgetItemResponse> items = new ArrayList<>();
        if (budget.getTotal() != null) {
            items.add(budget.getTotal());
        }
        items.addAll(budget.getCategories());

        for (BudgetItemResponse item : items) {
            BigDecimal rate = item.getUsageRate();
            if (rate == null) {
                continue;
            }
            String name = item.getCategoryName();
            if (rate.compareTo(BigDecimal.valueOf(100)) >= 0) {
                insights.add(new Insight("BUDGET_OVER", 1, "WARNING", "预算提醒",
                        name + " 已超过本月预算（已使用 " + trimRate(rate) + "%）", item.getAmount()));
            } else if (rate.compareTo(BUDGET_WARNING_PERCENT) >= 0) {
                insights.add(new Insight("BUDGET_WARNING", 1, "WARNING", "预算提醒",
                        name + " 预算已使用 " + trimRate(rate) + "%，请注意剩余预算", item.getAmount()));
            }
        }
    }

    /** 规则 4：某分类环比增长超过 20% */
    private void addCategoryGrowthInsights(List<CategorySum> current, List<CategorySum> previous,
                                           boolean previousHasData, List<Insight> insights) {
        if (!previousHasData) {
            return;
        }
        for (CategorySum now : current) {
            BigDecimal currentAmount = nullToZero(now.getAmount());
            BigDecimal previousAmount = previous.stream()
                    .filter(sum -> sum.getCategory().equals(now.getCategory()))
                    .map(sum -> nullToZero(sum.getAmount()))
                    .findFirst()
                    .orElse(BigDecimal.ZERO);
            if (previousAmount.signum() == 0) {
                continue;
            }
            BigDecimal rate = currentAmount.subtract(previousAmount)
                    .multiply(BigDecimal.valueOf(100))
                    .divide(previousAmount, 2, RoundingMode.HALF_UP);
            if (rate.compareTo(CATEGORY_GROWTH_PERCENT) > 0) {
                insights.add(new Insight("CATEGORY_GROWTH", 3, "INFO", "分类变化",
                        now.getCategory() + " 支出较上月明显增加（+" + trimRate(rate) + "%）",
                        money(currentAmount)));
            }
        }
    }

    /** 规则 1/2：本月支出与上月对比 */
    private void addSpendingChangeInsight(BigDecimal expense, BigDecimal previousExpense,
                                          boolean previousHasData, String changePercent,
                                          List<Insight> insights) {
        if (!previousHasData || changePercent == null) {
            return;
        }
        BigDecimal diff = expense.subtract(previousExpense).abs();
        BigDecimal rate = new BigDecimal(changePercent);
        if (rate.signum() > 0) {
            insights.add(new Insight("SPENDING_CHANGE", 4, "INFO", "消费变化",
                    "本月支出比上月增加 " + money(diff) + " 元（+" + trimRate(rate) + "%）",
                    money(expense)));
        } else if (rate.signum() < 0) {
            insights.add(new Insight("SPENDING_CHANGE", 4, "INFO", "消费变化",
                    "本月支出比上月减少 " + money(diff) + " 元（" + trimRate(rate) + "%）",
                    money(expense)));
        }
    }

    /** 规则 3：某分类占总支出超过 30% */
    private void addCategoryFocusInsight(String topCategory, String percent, List<Insight> insights) {
        if (topCategory == null || percent == null) {
            return;
        }
        BigDecimal value = new BigDecimal(percent);
        if (value.compareTo(CATEGORY_FOCUS_PERCENT) >= 0) {
            insights.add(new Insight("CATEGORY_FOCUS", 5, "INFO", "消费重点",
                    "本月支出主要集中在 " + topCategory + "，占总支出的 " + trimRate(value) + "%",
                    percent));
        }
    }

    /** 首页用的一句话摘要 */
    private String summary(BigDecimal expense, String changePercent, String topCategory) {
        if (expense.signum() == 0) {
            return "本月还没有支出记录";
        }
        StringBuilder builder = new StringBuilder("本月支出 ¥").append(money(expense));
        if (changePercent != null) {
            BigDecimal rate = new BigDecimal(changePercent);
            if (rate.signum() > 0) {
                builder.append("，比上月 ↑").append(trimRate(rate)).append("%");
            } else if (rate.signum() < 0) {
                builder.append("，比上月 ↓").append(trimRate(rate.abs())).append("%");
            } else {
                builder.append("，与上月持平");
            }
        }
        if (topCategory != null) {
            builder.append("，").append(topCategory).append("是主要支出类别");
        }
        return builder.append("。").toString();
    }

    private static String changePercent(BigDecimal current, BigDecimal previous, boolean previousHasData) {
        if (!previousHasData || previous.signum() == 0) {
            return null;
        }
        return current.subtract(previous)
                .multiply(BigDecimal.valueOf(100))
                .divide(previous, 2, RoundingMode.HALF_UP)
                .toPlainString();
    }

    private static String percentage(BigDecimal part, BigDecimal total) {
        if (total.signum() == 0) {
            return "0.00";
        }
        return part.multiply(BigDecimal.valueOf(100)).divide(total, 2, RoundingMode.HALF_UP).toPlainString();
    }

    /** 去掉无意义的小数零：80.00 -> 80，86.50 保持 86.50 */
    private static String trimRate(BigDecimal value) {
        BigDecimal stripped = value.stripTrailingZeros();
        return stripped.scale() < 0 ? stripped.setScale(0).toPlainString() : stripped.toPlainString();
    }

    private static BigDecimal nullToZero(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value;
    }

    private static String money(BigDecimal value) {
        return nullToZero(value).setScale(2, RoundingMode.HALF_UP).toPlainString();
    }
}
