package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.dto.PeriodSpendingItem;
import com.campus.ledger.dto.SpendingRhythmResponse;
import com.campus.ledger.dto.WeekdaySpendingItem;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 消费节奏与时间分布分析。
 *
 * 回答的问题是：**我的钱通常在什么时候花掉？**
 *
 * 与相邻模块的边界（维度互不重叠）：
 *   - Stage 4-A 预算预测看"本月会不会超预算"（预算维度）；
 *   - Stage 4-B 周期识别看"哪些支出会重复"（周期维度）；
 *   - Stage 4-C 消费异常看"哪里偏离常态"（异常维度）；
 *   - Stage 4-D 下月预估看"下个月大概花多少"（月度趋势维度）；
 *   - 本模块看"什么时候花得最多"（星期与月内阶段的时间分布维度）。
 *
 * 设计要点：
 *   1. 只分析目标月份本身（当月 1 日 ~ 当月月末），不读取任何历史月份；
 *   2. **一次**查询：复用 BillMapper#sumByDay（按天聚合），星期与月内阶段都在内存里归类；
 *   3. 只统计 type=1（支出），收入与不计收支不参与；
 *   4. 有支出的天数少于 3 天时不给结论，避免用一两天数据编造"消费习惯"；
 *   5. 不新增表、字段、索引与 Mapper 方法，结果实时计算不落库。
 */
@Service
public class SpendingRhythmService {

    /** 有支出记录的最少天数：少于 3 天不足以判断消费节奏 */
    static final int MIN_COVERED_DAYS = 3;

    /** 星期名称，索引 0 = 周一，与 DayOfWeek.getValue() - 1 对应 */
    static final String[] WEEKDAY_NAMES = {"周一", "周二", "周三", "周四", "周五", "周六", "周日"};

    /** 月内阶段的分界日：1-10 日 / 11-20 日 / 21 日-月底 */
    static final int PERIOD_BOUNDARY_FIRST = 10;
    static final int PERIOD_BOUNDARY_SECOND = 20;
    static final String PERIOD_NAME_FIRST = "1-10日";
    static final String PERIOD_NAME_SECOND = "11-20日";
    static final String PERIOD_NAME_THIRD = "21日-月底";

    static final String STATUS_OK = "OK";
    static final String STATUS_INSUFFICIENT_DATA = "INSUFFICIENT_DATA";
    static final String STATUS_NO_DATA = "NO_DATA";
    static final String STATUS_NOT_APPLICABLE = "NOT_APPLICABLE";

    private final BillMapper billMapper;
    private final Clock clock;

