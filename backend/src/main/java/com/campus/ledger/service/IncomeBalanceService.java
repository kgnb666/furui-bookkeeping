package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.IncomeBalanceResponse;
import com.campus.ledger.dto.IncomeCategoryItem;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.List;

/**
 * 收支结余分析（我这个月存下了多少）。
 *
 * 补上系统里唯一完全空白的维度：此前 Stage 4-A ~ 4-F 六个智能能力全部只看支出
 * （预算风险、周期、异常、下月总量、时间分布、消费对象），没有任何能力回答"收入够不够花"。
 *
 * 设计要点：
 *   1. 只分析目标月份本身（当月 1 日 ~ 月末），与 Stage 4-E / 4-F 口径一致；
 *   2. 复用既有 Mapper 方法，不新增任何查询方法：
 *        - sumByType            本月收入 / 支出合计（一次查询同时拿到两个数）
 *        - sumByCategoryAndMonth 本月收入结构（传 type=收入）
 *        - sumByType            上月收入 / 支出合计（用于与上月对比）
 *   3. 没有收入记录时**不编造结余率**，返回 NO_INCOME_DATA 并如实给出支出事实
 *      （真实数据里绝大多数用户只记支出，这个状态是常态而不是异常）；
 *   4. 不新增表、字段、索引与依赖，结果实时计算不落库。
 */
@Service
public class IncomeBalanceService {

    /** 收入结构最多返回的分类数 */
    static final int MAX_INCOME_ITEMS = 5;

    static final String STATUS_OK = "OK";
    static final String STATUS_NO_INCOME_DATA = "NO_INCOME_DATA";
    static final String STATUS_NO_DATA = "NO_DATA";
    static final String STATUS_NOT_APPLICABLE = "NOT_APPLICABLE";

    /** DATE_FORMAT 的月份模式，作为参数传入避免 SQL 里出现 % 与 MyBatis 占位符混淆 */
    static final String MONTH_PATTERN = "%Y-%m";

    private final BillMapper billMapper;
    private final Clock clock;

