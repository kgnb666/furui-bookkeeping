package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Months;
import com.campus.ledger.dto.ExpenseDetail;
import com.campus.ledger.dto.MerchantSpendingItem;
import com.campus.ledger.dto.SpendingMerchantResponse;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Clock;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

/**
 * 消费对象分析（我的钱花给谁了）。
 *
 * 与相邻模块的边界（维度互不重叠）：
 *   - Stage 4-A 预算预测看"会不会超预算"（预算维度）；
 *   - Stage 4-B 周期识别用商户是为了找"间隔是否规律"（周期维度）；
 *   - Stage 4-C 异常检测返回商户只是为了定位异常单笔（偏离维度）；
 *   - Stage 4-D 下月预估看"下个月大概花多少"（月度总量维度）；
 *   - Stage 4-E 节奏分析看"什么时候花"（时间维度）；
 *   - 本模块看"钱花给谁"（消费对象维度）。
 *
 * 设计要点：
 *   1. 只分析目标月份本身（当月 1 日 ~ 月末），不读取历史月份；
 *   2. **一次**查询：复用 BillMapper#selectExpenseDetails（带 start / end / limit），
 *      商户归一化、聚合、排序、指标计算全部在内存完成，不新增 Mapper 方法；
 *   3. 商户清洗只做三件事：trim、去掉连续空格、统一大小写。
 *      **不剥离"店 / 旗舰店 / 有限公司"等后缀、不做任何同义词合并**，避免把不同门店错误合并；
 *   4. 只统计 type=1（支出）且金额大于 0 的记录；
 *   5. 消费天数或交易对象信息不足时不给排行结论，只返回事实数据。
 */
@Service
public class SpendingMerchantService {

    /** 有支出记录的最少天数：少于 3 天不足以判断消费对象结构 */
    static final int MIN_COVERED_DAYS = 3;

    /** 有效消费对象的最少数量 */
    static final int MIN_MERCHANT_COUNT = 2;

    /** 交易对象覆盖率下限（%）：低于该值说明用户基本不填写交易对象 */
    static final BigDecimal MIN_MERCHANT_COVERAGE = new BigDecimal("50");

    /** 明细查询上限，兜住极端高频用户 */
    static final int MAX_DETAIL_ROWS = 2000;

    /** 排行返回上限 */
    static final int TOP_MERCHANT_LIMIT = 5;

    /** 集中度统计的 Top 数量 */
    static final int CONCENTRATION_SIZE = 3;

    static final String STATUS_OK = "OK";
    static final String STATUS_INSUFFICIENT_DATA = "INSUFFICIENT_DATA";
    static final String STATUS_NO_DATA = "NO_DATA";
    static final String STATUS_NOT_APPLICABLE = "NOT_APPLICABLE";

    private final BillMapper billMapper;
    private final Clock clock;

    public SpendingMerchantService(BillMapper billMapper, Clock clock) {
        this.billMapper = billMapper;
        this.clock = clock;
    }

    public SpendingMerchantResponse analyze(Long userId, String month) {
        YearMonth target = Months.parse(month);

        // 过去与未来月份都不做分析：与 Stage 4-A / 4-D / 4-E 的 NOT_APPLICABLE 约定保持一致
        if (!target.equals(YearMonth.now(clock))) {
            return respond(target, STATUS_NOT_APPLICABLE, "消费对象分析只对当前月份有效",
                    BigDecimal.ZERO, 0, 0, "0.00", BigDecimal.ZERO, "0.00", "0.00", "", List.of());
        }

        // 一次查询：当月支出明细（含交易对象），聚合与指标计算全部在内存完成
        List<ExpenseDetail> details = billMapper.selectExpenseDetails(userId,
                BillType.EXPENSE.getCode(), target.atDay(1), target.atEndOfMonth(), MAX_DETAIL_ROWS);

        Map<String, MerchantBucket> buckets = new LinkedHashMap<>();
        Set<LocalDate> coveredDays = new HashSet<>();
        BigDecimal totalAmount = BigDecimal.ZERO;
        int totalCount = 0;
        int unknownCount = 0;
        BigDecimal unknownAmount = BigDecimal.ZERO;

        for (ExpenseDetail detail : details) {
            if (detail == null || detail.getAmount() == null || detail.getAmount().signum() <= 0) {
                continue;
            }
            BigDecimal amount = detail.getAmount();
            totalAmount = totalAmount.add(amount);
            totalCount++;
            if (detail.getBillDate() != null) {
                coveredDays.add(detail.getBillDate());
            }
            String key = normalizeKey(detail.getMerchant());
            if (key.isEmpty()) {
                // 未填写交易对象：单独统计，不能混进任何商户
                unknownCount++;
                unknownAmount = unknownAmount.add(amount);
                continue;
            }
            buckets.computeIfAbsent(key, ignored -> new MerchantBucket(displayName(detail.getMerchant())))
                    .add(amount);
        }

        if (totalAmount.signum() == 0) {
            return respond(target, STATUS_NO_DATA, "当月还没有支出记录",
                    BigDecimal.ZERO, 0, 0, "0.00", BigDecimal.ZERO, "0.00", "0.00", "", List.of());
        }

        String coverage = percentage(BigDecimal.valueOf(totalCount - unknownCount),
                BigDecimal.valueOf(totalCount));
        String unknownRate = percentage(unknownAmount, totalAmount);
        if (coveredDays.size() < MIN_COVERED_DAYS || buckets.size() < MIN_MERCHANT_COUNT
                || new BigDecimal(coverage).compareTo(MIN_MERCHANT_COVERAGE) < 0) {
            return respond(target, STATUS_INSUFFICIENT_DATA,
                    "当月消费天数或交易对象信息不足，暂时无法分析消费对象",
                    totalAmount, totalCount, buckets.size(), coverage, unknownAmount, unknownRate,
                    "0.00", "", List.of());
        }

        List<MerchantBucket> sorted = new ArrayList<>(buckets.values());
        sorted.sort(SpendingMerchantService::compareBucket);

        List<MerchantSpendingItem> topMerchants = new ArrayList<>(TOP_MERCHANT_LIMIT);
        BigDecimal topAmount = BigDecimal.ZERO;
        for (int i = 0; i < sorted.size(); i++) {
            MerchantBucket bucket = sorted.get(i);
            if (i < CONCENTRATION_SIZE) {
                topAmount = topAmount.add(bucket.amount());
            }
            if (i < TOP_MERCHANT_LIMIT) {
                topMerchants.add(new MerchantSpendingItem(bucket.name(), money(bucket.amount()),
                        bucket.count(), percentage(bucket.amount(), totalAmount)));
            }
        }

        String concentration = percentage(topAmount, totalAmount);
        String summary = summary(Math.min(CONCENTRATION_SIZE, sorted.size()), concentration,
                unknownAmount, unknownRate);
        String message = "已分析 " + target + " 的消费对象：" + sorted.size() + " 个交易对象，共 "
                + totalCount + " 笔支出";

        return respond(target, STATUS_OK, message, totalAmount, totalCount, sorted.size(), coverage,
                unknownAmount, unknownRate, concentration, summary, topMerchants);
    }

