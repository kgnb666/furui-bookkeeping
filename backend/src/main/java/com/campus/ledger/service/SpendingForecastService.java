package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.ForecastSampleMonth;
import com.campus.ledger.dto.SpendingForecastResponse;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 下月支出预估。
 *
 * 回答的问题：**照我过去的消费节奏，下个月大概会花多少？**
 *
 * 与相邻模块的边界（都不重复劳动）：
 *   - Stage 4-A 预算预测看"本月会不会超预算"，依赖预算，且只外推当前月；
 *   - Stage 4-C 消费异常看"本月哪里偏离常态"，看的是分类与单笔；
 *   - 本模块看"下一个完整月的总量"，不依赖预算，也不需要任何明细。
 *
 * 设计要点：
 *   1. 只用当前登录用户自己的账单，查询固定带 user_id；
 *   2. **一次**聚合查询（复用 4-C 已引入的 sumByCategoryAndMonth），
 *      在内存里按月份合并，不存在按月份或按分类的循环查询（无 N+1）；
 *   3. 只使用"有支出的完整自然月"：当前月不参与，空月份不按 0 计入；
 *   4. 权重 3 : 2 : 1（最近月权重最高），异常月（高于中位数 2 倍）权重降为 1 并封顶置信度；
 *   5. 不足 3 个有效历史月份时不给结论，避免把噪声当预测；
 *   6. 不新增表、字段、索引，也不新增 Mapper 方法。
 */
@Service
public class SpendingForecastService {

    /** 读取的历史窗口：参考月之前的 6 个完整自然月（加上参考月本身，一次查询覆盖 7 个自然月） */
    static final int HISTORY_WINDOW_MONTHS = 6;

    /** 参与加权的历史月份数量：最近 3 个「有支出的完整自然月」 */
    static final int SAMPLE_MONTHS = 3;

    /** 最少需要的历史月份数：少于 3 个月不足以判断趋势，不给预测 */
    static final int MIN_SAMPLE_MONTHS = 3;

    /** 权重：最近月 3、次近月 2、第三近月 1 */
    static final int[] WEIGHTS = {3, 2, 1};

    /** 异常月判定：该月支出高于历史中位数的 2 倍 */
    static final BigDecimal OUTLIER_MULTIPLIER = new BigDecimal("2");

    /** 异常月的权重降到 1（保留样本，但不让它主导结果） */
    static final int OUTLIER_WEIGHT = 1;

    /** 置信度阈值：样本极差比 ≤ 0.30 视为稳定，> 0.60 只能"仅供参考" */
    static final BigDecimal HIGH_SPREAD = new BigDecimal("0.30");
    static final BigDecimal MEDIUM_SPREAD = new BigDecimal("0.60");

    static final String STATUS_OK = "OK";
    static final String STATUS_INSUFFICIENT_DATA = "INSUFFICIENT_DATA";
    static final String STATUS_NO_DATA = "NO_DATA";
    static final String STATUS_NOT_APPLICABLE = "NOT_APPLICABLE";

    static final String CONFIDENCE_HIGH = "HIGH";
    static final String CONFIDENCE_MEDIUM = "MEDIUM";
    static final String CONFIDENCE_LOW = "LOW";
    static final String CONFIDENCE_NONE = "NONE";

    /** DATE_FORMAT 的月份模式，作为参数传入避免 SQL 里出现 % 与 MyBatis 占位符混淆 */
    static final String MONTH_PATTERN = "%Y-%m";

    private final BillMapper billMapper;
    private final Clock clock;

