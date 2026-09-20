package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.AnomaliesResponse;
import com.campus.ledger.dto.AnomalyItem;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.ExpenseDetail;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 智能消费异常检测。
 *
 * 回答的问题：**指定月份里哪些消费偏离了用户自己的常态**。
 * 与相邻模块的边界：
 *   - 周期识别看"会重复发生的模式"（跨月，与月份无关）；
 *   - 消费洞察看"这个月的结构"（占比、环比、预算）；
 *   - 本模块看"偏离常态的地方"（本月相对前几个月是否异常）。
 *
 * 三条规则全部基于分类自己的基线，不使用机器学习、不使用全局平均。
 * 所有查询固定带当前登录用户的 user_id，结果实时计算不落库。
 */
@Service
public class SpendingAnomalyService {

    /** 月度对比的基线月数：目标月之前的 3 个完整自然月 */
    static final int BASELINE_MONTHS = 3;

    /**
     * 单笔异常的基线窗口。
     *
     * 用 90 天而不是 30 天：月初时 30 天窗口内可能只有上月末的几笔，
     * 基线抖动大；90 天覆盖约 3 个月的消费节奏，中位数更稳定。
     */
    static final int TRANSACTION_WINDOW_DAYS = 90;

    /** 单笔异常的最少样本数：少于 5 笔时中位数没有代表性 */
    static final int MIN_CATEGORY_SAMPLES = 5;

    /** 分类月度上涨的最低倍数 */
    static final BigDecimal CATEGORY_SPIKE_RATIO = new BigDecimal("1.5");

    /** 分类月度上涨的"严重"倍数 */
    static final BigDecimal CATEGORY_SPIKE_HIGH_RATIO = new BigDecimal("2.5");

    /** 频次异常的"常态"下限：每月至少 2 笔才谈得上频次变化 */
    static final int MIN_BASELINE_COUNT = 2;

    /** 频次异常的倍数与绝对增量门槛 */
    static final BigDecimal FREQUENCY_SPIKE_RATIO = new BigDecimal("2");
    static final BigDecimal FREQUENCY_SPIKE_HIGH_RATIO = new BigDecimal("3");
    static final int FREQUENCY_SPIKE_MIN_DELTA = 5;

    /** 单笔异常的倍数门槛 */
    static final BigDecimal TRANSACTION_RATIO = new BigDecimal("3");
    static final BigDecimal TRANSACTION_HIGH_RATIO = new BigDecimal("5");

    /**
     * 绝对值门槛（元）。
     *
     * 只有倍数门槛会产生噪声：日均 ¥12 的通讯从 ¥12 涨到 ¥20 就是 67% 的涨幅，
     * 但只多了 ¥8，提醒对用户没有价值。因此三类规则都要求一个绝对差额。
     */
    static final BigDecimal MIN_ABSOLUTE_DELTA = new BigDecimal("100");

    /** 单次最多返回的异常条数，与消费洞察保持一致，避免页面堆满文字 */
    static final int MAX_ITEMS = 5;

    /** 明细查询上限，兜住极端高频用户 */
    static final int MAX_DETAIL_ROWS = 2000;

    /** 只允许查询最近 12 个自然月 */
    static final int MAX_BACK_MONTHS = 12;

    /** DATE_FORMAT 的月份模式，作为参数传入避免 SQL 里出现 % 与 MyBatis 占位符混淆 */
    static final String MONTH_PATTERN = "%Y-%m";

    private final BillMapper billMapper;
    private final Clock clock;