    public SpendingRhythmService(BillMapper billMapper, Clock clock) {
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public SpendingRhythmResponse analyze(Long userId, String month) {
        YearMonth target = Months.parse(month);
        int daysInMonth = target.lengthOfMonth();

        // 过去与未来月份都不做分析：与 Stage 4-A / 4-D 的 NOT_APPLICABLE 约定保持一致
        if (!target.equals(YearMonth.now(clock))) {
            return empty(target, STATUS_NOT_APPLICABLE,
                    "消费节奏分析只对当前月份有效", BigDecimal.ZERO, 0, daysInMonth);
        }

        // 一次查询：当月每天每个收支类型的合计（收入与不计收支在内存里排除）
        Map<LocalDate, BigDecimal> expenseByDay = loadExpenseByDay(userId, target);
        BigDecimal total = BigDecimal.ZERO;
        for (BigDecimal amount : expenseByDay.values()) {
            total = total.add(amount);
        }

        int coveredDays = expenseByDay.size();
        if (total.signum() == 0) {
            return empty(target, STATUS_NO_DATA,
                    "当月还没有支出记录", BigDecimal.ZERO, 0, daysInMonth);
        }
        if (coveredDays < MIN_COVERED_DAYS) {
            return empty(target, STATUS_INSUFFICIENT_DATA,
                    "当月只有 " + coveredDays + " 天有消费记录，还不足以判断消费节奏",
                    total, coveredDays, daysInMonth);
        }

        BigDecimal[] weekdayAmounts = new BigDecimal[WEEKDAY_NAMES.length];
        BigDecimal[] periodAmounts = new BigDecimal[3];
        for (int i = 0; i < weekdayAmounts.length; i++) {
            weekdayAmounts[i] = BigDecimal.ZERO;
        }
        for (int i = 0; i < periodAmounts.length; i++) {
            periodAmounts[i] = BigDecimal.ZERO;
        }

        for (Map.Entry<LocalDate, BigDecimal> entry : expenseByDay.entrySet()) {
            LocalDate date = entry.getKey();
            BigDecimal amount = entry.getValue();
            DayOfWeek dayOfWeek = date.getDayOfWeek();
            weekdayAmounts[dayOfWeek.getValue() - 1] = weekdayAmounts[dayOfWeek.getValue() - 1].add(amount);
            periodAmounts[periodIndex(date.getDayOfMonth())] = periodAmounts[periodIndex(date.getDayOfMonth())].add(amount);
        }

        List<WeekdaySpendingItem> weekdayItems = new ArrayList<>(WEEKDAY_NAMES.length);
        int peakWeekdayIndex = 0;
        for (int i = 0; i < weekdayAmounts.length; i++) {
            weekdayItems.add(new WeekdaySpendingItem(i + 1, WEEKDAY_NAMES[i],
                    money(weekdayAmounts[i]), percentage(weekdayAmounts[i], total)));
            if (weekdayAmounts[i].compareTo(weekdayAmounts[peakWeekdayIndex]) > 0) {
                peakWeekdayIndex = i;
            }
        }

        List<PeriodSpendingItem> periodItems = new ArrayList<>(3);
        int peakPeriodIndex = 0;
        for (int i = 0; i < periodAmounts.length; i++) {
            periodItems.add(new PeriodSpendingItem(periodName(i), startDay(i), endDay(i, daysInMonth),
                    money(periodAmounts[i]), percentage(periodAmounts[i], total)));
            if (periodAmounts[i].compareTo(periodAmounts[peakPeriodIndex]) > 0) {
                peakPeriodIndex = i;
            }
        }

        String peakWeekday = WEEKDAY_NAMES[peakWeekdayIndex];
        String peakPeriod = periodName(peakPeriodIndex);
        String concentration = percentage(weekdayAmounts[peakWeekdayIndex], total);
        String summary = "支出主要集中在" + peakWeekday + "（占 " + concentration
                + "%），月内以 " + peakPeriod + " 最多（占 "
                + percentage(periodAmounts[peakPeriodIndex], total) + "%）";

        return new SpendingRhythmResponse(target.toString(), STATUS_OK,
                "已分析 " + target + " 的消费节奏：当月共 " + coveredDays + " 天有消费记录",
                money(total), coveredDays, coveredRate(coveredDays, daysInMonth),
                peakWeekday, peakPeriod, concentration, summary, weekdayItems, periodItems);
    }

    /**
     * 一次查询取回当月每天的收支合计，再在内存里只保留支出。
     * 合计为 0 或负数的日期会被剔除，不计入"有消费记录的天数"。
     */
    private Map<LocalDate, BigDecimal> loadExpenseByDay(Long userId, YearMonth target) {
        List<DailySum> rows = billMapper.sumByDay(userId, target.atDay(1), target.atEndOfMonth());
        Map<LocalDate, BigDecimal> expenseByDay = new HashMap<>();
        for (DailySum row : rows) {
            if (row == null || row.getBillDate() == null || row.getType() == null) {
                continue;
            }
            if (row.getType() != BillType.EXPENSE.getCode()) {
                continue;
            }
            BigDecimal amount = row.getAmount() == null ? BigDecimal.ZERO : row.getAmount();
            if (amount.signum() <= 0) {
                continue;
            }
            expenseByDay.merge(row.getBillDate(), amount, BigDecimal::add);
        }
        return expenseByDay;
    }

    /** 月内阶段：1-10 日 → 0，11-20 日 → 1，21 日及以后 → 2 */
    static int periodIndex(int dayOfMonth) {
        if (dayOfMonth <= PERIOD_BOUNDARY_FIRST) {
            return 0;
        }
        if (dayOfMonth <= PERIOD_BOUNDARY_SECOND) {
            return 1;
        }
        return 2;
    }

    private static String periodName(int index) {
        return switch (index) {
            case 0 -> PERIOD_NAME_FIRST;
            case 1 -> PERIOD_NAME_SECOND;
            default -> PERIOD_NAME_THIRD;
        };
    }

    private static int startDay(int index) {
        return switch (index) {
            case 0 -> 1;
            case 1 -> PERIOD_BOUNDARY_FIRST + 1;
            default -> PERIOD_BOUNDARY_SECOND + 1;
        };
    }

    /** 第三段的结束日随当月天数变化（28 / 29 / 30 / 31 天都正确） */
    private static int endDay(int index, int daysInMonth) {
        return switch (index) {
            case 0 -> PERIOD_BOUNDARY_FIRST;
            case 1 -> PERIOD_BOUNDARY_SECOND;
            default -> daysInMonth;
        };
    }

    /** 非 OK 状态：只给状态、文案与已经有的事实（金额 / 天数），分布列表为空 */
    private SpendingRhythmResponse empty(YearMonth target, String status, String message,
                                         BigDecimal totalAmount, int coveredDays, int daysInMonth) {
        return new SpendingRhythmResponse(target.toString(), status, message, money(totalAmount),
                coveredDays, coveredRate(coveredDays, daysInMonth), "", "", "0.00", "",
                List.of(), List.of());
    }

    /** 记账覆盖率：有支出的天数 ÷ 当月天数 × 100 */
    static String coveredRate(int coveredDays, int daysInMonth) {
        if (daysInMonth <= 0) {
            return "0.00";
        }
        return BigDecimal.valueOf(coveredDays)
                .multiply(BigDecimal.valueOf(100))
                .divide(BigDecimal.valueOf(daysInMonth), 2, RoundingMode.HALF_UP)
                .toPlainString();
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