    public IncomeBalanceService(BillMapper billMapper, Clock clock) {
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public IncomeBalanceResponse analyze(Long userId, String month) {
        YearMonth target = Months.parse(month);

        // 过去与未来月份都不做分析：与 4-A / 4-D / 4-E / 4-F 保持一致
        if (!target.equals(YearMonth.now(clock))) {
            return respond(target, STATUS_NOT_APPLICABLE, "收支结余分析只对当前月份有效",
                    BigDecimal.ZERO, BigDecimal.ZERO, "0.00", 0, List.of(),
                    BigDecimal.ZERO, null, false, "");
        }

        // 查询 1：本月收入 / 支出合计
        BigDecimal income = BigDecimal.ZERO;
        BigDecimal expense = BigDecimal.ZERO;
        for (TypeSum sum : billMapper.sumByType(userId, target.atDay(1), target.atEndOfMonth())) {
            if (sum == null || sum.getType() == null) {
                continue;
            }
            BigDecimal amount = sum.getAmount() == null ? BigDecimal.ZERO : sum.getAmount();
            if (sum.getType() == BillType.INCOME.getCode()) {
                income = income.add(amount);
            } else if (sum.getType() == BillType.EXPENSE.getCode()) {
                expense = expense.add(amount);
            }
        }

        if (income.signum() == 0 && expense.signum() == 0) {
            return respond(target, STATUS_NO_DATA, "当月还没有任何收支记录",
                    BigDecimal.ZERO, BigDecimal.ZERO, "0.00", 0, List.of(),
                    BigDecimal.ZERO, null, false, "");
        }

        BigDecimal balance = income.subtract(expense);
        List<CategoryMonthlySum> incomeRows = billMapper.sumByCategoryAndMonth(userId,
                BillType.INCOME.getCode(), target.atDay(1), target.atEndOfMonth(), MONTH_PATTERN);
        List<IncomeCategoryItem> incomeItems = new ArrayList<>(MAX_INCOME_ITEMS);
        int incomeCount = 0;
        for (CategoryMonthlySum row : incomeRows) {
            if (row == null || row.getCategory() == null) {
                continue;
            }
            incomeCount += row.getCount() == null ? 0 : row.getCount();
        }

        if (income.signum() == 0) {
            // 有支出但没有收入记录：不计算结余率，只返回事实
            return respond(target, STATUS_NO_INCOME_DATA,
                    "当月没有收入记录，无法计算结余率（补记收入后即可分析）",
                    income, expense, "0.00", 0, List.of(), BigDecimal.ZERO, null, false, "");
        }

        final BigDecimal incomeTotal = income;
        incomeRows.stream()
                .filter(row -> row != null && row.getCategory() != null)
                .sorted((left, right) -> amountOf(right).compareTo(amountOf(left)))
                .limit(MAX_INCOME_ITEMS)
                .forEach(row -> incomeItems.add(new IncomeCategoryItem(row.getCategory(),
                        money(amountOf(row)), row.getCount() == null ? 0 : row.getCount(),
                        percentage(amountOf(row), incomeTotal))));

        // 查询 2：上月收支（用于"比上月多存/少存"的对比）
        YearMonth previous = target.minusMonths(1);
        BigDecimal previousIncome = BigDecimal.ZERO;
        BigDecimal previousExpense = BigDecimal.ZERO;
        boolean hasPreviousData = false;
        List<TypeSum> previousSums = billMapper.sumByType(userId,
                previous.atDay(1), previous.atEndOfMonth());
        for (TypeSum sum : previousSums) {
            hasPreviousData = true;
            if (sum == null || sum.getType() == null) {
                continue;
            }
            BigDecimal amount = sum.getAmount() == null ? BigDecimal.ZERO : sum.getAmount();
            if (sum.getType() == BillType.INCOME.getCode()) {
                previousIncome = previousIncome.add(amount);
            } else if (sum.getType() == BillType.EXPENSE.getCode()) {
                previousExpense = previousExpense.add(amount);
            }
        }
        BigDecimal previousBalance = previousIncome.subtract(previousExpense);
        String balanceChange = hasPreviousData
                ? money(balance.subtract(previousBalance))
                : null;

        String rate = percentage(balance, income);
        String summary = summary(income, expense, balance, rate, hasPreviousData, balanceChange);

        return respond(target, STATUS_OK,
                "已分析 " + target + " 的收支结余：收入 " + money(income)
                        + "，支出 " + money(expense),
                income, expense, rate, incomeCount, incomeItems,
                previousBalance, balanceChange, hasPreviousData, summary);
    }

    /** 一句话结论：结余或超支 + 结余率 + 与上月的对比（如果有） */
    private static String summary(BigDecimal income, BigDecimal expense, BigDecimal balance,
                                  String rate, boolean hasPreviousData, String balanceChange) {
        StringBuilder summary = new StringBuilder();
        if (balance.signum() >= 0) {
            summary.append("本月结余 ¥").append(money(balance))
                    .append("（结余率 ").append(rate).append("%）");
        } else {
            summary.append("本月支出超过收入 ¥").append(money(balance.abs()))
                    .append("（结余率 ").append(rate).append("%）");
        }
        if (hasPreviousData && balanceChange != null) {
            BigDecimal change = new BigDecimal(balanceChange);
            if (change.signum() > 0) {
                summary.append("，比上月多存 ¥").append(money(change));
            } else if (change.signum() < 0) {
                summary.append("，比上月少存 ¥").append(money(change.abs()));
            } else {
                summary.append("，与上月持平");
            }
        }
        return summary.toString();
    }

    private IncomeBalanceResponse respond(YearMonth target, String status, String message,
                                          BigDecimal income, BigDecimal expense, String balanceRate,
                                          int incomeCount, List<IncomeCategoryItem> incomeItems,
                                          BigDecimal previousBalance, String balanceChange,
                                          boolean hasPreviousData, String summary) {
        BigDecimal balance = income.subtract(expense);
        return new IncomeBalanceResponse(target.toString(), status, message, money(income),
                money(expense), money(balance), balanceRate, incomeCount, incomeItems,
                money(previousBalance), balanceChange, hasPreviousData, summary);
    }

    private static BigDecimal amountOf(CategoryMonthlySum sum) {
        return sum == null || sum.getAmount() == null ? BigDecimal.ZERO : sum.getAmount();
    }

    /** 占比：part ÷ total × 100，保留两位小数；total 为 0 时返回 0.00 */
    static String percentage(BigDecimal part, BigDecimal total) {
        if (total == null || total.signum() == 0) {
            return "0.00";
        }
        return part.multiply(BigDecimal.valueOf(100))
                .divide(total, 2, RoundingMode.HALF_UP)
                .toPlainString();
    }

    private static String money(BigDecimal value) {
        return StatisticsService.money(value);
    }
}