    /**
     * 排序规则固定为：金额降序 → 笔数降序 → 名称字典序升序。
     * 三条规则一起保证同一份数据的结果稳定（可测试）。
     */
    private static int compareBucket(MerchantBucket left, MerchantBucket right) {
        int byAmount = right.amount().compareTo(left.amount());
        if (byAmount != 0) {
            return byAmount;
        }
        int byCount = Integer.compare(right.count(), left.count());
        if (byCount != 0) {
            return byCount;
        }
        return left.name().compareTo(right.name());
    }

    /**
     * 商户分组键：trim → 去掉连续空格 → 统一小写。
     * 只做这三件事，**不剥离后缀、不做同义词合并**，避免把不同门店错误合并成一个对象。
     */
    static String normalizeKey(String merchant) {
        return displayName(merchant).toLowerCase(Locale.ROOT);
    }

    /**
     * 展示名：只做 trim 与连续空格压缩，保留用户自己写的大小写
     * （避免把英文商户名统一显示成小写）；大小写差异通过分组键合并。
     */
    static String displayName(String merchant) {
        if (merchant == null) {
            return "";
        }
        return merchant.trim().replaceAll("\\s+", " ");
    }

    /** 一句话结论：集中度 + 未填写交易对象的提示（数据质量） */
    private static String summary(int topSize, String concentration, BigDecimal unknownAmount,
                                  String unknownRate) {
        StringBuilder summary = new StringBuilder("支出主要集中在 ")
                .append(topSize).append(" 个消费对象，合计占 ").append(concentration).append("%");
        if (unknownAmount.signum() > 0) {
            summary.append("；另有 ").append(unknownRate).append("% 的支出未填写交易对象");
        }
        return summary.toString();
    }

    private SpendingMerchantResponse respond(YearMonth target, String status, String message,
                                             BigDecimal totalAmount, int totalCount, int merchantCount,
                                             String coverage, BigDecimal unknownAmount,
                                             String unknownRate, String concentration, String summary,
                                             List<MerchantSpendingItem> topMerchants) {
        return new SpendingMerchantResponse(target.toString(), status, message, money(totalAmount),
                totalCount, averageAmount(totalAmount, totalCount), merchantCount, coverage,
                money(unknownAmount), unknownRate, concentration, summary, topMerchants);
    }

    /** 整体客单价 = 支出合计 ÷ 笔数；没有笔数时返回 0.00 */
    static String averageAmount(BigDecimal totalAmount, int totalCount) {
        if (totalCount <= 0) {
            return "0.00";
        }
        return money(totalAmount.divide(BigDecimal.valueOf(totalCount), 2, RoundingMode.HALF_UP));
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

    /** 一个消费对象的聚合结果 */
    private static final class MerchantBucket {

        private final String name;
        private BigDecimal amount = BigDecimal.ZERO;
        private int count;

        private MerchantBucket(String name) {
            this.name = name;
        }

        private void add(BigDecimal value) {
            amount = amount.add(value);
            count++;
        }

        private String name() {
            return name;
        }

        private BigDecimal amount() {
            return amount;
        }

        private int count() {
            return count;
        }
    }
}
