package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.CategoryStatResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.DailySummaryResponse;
import com.campus.ledger.dto.DailyStatResponse;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.dto.MonthlyStatResponse;
import com.campus.ledger.dto.SourceStatResponse;
import com.campus.ledger.dto.SourceSum;
import com.campus.ledger.dto.TrendsResponse;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.common.BillSource;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 统计口径：只统计当前用户的收入(type=2)与支出(type=1)，
 * 不计收支(type=3)完全不参与统计。
 * 金额一律由 SQL 汇总成 BigDecimal，再格式化成字符串返回。
 */
@Service
public class StatisticsService {

    private final BillMapper billMapper;

    public StatisticsService(BillMapper billMapper) {
        this.billMapper = billMapper;
    }

    public MonthlyStatResponse monthly(Long userId, String month) {
        YearMonth yearMonth = Months.parse(month);
        LocalDate start = yearMonth.atDay(1);
        LocalDate end = yearMonth.atEndOfMonth();

        BigDecimal income = BigDecimal.ZERO;
        BigDecimal expense = BigDecimal.ZERO;
        for (TypeSum sum : billMapper.sumByType(userId, start, end)) {
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
        return new MonthlyStatResponse(yearMonth.toString(), money(income), money(expense),
                money(income.subtract(expense)));
    }

    public List<CategoryStatResponse> category(Long userId, String month) {
        YearMonth yearMonth = Months.parse(month);
        List<CategorySum> sums = billMapper.sumByCategory(userId,
                yearMonth.atDay(1), yearMonth.atEndOfMonth());

        BigDecimal total = BigDecimal.ZERO;
        for (CategorySum sum : sums) {
            total = total.add(nullToZero(sum.getAmount()));
        }

        List<CategoryStatResponse> result = new ArrayList<>(sums.size());
        for (CategorySum sum : sums) {
            BigDecimal amount = nullToZero(sum.getAmount());
            result.add(new CategoryStatResponse(sum.getCategory(), money(amount), percentage(amount, total)));
        }
        return result;
    }

    public List<DailyStatResponse> daily(Long userId, String month) {
        YearMonth yearMonth = Months.parse(month);
        List<DailySum> sums = billMapper.sumByDay(userId,
                yearMonth.atDay(1), yearMonth.atEndOfMonth());

        Map<LocalDate, BigDecimal[]> amountsByDate = new HashMap<>();
        for (DailySum sum : sums) {
            Integer type = sum.getType();
            if (sum.getBillDate() == null || type == null) {
                continue;
            }
            BigDecimal[] pair = amountsByDate.computeIfAbsent(sum.getBillDate(),
                    key -> new BigDecimal[]{BigDecimal.ZERO, BigDecimal.ZERO});
            if (type == BillType.INCOME.getCode()) {
                pair[0] = pair[0].add(nullToZero(sum.getAmount()));
            } else if (type == BillType.EXPENSE.getCode()) {
                pair[1] = pair[1].add(nullToZero(sum.getAmount()));
            }
        }

        // 整个月每天都返回，没有交易的日期记 0，前端趋势图才能连续
        List<DailyStatResponse> result = new ArrayList<>(yearMonth.lengthOfMonth());
        for (int day = 1; day <= yearMonth.lengthOfMonth(); day++) {
            LocalDate date = yearMonth.atDay(day);
            BigDecimal[] pair = amountsByDate.getOrDefault(date,
                    new BigDecimal[]{BigDecimal.ZERO, BigDecimal.ZERO});
            result.add(new DailyStatResponse(date.toString(), money(pair[0]), money(pair[1])));
        }
        return result;
    }

    /**
     * 支付来源统计：只算支出（type=1），不计收支与收入都不参与。
     */
    public List<SourceStatResponse> source(Long userId, String month) {
        YearMonth yearMonth = Months.parse(month);
        List<SourceSum> sums = billMapper.sumBySource(userId,
                yearMonth.atDay(1), yearMonth.atEndOfMonth());

        BigDecimal total = BigDecimal.ZERO;
        for (SourceSum sum : sums) {
            total = total.add(nullToZero(sum.getAmount()));
        }

        List<SourceStatResponse> result = new ArrayList<>(sums.size());
        for (SourceSum sum : sums) {
            BigDecimal amount = nullToZero(sum.getAmount());
            result.add(new SourceStatResponse(sum.getSource(), sourceName(sum.getSource()),
                    money(amount), percentage(amount, total)));
        }
        return result;
    }

    /**
     * 指定日期的收支合计，首页「今日收入 / 今日支出」使用。
     * 不传日期时按服务器当天计算，同样只统计 type=1 与 type=2。
     */
    public DailySummaryResponse dailySummary(Long userId, LocalDate date) {
        LocalDate target = date == null ? LocalDate.now() : date;
        BigDecimal income = BigDecimal.ZERO;
        BigDecimal expense = BigDecimal.ZERO;
        for (TypeSum sum : billMapper.sumByType(userId, target, target)) {
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
        return new DailySummaryResponse(target.toString(), money(income), money(expense));
    }

    /**
     * 消费趋势：本月与上月的支出对比。
     * 上月没有任何账单时 previousHasData 为 false，变化率返回 null，前端显示"暂无对比数据"。
     */
    public TrendsResponse trends(Long userId, String month) {
        YearMonth current = Months.parse(month);
        YearMonth previous = current.minusMonths(1);

        BigDecimal currentIncome = BigDecimal.ZERO;
        BigDecimal currentExpense = BigDecimal.ZERO;
        for (TypeSum sum : billMapper.sumByType(userId, current.atDay(1), current.atEndOfMonth())) {
            Integer type = sum.getType();
            if (type == null) {
                continue;
            }
            if (type == BillType.INCOME.getCode()) {
                currentIncome = currentIncome.add(nullToZero(sum.getAmount()));
            } else if (type == BillType.EXPENSE.getCode()) {
                currentExpense = currentExpense.add(nullToZero(sum.getAmount()));
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

        return new TrendsResponse(current.toString(), money(currentExpense), money(currentIncome),
                previous.toString(), money(previousExpense), previousHasData,
                changePercent(currentExpense, previousExpense, previousHasData));
    }

    /** 支出变化率：上月没有账单或上月支出为 0 时无法比较，返回 null */
    private static String changePercent(BigDecimal current, BigDecimal previous, boolean previousHasData) {
        if (!previousHasData || previous == null || previous.signum() == 0) {
            return null;
        }
        BigDecimal rate = current.subtract(previous)
                .multiply(BigDecimal.valueOf(100))
                .divide(previous, 2, RoundingMode.HALF_UP);
        return rate.toPlainString();
    }

    /** 来源的中文名，未知来源直接显示原始值，避免页面上出现空字符串 */
    private String sourceName(String source) {
        BillSource billSource = BillSource.parse(source);
        return billSource == null ? (source == null ? "" : source) : billSource.getLabel();
    }

    static BigDecimal nullToZero(BigDecimal value) {
        return value == null ? BigDecimal.ZERO : value;
    }

    static String money(BigDecimal value) {
        return nullToZero(value).setScale(2, RoundingMode.HALF_UP).toPlainString();
    }

    /** 占比，保留两位小数；总金额为 0 时直接返回 0，避免除零 */
    static BigDecimal percentage(BigDecimal part, BigDecimal total) {
        if (total == null || total.signum() == 0) {
            return BigDecimal.ZERO.setScale(2);
        }
        return part.multiply(BigDecimal.valueOf(100)).divide(total, 2, RoundingMode.HALF_UP);
    }
}