    public SpendingAnomalyService(BillMapper billMapper, Clock clock) {
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public AnomaliesResponse detect(Long userId, String month) {
        YearMonth target = Months.parse(month);
        ensureWithinWindow(target);
        List<String> baselineMonths = baselineMonths(target);

        // 查询 1：一次拿到目标月 + 前 3 个月的「分类 + 月份」聚合
        Map<String, Map<String, CategoryMonthlySum>> monthly = loadMonthly(userId, target);
        Map<String, CategoryMonthlySum> currentByCategory = monthly.getOrDefault(target.toString(), Map.of());

        if (currentByCategory.isEmpty()) {
            return AnomaliesResponse.of(target.toString(), "NO_DATA",
                    "本月还没有支出记录", baselineMonths, List.of());
        }
        if (monthly.size() == 1) {
            return AnomaliesResponse.of(target.toString(), "NOT_ENOUGH_BASELINE",
                    "积累几个月数据后，这里可以对比出消费异常", baselineMonths, List.of());
        }

        // 查询 2：一次取回「目标月之前 90 天 + 目标月」的支出明细，
        // 前半段用于算中位数基线，后半段用于判定本月异常
        List<ExpenseDetail> details = loadDetails(userId, target);
        List<ExpenseDetail> baselineDetails = filterBefore(details, target);
        List<ExpenseDetail> targetDetails = filterInMonth(details, target);

        List<AnomalyItem> items = new ArrayList<>();
        appendCategorySpikes(items, target, monthly);
        appendLargeTransactions(items, baselineDetails, targetDetails);
        appendFrequencySpikes(items, target, monthly);

        items.sort(Comparator
                .comparingInt((AnomalyItem item) -> severityRank(item.getSeverity())).reversed()
                .thenComparing(Comparator.comparing(SpendingAnomalyService::magnitude).reversed())
                .thenComparing(AnomalyItem::getCategory));

        List<AnomalyItem> top = items.size() > MAX_ITEMS ? items.subList(0, MAX_ITEMS) : items;
        if (top.isEmpty()) {
            return AnomaliesResponse.of(target.toString(), "NO_ANOMALY",
                    "本月消费节奏正常，没有发现明显异常", baselineMonths, List.of());
        }
        return AnomaliesResponse.of(target.toString(), "OK",
                "本月发现 " + top.size() + " 处消费异常", baselineMonths, top);
    }

    // ==================== 规则 1：分类月度上涨 ====================

    private void appendCategorySpikes(List<AnomalyItem> items, YearMonth target,
                                      Map<String, Map<String, CategoryMonthlySum>> monthly) {
        Map<String, CategoryMonthlySum> current = monthly.get(target.toString());
        if (current == null) {
            return;
        }
        for (Map.Entry<String, CategoryMonthlySum> entry : current.entrySet()) {
            String category = entry.getKey();
            BigDecimal currentAmount = amountOf(entry.getValue());
            BigDecimal baseline = averageAmount(monthly, category, target);
            if (baseline.signum() <= 0) {
                continue;
            }
            BigDecimal difference = currentAmount.subtract(baseline);
            if (currentAmount.compareTo(baseline.multiply(CATEGORY_SPIKE_RATIO)) < 0
                    || difference.compareTo(MIN_ABSOLUTE_DELTA) < 0) {
                continue;
            }
            boolean high = currentAmount.compareTo(baseline.multiply(CATEGORY_SPIKE_HIGH_RATIO)) >= 0;
            items.add(new AnomalyItem("CATEGORY_SPIKE", high ? "HIGH" : "MEDIUM",
                    severityLabel(high), category, category + "支出明显上涨",
                    category + "本月 ¥" + money(currentAmount) + "，前 " + BASELINE_MONTHS
                            + " 个月平均 ¥" + money(baseline) + "，上涨 "
                            + percent(currentAmount, baseline) + "%（多支出 ¥" + money(difference) + "）",
                    money(currentAmount), money(baseline), money(difference),
                    percent(currentAmount, baseline), null, null));
        }
    }

    /** 基线的绝对差额（用于排序），无法解析时返回 0 */
    private static BigDecimal magnitude(AnomalyItem item) {
        try {
            return new BigDecimal(item.getDifference());
        } catch (NumberFormatException e) {
            return BigDecimal.ZERO;
        }
    }

    // ==================== 规则 2：单笔异常 ====================

    private void appendLargeTransactions(List<AnomalyItem> items, List<ExpenseDetail> baselineDetails,
                                         List<ExpenseDetail> targetDetails) {
        // 基线只用目标月之前的明细；被检测的本月账单不参与自己的基线计算
        Map<String, List<ExpenseDetail>> byCategory = new LinkedHashMap<>();
        for (ExpenseDetail detail : baselineDetails) {
            if (detail.getBillDate() == null || detail.getAmount() == null) {
                continue;
            }
            byCategory.computeIfAbsent(nullToEmpty(detail.getCategory()), k -> new ArrayList<>()).add(detail);
        }

        for (Map.Entry<String, List<ExpenseDetail>> entry : byCategory.entrySet()) {
            List<ExpenseDetail> categoryDetails = entry.getValue();
            if (categoryDetails.size() < MIN_CATEGORY_SAMPLES) {
                continue;
            }
            BigDecimal median = medianAmount(categoryDetails);
            if (median.signum() <= 0) {
                continue;
            }
            for (ExpenseDetail detail : targetDetails) {
                if (!entry.getKey().equals(nullToEmpty(detail.getCategory()))
                        || detail.getAmount() == null || detail.getBillDate() == null) {
                    continue;
                }
                BigDecimal amount = detail.getAmount();
                BigDecimal difference = amount.subtract(median);
                if (amount.compareTo(median.multiply(TRANSACTION_RATIO)) < 0
                        || difference.compareTo(MIN_ABSOLUTE_DELTA) < 0) {
                    continue;
                }
                boolean high = amount.compareTo(median.multiply(TRANSACTION_HIGH_RATIO)) >= 0;
                String where = nullToEmpty(detail.getMerchant()).isEmpty()
                        ? entry.getKey()
                        : detail.getMerchant().trim();
                items.add(new AnomalyItem("LARGE_TRANSACTION", high ? "HIGH" : "MEDIUM",
                        severityLabel(high), entry.getKey(), "出现一笔较高金额消费",
                        where + " " + detail.getBillDate() + " 支出 ¥" + money(amount)
                                + "，该分类近 " + TRANSACTION_WINDOW_DAYS + " 天单笔中位数 ¥"
                                + money(median) + "，约为 " + multiple(amount, median) + " 倍",
                        money(amount), money(median), money(difference),
                        percent(amount, median), where, detail.getBillDate().toString()));
            }
        }
    }

    // ==================== 规则 3：消费频次异常 ====================

    private void appendFrequencySpikes(List<AnomalyItem> items, YearMonth target,
                                       Map<String, Map<String, CategoryMonthlySum>> monthly) {
        Map<String, CategoryMonthlySum> current = monthly.get(target.toString());
        if (current == null) {
            return;
        }
        for (Map.Entry<String, CategoryMonthlySum> entry : current.entrySet()) {
            String category = entry.getKey();
            int currentCount = countOf(entry.getValue());
            BigDecimal baseline = averageCount(monthly, category, target);
            if (baseline.compareTo(BigDecimal.valueOf(MIN_BASELINE_COUNT)) < 0) {
                continue;
            }
            BigDecimal delta = BigDecimal.valueOf(currentCount).subtract(baseline);
            if (BigDecimal.valueOf(currentCount).compareTo(baseline.multiply(FREQUENCY_SPIKE_RATIO)) < 0
                    || delta.compareTo(BigDecimal.valueOf(FREQUENCY_SPIKE_MIN_DELTA)) < 0) {
                continue;
            }
            boolean high = BigDecimal.valueOf(currentCount)
                    .compareTo(baseline.multiply(FREQUENCY_SPIKE_HIGH_RATIO)) >= 0;
            items.add(new AnomalyItem("FREQUENCY_SPIKE", high ? "HIGH" : "MEDIUM",
                    severityLabel(high), category, category + "消费频次明显增加",
                    category + "本月 " + currentCount + " 笔，前 " + BASELINE_MONTHS + " 个月平均 "
                            + trim(baseline) + " 笔，多 " + trim(delta) + " 笔",
                    String.valueOf(currentCount), trim(baseline), trim(delta),
                    percent(BigDecimal.valueOf(currentCount), baseline), null, null));
        }
    }

    // ==================== 查询与计算 ====================

    /** 目标月 + 前 3 个月，映射为「月份 → (分类 → 聚合)」 */
    private Map<String, Map<String, CategoryMonthlySum>> loadMonthly(Long userId, YearMonth target) {
        YearMonth first = target.minusMonths(BASELINE_MONTHS);
        List<CategoryMonthlySum> rows = billMapper.sumByCategoryAndMonth(userId,
                BillType.EXPENSE.getCode(), first.atDay(1), target.atEndOfMonth(), MONTH_PATTERN);
        Map<String, Map<String, CategoryMonthlySum>> result = new LinkedHashMap<>();
        for (CategoryMonthlySum row : rows) {
            if (row.getMonth() == null || row.getCategory() == null) {
                continue;
            }
            result.computeIfAbsent(row.getMonth(), k -> new LinkedHashMap<>()).put(row.getCategory(), row);
        }
        return result;
    }

    /**
     * 单笔异常的基线窗口：目标月开始前的 90 天。
     *
     * 这里刻意**不包含目标月自己**——如果把被检测的那个月算进基线，
     * 一笔异常大额会把中位数显著抬高，导致它自己反而达不到 3 倍门槛而漏报。
     * 基线只反映"目标月之前"的消费水平，才能和本月的单笔做对比。
     */
    private List<ExpenseDetail> loadDetails(Long userId, YearMonth target) {
        LocalDate end = target.atDay(1).minusDays(1);
        return billMapper.selectExpenseDetails(userId, BillType.EXPENSE.getCode(),
                end.minusDays(TRANSACTION_WINDOW_DAYS), target.atEndOfMonth(), MAX_DETAIL_ROWS);
    }

    /** 目标月之前的明细，用于算基线 */
    private static List<ExpenseDetail> filterBefore(List<ExpenseDetail> details, YearMonth target) {
        List<ExpenseDetail> result = new ArrayList<>();
        for (ExpenseDetail detail : details) {
            if (detail.getBillDate() != null && detail.getBillDate().isBefore(target.atDay(1))) {
                result.add(detail);
            }
        }
        return result;
    }

    /** 目标月内的明细，用于判定单笔异常 */
    private static List<ExpenseDetail> filterInMonth(List<ExpenseDetail> details, YearMonth target) {
        List<ExpenseDetail> result = new ArrayList<>();
        for (ExpenseDetail detail : details) {
            if (detail.getBillDate() != null && YearMonth.from(detail.getBillDate()).equals(target)) {
                result.add(detail);
            }
        }
        return result;
    }

    /**
     * 分类的月度金额基线：只对"有支出的月份"取平均。
     *
     * 若把没有记录的月份按 0 计入，会把基线拉低，导致一笔正常支出被误判为暴涨。
     */
    private BigDecimal averageAmount(Map<String, Map<String, CategoryMonthlySum>> monthly,
                                     String category, YearMonth target) {
        BigDecimal sum = BigDecimal.ZERO;
        int months = 0;
        for (int i = 1; i <= BASELINE_MONTHS; i++) {
            Map<String, CategoryMonthlySum> snapshot = monthly.get(target.minusMonths(i).toString());
            if (snapshot == null || !snapshot.containsKey(category)) {
                continue;
            }
            sum = sum.add(amountOf(snapshot.get(category)));
            months++;
        }
        return months == 0 ? BigDecimal.ZERO : sum.divide(BigDecimal.valueOf(months), 2, RoundingMode.HALF_UP);
    }

    /** 分类的月度笔数基线，口径同上（只对有效月份取平均） */
    private BigDecimal averageCount(Map<String, Map<String, CategoryMonthlySum>> monthly,
                                    String category, YearMonth target) {
        BigDecimal sum = BigDecimal.ZERO;
        int months = 0;
        for (int i = 1; i <= BASELINE_MONTHS; i++) {
            Map<String, CategoryMonthlySum> snapshot = monthly.get(target.minusMonths(i).toString());
            if (snapshot == null || !snapshot.containsKey(category)) {
                continue;
            }
            sum = sum.add(BigDecimal.valueOf(countOf(snapshot.get(category))));
            months++;
        }
        return months == 0 ? BigDecimal.ZERO : sum.divide(BigDecimal.valueOf(months), 2, RoundingMode.HALF_UP);
    }

    /** 前 3 个自然月，按时间升序，供响应展示 */
    private List<String> baselineMonths(YearMonth target) {
        List<String> months = new ArrayList<>(BASELINE_MONTHS);
        for (int i = BASELINE_MONTHS; i >= 1; i--) {
            months.add(target.minusMonths(i).toString());
        }
        return months;
    }

    /**
     * 月份范围校验：只允许查询最近 12 个自然月。
     * 超出范围不返回数据而不是静默截断，避免用户以为"查过了但没异常"。
     */
    private void ensureWithinWindow(YearMonth target) {
        YearMonth current = YearMonth.now(clock);
        YearMonth earliest = current.minusMonths(MAX_BACK_MONTHS);
        if (target.isAfter(current)) {
            throw new BizException(400, "不能查询未来的月份");
        }
        if (target.isBefore(earliest)) {
            throw new BizException(400, "只能查询最近 " + MAX_BACK_MONTHS + " 个月的消费异常");
        }
    }

    // ==================== 数值与文案工具 ====================

    /** 中位数：偶数个取中间两个的平均；金额一律用 BigDecimal */
    static BigDecimal medianAmount(List<ExpenseDetail> details) {
        List<BigDecimal> amounts = new ArrayList<>(details.size());
        for (ExpenseDetail detail : details) {
            if (detail.getAmount() != null) {
                amounts.add(detail.getAmount());
            }
        }
        if (amounts.isEmpty()) {
            return BigDecimal.ZERO;
        }
        Collections.sort(amounts);
        int size = amounts.size();
        if (size % 2 == 1) {
            return amounts.get(size / 2);
        }
        return amounts.get(size / 2 - 1).add(amounts.get(size / 2))
                .divide(BigDecimal.valueOf(2), 2, RoundingMode.HALF_UP);
    }

    static BigDecimal amountOf(CategoryMonthlySum sum) {
        return sum == null || sum.getAmount() == null ? BigDecimal.ZERO : sum.getAmount();
    }

    static int countOf(CategoryMonthlySum sum) {
        return sum == null || sum.getCount() == null ? 0 : sum.getCount();
    }

    private static int severityRank(String severity) {
        return "HIGH".equals(severity) ? 2 : 1;
    }

    private static String severityLabel(boolean high) {
        return high ? "需注意" : "留意";
    }

    /** 变化百分比：(current − baseline) ÷ baseline × 100，保留两位小数 */
    private static String percent(BigDecimal current, BigDecimal baseline) {
        if (baseline == null || baseline.signum() == 0) {
            return "0.00";
        }
        return current.subtract(baseline)
                .multiply(BigDecimal.valueOf(100))
                .divide(baseline, 2, RoundingMode.HALF_UP)
                .toPlainString();
    }

    /** 倍数：保留一位小数 */
    private static String multiple(BigDecimal current, BigDecimal baseline) {
        if (baseline == null || baseline.signum() == 0) {
            return "0.0";
        }
        return current.divide(baseline, 1, RoundingMode.HALF_UP).toPlainString();
    }

    /** 去掉无意义的小数零：18.00 → 18 */
    private static String trim(BigDecimal value) {
        BigDecimal stripped = value.stripTrailingZeros();
        return stripped.scale() < 0 ? stripped.setScale(0).toPlainString() : stripped.toPlainString();
    }

    private static String money(BigDecimal value) {
        return StatisticsService.money(value);
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

}
