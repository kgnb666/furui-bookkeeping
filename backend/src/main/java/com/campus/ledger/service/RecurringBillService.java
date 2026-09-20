package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.dto.RecurringBillResponse;
import com.campus.ledger.dto.RecurringBillRow;
import com.campus.ledger.dto.RecurringBillsResponse;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 智能周期性账单识别。
 *
 * 全部规则都是「算术 + 阈值」，不使用大模型、不调用外部服务、结果不落库。
 *
 * 识别流程：
 *   1. 一次查询取最近 180 天的支出明细（商户非空），走 idx_bill_user_type_date 索引；
 *   2. 按【归一化商户名】分组，商户分组与统计全部在内存完成，不做按商户的循环查询（禁止 N+1）；
 *   3. 每个分组按日期升序算相邻间隔，用中位数间隔匹配周期类型；
 *   4. 四项信号（间隔稳定 / 金额稳定 / 商户一致 / 分类一致）计数得到置信度；
 *   5. 信号数 ≤ 2 直接丢弃，不返回 LOW。
 *
 * 所有查询固定带当前登录用户的 user_id，不接受前端传入的用户标识。
 */
@Service
public class RecurringBillService {

    /** 分析窗口：180 天。月周期要求至少 4 次样本，90 天窗口永远达不到这个门槛 */
    public static final int WINDOW_DAYS = 180;

    /** 同一商户最低样本数：3 次只能得到 2 个间隔，一次异常就会让稳定性判断失效 */
    public static final int MIN_SAMPLES = 4;

    /** 高频过滤：平均间隔小于该天数直接排除，用于挡住食堂、公交这类日常习惯 */
    public static final int MIN_AVERAGE_INTERVAL = 5;

    /** 金额稳定：变异系数上限 */
    public static final BigDecimal MAX_AMOUNT_CV = new BigDecimal("0.15");

    /**
     * 分类一致：主导分类占比下限，单位是**百分数**（与 ratio() 的返回值一致）。
     *
     * 注意单位：ratio() 返回的是 25.00 这样的百分数，如果这里写成 0.80 就会把
     * "25% 一致"误判为通过，导致分类信号几乎恒为真、结果系统性偏 HIGH。
     */
    public static final BigDecimal MIN_CATEGORY_RATIO = new BigDecimal("80");

    /**
     * 周期匹配的最低覆盖率：落在周期区间内的间隔必须占到这个比例。
     *
     * 只靠"中位数落进区间"是不够的——间隔完全杂乱时中位数也可能偶然落进区间
     * （例如间隔为 2/3/9/15/22/30/40 天时中位数是 15，恰好在双周区间内），
     * 那会把随机消费误判成周期。加这道门槛后，这类数据不会匹配到任何周期。
     */
    public static final BigDecimal MIN_CYCLE_COVERAGE = new BigDecimal("0.60");

    /** 历史跨度不足该天数时提示"用得太短"（月周期不可能成立） */
    public static final int MIN_HISTORY_DAYS = 60;

    /** 窗口内支出账单少于该条数视为样本太少 */
    public static final int MIN_ROWS_FOR_ANALYSIS = 5;

    /** 单次拉取明细的上限，兜住极端高频用户 */
    public static final int MAX_ROWS = 2000;

    /**
     * 支持的周期及其间隔区间（天）。区间之间刻意不重叠，
     * 一组数据只能落进一个周期，避免"既像周又像双周"的歧义结论。
     */
    static final List<Cycle> CYCLES = List.of(
            new Cycle("WEEKLY", "每周一次", 7, 5, 10),
            new Cycle("BIWEEKLY", "每两周一次", 14, 12, 17),
            new Cycle("MONTHLY", "每月一次", 30, 26, 35)
    );

    private final BillMapper billMapper;
    private final Clock clock;