    public SpendingForecastService(BillMapper billMapper, Clock clock) {
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public SpendingForecastResponse forecast(Long userId, String month) {
        YearMonth reference = Months.parse(month);
        YearMonth current = YearMonth.now(clock);
        YearMonth target = reference.plusMonths(1);
        int elapsedDays = LocalDate.now(clock).getDayOfMonth();

        // 过去与未来月份都不做预估：与 Stage 4-A 的 NOT_APPLICABLE 约定保持一致
        if (!reference.equals(current)) {
            return empty(reference, target, STATUS_NOT_APPLICABLE,
                    "下月支出预估仅支持当前月份", elapsedDays, BigDecimal.ZERO);
        }

        Map<String, BigDecimal> expenseByMonth = loadMonthlyExpense(userId, current);
        BigDecimal currentMonthAmount = expenseByMonth.getOrDefault(current.toString(), BigDecimal.ZERO);

        if (expenseByMonth.isEmpty()) {
            return empty(reference, target, STATUS_NO_DATA,
                    "还没有支出记录，暂时无法预估下月支出", elapsedDays, currentMonthAmount);
        }

        // 最近 3 个"有支出的完整自然月"：当前月不参与，空月份直接跳过（不按 0 计入）
        List<MonthSample> samples = recentSamples(expenseByMonth, current);
        if (samples.size() < MIN_SAMPLE_MONTHS) {
            return empty(reference, target, STATUS_INSUFFICIENT_DATA,
                    "有支出的完整月份还不够 " + MIN_SAMPLE_MONTHS + " 个月，暂时无法预估下月支出",
                    elapsedDays, currentMonthAmount);
        }

        return predict(reference, target, samples, currentMonthAmount, elapsedDays);
    }

    /**
     * 一次聚合查询 → 按月份合并。
     *
     * 复用 Stage 4-C 引入的「分类 + 月份」聚合：它的取数范围与分组正好覆盖本需求，
     * 因此不需要新增 Mapper 方法。合计为 0 的月份在这里被剔除
     * （有记录但没花钱的月份不应该把预估拉低）。
     */
    private Map<String, BigDecimal> loadMonthlyExpense(Long userId, YearMonth current) {
        YearMonth first = current.minusMonths(HISTORY_WINDOW_MONTHS);
        List<CategoryMonthlySum> rows = billMapper.sumByCategoryAndMonth(userId,
                BillType.EXPENSE.getCode(), first.atDay(1), LocalDate.now(clock), MONTH_PATTERN);

        Map<String, BigDecimal> expenseByMonth = new HashMap<>();
        for (CategoryMonthlySum row : rows) {
            if (row == null || row.getMonth() == null) {
                continue;
            }
            BigDecimal amount = row.getAmount() == null ? BigDecimal.ZERO : row.getAmount();
            expenseByMonth.merge(row.getMonth(), amount, BigDecimal::add);
        }
        expenseByMonth.values().removeIf(amount -> amount.signum() <= 0);
        return expenseByMonth;
    }

    /** 按时间倒序取最近 3 个有支出的完整自然月 */
    private List<MonthSample> recentSamples(Map<String, BigDecimal> expenseByMonth, YearMonth current) {
        List<MonthSample> samples = new ArrayList<>(SAMPLE_MONTHS);
        for (int i = 1; i <= HISTORY_WINDOW_MONTHS && samples.size() < SAMPLE_MONTHS; i++) {
            String month = current.minusMonths(i).toString();
            BigDecimal amount = expenseByMonth.get(month);
            if (amount != null) {
                samples.add(new MonthSample(month, amount));
            }
        }
        return samples;
    }

    private SpendingForecastResponse predict(YearMonth reference, YearMonth target,
                                             List<MonthSample> samples, BigDecimal currentMonthAmount,
                                             int elapsedDays) {
        List<BigDecimal> amounts = new ArrayList<>(samples.size());
        for (MonthSample sample : samples) {
            amounts.add(sample.amount());
        }
        BigDecimal median = median(amounts);

        // 权重：正常情况下 3 : 2 : 1；高于中位数 2 倍的月份降为 1
        int[] weights = new int[samples.size()];
        String outlierMonth = null;
        BigDecimal weightedSum = BigDecimal.ZERO;
        int weightTotal = 0;
        for (int i = 0; i < samples.size(); i++) {
            BigDecimal amount = samples.get(i).amount();
            int weight = WEIGHTS[i];
            if (amount.compareTo(median.multiply(OUTLIER_MULTIPLIER)) > 0) {
                weight = OUTLIER_WEIGHT;
                outlierMonth = samples.get(i).month();
            }
            weights[i] = weight;
            weightedSum = weightedSum.add(amount.multiply(BigDecimal.valueOf(weight)));
            weightTotal += weight;
        }

        BigDecimal predicted = weightedSum.divide(BigDecimal.valueOf(weightTotal), 2, RoundingMode.HALF_UP);
        BigDecimal previous = samples.get(0).amount();
        BigDecimal difference = predicted.subtract(previous).setScale(2, RoundingMode.HALF_UP);
        String changePercent = changePercent(difference, previous);

        String confidence = confidence(amounts, predicted, outlierMonth != null);
        List<ForecastSampleMonth> sampleMonths = new ArrayList<>(samples.size());
        for (int i = 0; i < samples.size(); i++) {
            sampleMonths.add(new ForecastSampleMonth(samples.get(i).month(),
                    money(samples.get(i).amount()), weights[i]));
        }

        return new SpendingForecastResponse(reference.toString(), target.toString(), STATUS_OK,
                okMessage(target, samples.get(0).month(), predicted, difference, changePercent),
                confidence, confidenceLabel(confidence),
                confidenceReason(samples, amounts, predicted, outlierMonth),
                money(predicted), money(previous), money(difference), changePercent,
                money(currentMonthAmount), elapsedDays, sampleMonths);
    }

    /**
     * 置信度只看客观条件：样本极差比（最高月与最低月的差距 ÷ 预估金额）。
     * 正常情况下 3 个样本的权重是 3 : 2 : 1，某个样本被降权说明当月偏离常态，
     * 此时无论极差比多小，都不给 HIGH。
     */
    static String confidence(List<BigDecimal> amounts, BigDecimal predicted, boolean hasOutlier) {
        BigDecimal max = Collections.max(amounts);
        BigDecimal min = Collections.min(amounts);
        BigDecimal spread = max.subtract(min)
                .divide(predicted, 4, RoundingMode.HALF_UP);

        String level;
        if (spread.compareTo(HIGH_SPREAD) <= 0) {
            level = CONFIDENCE_HIGH;
        } else if (spread.compareTo(MEDIUM_SPREAD) <= 0) {
            level = CONFIDENCE_MEDIUM;
        } else {
            level = CONFIDENCE_LOW;
        }
        if (hasOutlier && CONFIDENCE_HIGH.equals(level)) {
            level = CONFIDENCE_MEDIUM;
        }
        return level;
    }

    private static String confidenceLabel(String confidence) {
        return switch (confidence) {
            case CONFIDENCE_HIGH -> "高可信";
            case CONFIDENCE_MEDIUM -> "中等可信";
            case CONFIDENCE_LOW -> "仅供参考";
            default -> "";
        };
    }

    /** 置信度依据：把客观条件说清楚，用户可以自己复核 */
    private String confidenceReason(List<MonthSample> samples, List<BigDecimal> amounts,
                                    BigDecimal predicted, String outlierMonth) {
        BigDecimal max = Collections.max(amounts);
        BigDecimal min = Collections.min(amounts);
        BigDecimal spread = max.subtract(min)
                .multiply(BigDecimal.valueOf(100))
                .divide(predicted, 2, RoundingMode.HALF_UP);
        StringBuilder reason = new StringBuilder()
                .append("近 ").append(samples.size()).append(" 个月最高 ¥").append(money(max))
                .append("、最低 ¥").append(money(min))
                .append("，相差 ").append(trim(spread)).append("%");
        if (outlierMonth != null) {
            reason.append("；").append(outlierMonth).append(" 明显高于其他月份（超过中位数的 2 倍），已降低其权重");
        }
        return reason.toString();
    }

    private String okMessage(YearMonth target, String previousMonth, BigDecimal predicted,
                             BigDecimal difference, String changePercent) {
        StringBuilder message = new StringBuilder("预计 ")
                .append(target).append(" 支出 ¥").append(money(predicted));
        if (changePercent == null) {
            return message.toString();
        }
        int sign = difference.signum();
        if (sign > 0) {
            message.append("，比 ").append(previousMonth).append(" 多 ¥").append(money(difference))
                    .append("（+").append(trim(new BigDecimal(changePercent))).append("%）");
        } else if (sign < 0) {
            message.append("，比 ").append(previousMonth).append(" 少 ¥").append(money(difference.abs()))
                    .append("（").append(trim(new BigDecimal(changePercent))).append("%）");
        } else {
            message.append("，与 ").append(previousMonth).append("持平");
        }
        return message.toString();
    }

    /** 变化率：(预估 − 最近有效月) ÷ 最近有效月 × 100；分母为 0 时不生成 */
    private static String changePercent(BigDecimal difference, BigDecimal previous) {
        if (previous == null || previous.signum() == 0) {
            return null;
        }
        return difference.multiply(BigDecimal.valueOf(100))
                .divide(previous, 2, RoundingMode.HALF_UP)
                .toPlainString();
    }

    /** 中位数：样本固定为 3 个（奇数），取排序后的中间值；金额一律 BigDecimal */
    static BigDecimal median(List<BigDecimal> amounts) {
        List<BigDecimal> sorted = new ArrayList<>(amounts);
        Collections.sort(sorted);
        int size = sorted.size();
        if (size % 2 == 1) {
            return sorted.get(size / 2);
        }
        return sorted.get(size / 2 - 1).add(sorted.get(size / 2))
                .divide(BigDecimal.valueOf(2), 2, RoundingMode.HALF_UP);
    }

    /**
     * 非 OK 状态：只给状态、文案与参考月的事实数据（本月已支出多少），不给任何预测结论。
     * NOT_APPLICABLE 时没有查库，本月金额按 0 返回。
     */
    private SpendingForecastResponse empty(YearMonth reference, YearMonth target, String status,
                                           String message, int elapsedDays,
                                           BigDecimal currentMonthAmount) {
        return new SpendingForecastResponse(reference.toString(), target.toString(), status, message,
                CONFIDENCE_NONE, "", "", money(BigDecimal.ZERO), money(BigDecimal.ZERO), null, null,
                money(currentMonthAmount), elapsedDays, List.of());
    }

    private static String money(BigDecimal value) {
        return StatisticsService.money(value);
    }

    /** 去掉无意义的小数零：11.90 → 11.9 */
    private static String trim(BigDecimal value) {
        BigDecimal stripped = value.stripTrailingZeros();
        return stripped.scale() < 0 ? stripped.setScale(0).toPlainString() : stripped.toPlainString();
    }

    /** 一个有效历史月份的样本 */
    private record MonthSample(String month, BigDecimal amount) {
    }
}