    public RecurringBillService(BillMapper billMapper, Clock clock) {
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public RecurringBillsResponse detect(Long userId, String type) {
        // 只分析支出；收入与不计收支不参与周期识别
        BillType billType = resolveType(type);
        if (billType != BillType.EXPENSE) {
            return RecurringBillsResponse.of(WINDOW_DAYS, "NO_DATA",
                    "目前只支持识别支出的周期性", List.of());
        }

        LocalDate today = LocalDate.now(clock);
        LocalDate start = today.minusDays(WINDOW_DAYS);
        List<RecurringBillRow> rows = billMapper.selectRecurringCandidates(
                userId, billType.getCode(), start, MAX_ROWS);

        // 以下状态判断全部基于这一次查询的结果，不再产生额外 SQL
        if (rows.isEmpty()) {
            return RecurringBillsResponse.of(WINDOW_DAYS, "NO_DATA",
                    "还没有足够的支出记录，记录更多账单后可以识别周期性支出", List.of());
        }
        LocalDate earliest = rows.stream()
                .map(RecurringBillRow::getBillDate)
                .filter(java.util.Objects::nonNull)
                .min(Comparator.naturalOrder())
                .orElse(today);
        if (earliest.isAfter(today.minusDays(MIN_HISTORY_DAYS))) {
            return RecurringBillsResponse.of(WINDOW_DAYS, "NOT_ENOUGH_HISTORY",
                    "使用 3 个月以上后，这里会显示周期性支出", List.of());
        }
        if (rows.size() < MIN_ROWS_FOR_ANALYSIS) {
            return RecurringBillsResponse.of(WINDOW_DAYS, "NO_DATA",
                    "还没有足够的支出记录，记录更多账单后可以识别周期性支出", List.of());
        }

        List<RecurringBillResponse> items = analyze(rows, today);
        if (items.isEmpty()) {
            return RecurringBillsResponse.of(WINDOW_DAYS, "NO_RECURRING",
                    "最近 " + WINDOW_DAYS + " 天没有发现明显的周期性支出", List.of());
        }
        return RecurringBillsResponse.of(WINDOW_DAYS, "OK",
                "在最近 " + WINDOW_DAYS + " 天的账单中识别到 " + items.size() + " 项周期性支出", items);
    }

    /** 供单元测试直接验证算法，跳过 status 判断 */
    List<RecurringBillResponse> analyze(List<RecurringBillRow> rows, LocalDate today) {
        LocalDate start = today.minusDays(WINDOW_DAYS);
        Map<String, List<RecurringBillRow>> groups = new LinkedHashMap<>();
        for (RecurringBillRow row : rows) {
            if (row.getBillDate() == null || row.getBillDate().isBefore(start)) {
                continue;
            }
            String key = normalizeMerchant(row.getMerchant());
            if (key.isEmpty()) {
                continue;
            }
            groups.computeIfAbsent(key, k -> new ArrayList<>()).add(row);
        }

        List<RecurringBillResponse> result = new ArrayList<>();
        for (Map.Entry<String, List<RecurringBillRow>> entry : groups.entrySet()) {
            RecurringBillResponse item = detectOne(entry.getKey(), entry.getValue(), today);
            if (item != null) {
                result.add(item);
            }
        }
        // 置信度高的排前面，同级按样本数多的排前面
        result.sort(Comparator
                .comparingInt((RecurringBillResponse item) -> "HIGH".equals(item.getConfidence()) ? 0 : 1)
                .thenComparing(Comparator.comparingInt(RecurringBillResponse::getSampleCount).reversed()));
        return result;
    }

    /** 单个商户分组的周期判断 */
    private RecurringBillResponse detectOne(String key, List<RecurringBillRow> group, LocalDate today) {
        if (group.size() < MIN_SAMPLES) {
            return null;
        }

        // 主导分类：占比最高的那个分类
        Map<String, Integer> categoryCount = new LinkedHashMap<>();
        for (RecurringBillRow row : group) {
            categoryCount.merge(nullToEmpty(row.getCategory()), 1, Integer::sum);
        }
        String dominant = categoryCount.entrySet().stream()
                .max(Comparator.comparingInt(Map.Entry::getValue))
                .map(Map.Entry::getKey)
                .orElse("");
        int dominantCount = categoryCount.getOrDefault(dominant, 0);
        BigDecimal categoryRatio = ratio(dominantCount, group.size());

        /*
         * 参与周期计算的序列：
         *   分类一致 → 用全部记录；
         *   分类不一致 → 优先只取主导分类的记录，但子集本身也必须够样本，
         *   否则回退到全部记录（此时分类信号不通过，且金额/间隔会体现真实波动）。
         *
         * 这里的样本数检查是必须的：曾经漏掉它时，主导分类只剩 1 条也会被当作
         * 一条"金额完全稳定"的序列，从而给出 HIGH 置信度的误报。
         */
        List<RecurringBillRow> series = group;
        if (categoryRatio.compareTo(MIN_CATEGORY_RATIO) < 0) {
            List<RecurringBillRow> dominantOnly = group.stream()
                    .filter(row -> dominant.equals(nullToEmpty(row.getCategory())))
                    .toList();
            if (dominantOnly.size() >= MIN_SAMPLES) {
                series = dominantOnly;
            }
        }

        List<LocalDate> dates = series.stream()
                .map(RecurringBillRow::getBillDate)
                .sorted()
                .toList();
        List<Integer> intervals = new ArrayList<>();
        for (int i = 1; i < dates.size(); i++) {
            intervals.add((int) (dates.get(i).toEpochDay() - dates.get(i - 1).toEpochDay()));
        }
        if (intervals.size() < MIN_SAMPLES - 1) {
            return null;
        }

        // 高频过滤：平均间隔过短说明这是日常习惯，不是周期账单
        BigDecimal averageInterval = average(intervals);
        if (averageInterval.compareTo(BigDecimal.valueOf(MIN_AVERAGE_INTERVAL)) < 0) {
            return null;
        }

        Cycle cycle = matchCycle(median(intervals), intervals);
        if (cycle == null) {
            return null;
        }

        BigDecimal averageAmount = averageAmount(series);
        BigDecimal cv = coefficientOfVariation(series, averageAmount);

        boolean intervalStable = intervals.stream().allMatch(cycle::covers);
        boolean amountStable = cv.compareTo(MAX_AMOUNT_CV) <= 0;
        boolean merchantConsistent = true;   // 分组前提，恒成立
        // 分类信号必须按"原始分组"的比例判断，不能按收窄后的子集重算——
        // 否则 71% 的组会因为子集变成 100% 而重新拿到 HIGH。
        boolean categoryConsistent = categoryRatio.compareTo(MIN_CATEGORY_RATIO) >= 0;

        int signals = (intervalStable ? 1 : 0) + (amountStable ? 1 : 0)
                + (merchantConsistent ? 1 : 0) + (categoryConsistent ? 1 : 0);
        if (signals <= 2) {
            return null;                      // 不返回 LOW
        }
        String confidence = signals == 4 ? "HIGH" : "MEDIUM";

        LocalDate lastDate = dates.get(dates.size() - 1);
        LocalDate nextDate = nextDate(lastDate, cycle);
        int minInterval = intervals.stream().mapToInt(Integer::intValue).min().orElse(0);
        int maxInterval = intervals.stream().mapToInt(Integer::intValue).max().orElse(0);
        // 只有在"分类一致"或"已收窄到主导分类"时才说明分类情况，
        // 否则说明与统计口径不符
        boolean narrowed = series != group;

        return new RecurringBillResponse(
                displayName(group, key),
                dominant,
                cycle.code(),
                cycle.label(),
                confidence,
                "HIGH".equals(confidence) ? "高" : "中",
                series.size(),
                money(averageAmount),
                averageInterval.setScale(0, RoundingMode.HALF_UP).intValue(),
                minInterval + "~" + maxInterval + " 天",
                cv.setScale(2, RoundingMode.HALF_UP).toPlainString(),
                categoryRatio.toPlainString(),
                lastDate.toString(),
                nextDate == null ? null : nextDate.toString(),
                buildReason(series.size(), cycle, averageAmount, minInterval, maxInterval,
                        amountStable, narrowed, categoryConsistent));
    }

    /**
     * 周期匹配：用中位数间隔而不是平均间隔，避免一次漏记把平均值带偏。
     * 区间之间不重叠，因此最多命中一个周期。
     */
    private Cycle matchCycle(BigDecimal medianInterval, List<Integer> intervals) {
        for (Cycle cycle : CYCLES) {
            if (medianInterval.compareTo(BigDecimal.valueOf(cycle.minDays())) < 0
                    || medianInterval.compareTo(BigDecimal.valueOf(cycle.maxDays())) > 0) {
                continue;
            }
            long covered = intervals.stream().filter(cycle::covers).count();
            BigDecimal coverage = BigDecimal.valueOf(covered)
                    .divide(BigDecimal.valueOf(intervals.size()), 4, RoundingMode.HALF_UP);
            if (coverage.compareTo(MIN_CYCLE_COVERAGE) >= 0) {
                return cycle;
            }
        }
        return null;
    }

    /**
     * 下次预计日期。按月周期用日历月推进（含月末与闰年处理），
     * 周/双周直接加天数。
     */
    private LocalDate nextDate(LocalDate lastDate, Cycle cycle) {
        return switch (cycle.code()) {
            case "MONTHLY" -> lastDate.plusMonths(1);
            case "BIWEEKLY" -> lastDate.plusDays(14);
            default -> lastDate.plusDays(7);
        };
    }

    /**
     * 商户名归一化。
     *
     * 规则（保持简单、可解释，不做模糊匹配）：
     *   1. trim；
     *   2. 去除半角与全角空格（含连续空格）；
     *   3. 统一转小写，大小写不敏感；
     *   4. 去除明确的"长后缀"：旗舰店 / 门店 / 分店 / 专卖店 / 有限公司 / 有限责任公司。
     *
     * 刻意 **不剥离单独的"店"字**：酒店、便利店、药店等名称里的"店"是名称本身的一部分，
     * 剥掉会把"如家酒店"变成"如家酒"，造成错误合并。
     */
    static String normalizeMerchant(String merchant) {
        if (merchant == null) {
            return "";
        }
        String text = merchant.replace(" ", "").replace("\u3000", "").trim().toLowerCase();
        for (String suffix : LONG_SUFFIXES) {
            if (text.endsWith(suffix) && text.length() > suffix.length()) {
                text = text.substring(0, text.length() - suffix.length());
            }
        }
        return text;
    }

    /** 长后缀按长度从长到短排列，避免"有限责任公司"被"有限公司"先截断 */
    private static final List<String> LONG_SUFFIXES = List.of(
            "有限责任公司", "有限公司", "专卖店", "旗舰店", "分店", "门店");

    /** 展示名取该组中出现次数最多的原始写法，保留用户记账时的习惯 */
    private static String displayName(List<RecurringBillRow> group, String fallback) {
        Map<String, Integer> counts = new LinkedHashMap<>();
        for (RecurringBillRow row : group) {
            counts.merge(nullToEmpty(row.getMerchant()).trim(), 1, Integer::sum);
        }
        return counts.entrySet().stream()
                .max(Comparator.comparingInt(Map.Entry::getValue))
                .map(Map.Entry::getKey)
                .orElse(fallback);
    }

    /** 可解释说明：把次数、间隔区间、金额稳定性都写清楚，用户可以自己核对 */
    private static String buildReason(int count, Cycle cycle, BigDecimal averageAmount,
                                      int minInterval, int maxInterval, boolean amountStable,
                                      boolean narrowed, boolean categoryConsistent) {
        StringBuilder builder = new StringBuilder();
        builder.append("近").append(WINDOW_DAYS).append("天 ").append(count).append(" 次消费，");
        builder.append(amountStable ? "金额稳定" : "金额有波动");
        builder.append("，约每 ").append(cycle.targetDays()).append(" 天发生一次");
        builder.append("（间隔 ").append(minInterval).append("~").append(maxInterval).append(" 天，");
        builder.append("平均 ¥").append(money(averageAmount)).append("）");
        if (!categoryConsistent) {
            builder.append(narrowed
                    ? "；该商户分类不完全一致，已按主导分类统计"
                    : "；该商户分类不一致，分类信号未通过");
        }
        return builder.toString();
    }

    /** type 参数默认支出；兼容 1 / EXPENSE / 支出 三种写法 */
    private BillType resolveType(String type) {
        if (type == null || type.isBlank()) {
            return BillType.EXPENSE;
        }
        BillType parsed = BillType.parse(type);
        if (parsed == null) {
            throw new com.campus.ledger.common.BizException(400, "收支类型只能是 1(支出)/2(收入)/3(不计收支)");
        }
        return parsed;
    }

    // ==================== 数值工具（全部用 BigDecimal，避免浮点误差） ====================

    private static BigDecimal average(List<Integer> values) {
        BigDecimal sum = BigDecimal.ZERO;
        for (Integer value : values) {
            sum = sum.add(BigDecimal.valueOf(value));
        }
        return sum.divide(BigDecimal.valueOf(values.size()), 4, RoundingMode.HALF_UP);
    }

    /** 中位数：偶数个取中间两个的平均 */
    private static BigDecimal median(List<Integer> values) {
        List<Integer> sorted = new ArrayList<>(values);
        sorted.sort(Comparator.naturalOrder());
        int size = sorted.size();
        if (size % 2 == 1) {
            return BigDecimal.valueOf(sorted.get(size / 2));
        }
        BigDecimal middle = BigDecimal.valueOf(sorted.get(size / 2 - 1) + sorted.get(size / 2));
        return middle.divide(BigDecimal.valueOf(2), 4, RoundingMode.HALF_UP);
    }

    private static BigDecimal averageAmount(List<RecurringBillRow> series) {
        BigDecimal sum = BigDecimal.ZERO;
        for (RecurringBillRow row : series) {
            sum = sum.add(row.getAmount() == null ? BigDecimal.ZERO : row.getAmount());
        }
        return sum.divide(BigDecimal.valueOf(series.size()), 4, RoundingMode.HALF_UP);
    }

    /** 变异系数 = 标准差 ÷ 平均金额 */
    private static BigDecimal coefficientOfVariation(List<RecurringBillRow> series,
                                                      BigDecimal averageAmount) {
        if (averageAmount.signum() == 0) {
            return BigDecimal.ZERO;
        }
        BigDecimal sumOfSquares = BigDecimal.ZERO;
        for (RecurringBillRow row : series) {
            BigDecimal amount = row.getAmount() == null ? BigDecimal.ZERO : row.getAmount();
            BigDecimal deviation = amount.subtract(averageAmount);
            sumOfSquares = sumOfSquares.add(deviation.multiply(deviation));
        }
        BigDecimal variance = sumOfSquares.divide(BigDecimal.valueOf(series.size()), 6, RoundingMode.HALF_UP);
        BigDecimal stdDev = BigDecimal.valueOf(Math.sqrt(variance.doubleValue()));
        return stdDev.divide(averageAmount, 6, RoundingMode.HALF_UP);
    }

    private static BigDecimal ratio(int part, int total) {
        if (total <= 0) {
            return BigDecimal.ZERO.setScale(2);
        }
        return BigDecimal.valueOf(part)
                .multiply(BigDecimal.valueOf(100))
                .divide(BigDecimal.valueOf(total), 2, RoundingMode.HALF_UP);
    }

    private static String money(BigDecimal value) {
        return StatisticsService.money(value);
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    /** 支持的周期类型 */
    record Cycle(String code, String label, int targetDays, int minDays, int maxDays) {
        boolean covers(int interval) {
            return interval >= minDays && interval <= maxDays;
        }
    }
}
