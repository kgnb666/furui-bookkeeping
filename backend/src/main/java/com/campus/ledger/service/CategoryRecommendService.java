package com.campus.ledger.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.common.Category;
import com.campus.ledger.dto.CategoryRecommendResponse;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 个性化分类推荐：用「用户自己的历史账单」+「内置关键词规则」给候选分类打分。
 *
 * 设计原则：
 *   1. 只读，绝不修改账单；推荐结果必须由用户确认后才会写入；
 *   2. 每条推荐都给得出原因（reason），没有依据就不给推荐；
 *   3. 查询只取当前用户最近若干条账单，带 user_id 与索引条件，不做全表扫描；
 *   4. 用户最近的分类选择优先于历史习惯（偏好覆盖），否则改了分类也不会生效。
 */
@Service
public class CategoryRecommendService {

    /** 参与打分的历史账单条数上限，避免随着数据增长越查越慢 */
    static final int HISTORY_LIMIT = 200;

    /** 近期加权窗口：最近多少天内的记录额外加分 */
    static final int RECENT_DAYS = 30;

    /** 偏好覆盖：最近 N 条里出现了 M 笔同一分类，直接以该分类为准 */
    static final int RECENT_WINDOW = 5;
    static final int RECENT_OVERRIDE_COUNT = 3;

    static final int SCORE_MERCHANT_EXACT = 100;
    static final int SCORE_NOTE_EXACT = 120;
    static final int SCORE_MERCHANT_CONTAINS = 70;
    static final int SCORE_NOTE_CONTAINS = 40;
    static final int SCORE_KEYWORD = 30;
    static final int SCORE_RECENT_BONUS = 15;
    static final int SCORE_CONSISTENCY_BONUS = 10;

    private final BillMapper billMapper;
    private final CategoryMatcher categoryMatcher;

    public CategoryRecommendService(BillMapper billMapper, CategoryMatcher categoryMatcher) {
        this.billMapper = billMapper;
        this.categoryMatcher = categoryMatcher;
    }

    public CategoryRecommendResponse recommend(Long userId, String merchant, String note, String type) {
        BillType billType = BillType.parse(type);
        if (billType == null) {
            throw new BizException(400, "收支类型只能是 1(支出)/2(收入)/3(不计收支)");
        }
        String merchantText = normalize(merchant);
        String noteText = normalize(note);
        List<Bill> history = recentHistory(userId, billType);
        return score(billType, merchantText, noteText, history);

    }

    /** 只取当前用户、当前收支类型最近的若干条账单；走 (user_id, type, bill_date) 索引 */
    private List<Bill> recentHistory(Long userId, BillType billType) {
        return billMapper.selectList(new LambdaQueryWrapper<Bill>()
                .eq(Bill::getUserId, userId)
                .eq(Bill::getType, billType.getCode())
                .orderByDesc(Bill::getBillDate)
                .orderByDesc(Bill::getId)
                .last("LIMIT " + HISTORY_LIMIT));
    }

    /**
     * 打分主流程，抽成包级可见方法便于单元测试直接验证算法。
     */
    CategoryRecommendResponse score(BillType billType, String merchant, String note, List<Bill> history) {
        if (merchant.isEmpty() && note.isEmpty()) {
            return CategoryRecommendResponse.none();
        }

        Map<String, Integer> scores = new HashMap<>();
        Map<String, Integer> samples = new HashMap<>();
        Map<String, Integer> recentHits = new HashMap<>();
        LocalDate recentLine = LocalDate.now().minusDays(RECENT_DAYS);

        // 显式按日期倒序排列：算法需要"最近的记录排在最前"，
        // 不能依赖上层查询是否带了 ORDER BY，否则偏好覆盖会失效。
        List<Bill> ordered = new ArrayList<>(history);
        ordered.sort(Comparator
                .comparing(Bill::getBillDate, Comparator.nullsLast(Comparator.reverseOrder()))
                .thenComparing(Bill::getId, Comparator.nullsLast(Comparator.reverseOrder())));

        for (int i = 0; i < ordered.size(); i++) {
            Bill bill = ordered.get(i);
            String category = normalize(bill.getCategory());
            if (category.isEmpty()) {
                continue;
            }
            int weight = similarity(bill, merchant, note);
            if (weight == 0) {
                continue;
            }
            // 最近的记录权重更高：相同匹配下，越靠前的记录分越多
            if (bill.getBillDate() != null && !bill.getBillDate().isBefore(recentLine)) {
                weight += SCORE_RECENT_BONUS;
            }
            scores.merge(category, weight, Integer::sum);
            samples.merge(category, 1, Integer::sum);
            if (i < RECENT_WINDOW) {
                recentHits.merge(category, 1, Integer::sum);
            }
        }

        // 用户最近连续把同一商户归到某个分类，说明偏好已经变了，以最近的为准
        // 注意：这里必须挑"最近命中次数最多"的分类，不能取哈希表里的第一个，
        // 否则多分类并存时结果会不确定。
        int best = -1;
        String overrideCategory = null;
        for (Map.Entry<String, Integer> entry : recentHits.entrySet()) {
            if (entry.getValue() < RECENT_OVERRIDE_COUNT) {
                continue;
            }
            if (overrideCategory == null
                    || entry.getValue() > recentHits.getOrDefault(overrideCategory, 0)) {
                overrideCategory = entry.getKey();
            }
        }
        boolean override = overrideCategory != null;
        if (override) {
            best = scores.getOrDefault(overrideCategory, 0);
        }

        if (!override) {
            // 加上"多次一致"的额外可信度，再取最高分
            for (Map.Entry<String, Integer> entry : new LinkedHashMap<>(scores).entrySet()) {
                int count = samples.getOrDefault(entry.getKey(), 0);
                if (count >= 3) {
                    scores.merge(entry.getKey(), SCORE_CONSISTENCY_BONUS, Integer::sum);
                }
            }
            for (Map.Entry<String, Integer> entry : scores.entrySet()) {
                if (entry.getValue() > best) {
                    best = entry.getValue();
                }
            }
        }

        String category = override ? overrideCategory : winner(scores, best, samples);

        // 历史里没有可用的匹配时，退回内置关键词规则
        if (category == null) {
            String ruleCategory = keywordCategory(billType, merchant, note);
            if (ruleCategory != null) {
                return new CategoryRecommendResponse(ruleCategory, "LOW", SCORE_KEYWORD,
                        "“" + (merchant.isEmpty() ? note : merchant) + "”符合内置分类关键词", 0);
            }
            return CategoryRecommendResponse.none();
        }

        int count = samples.getOrDefault(category, 0);
        String confidence = count >= 3 ? "HIGH" : count == 2 ? "MEDIUM" : "LOW";
        String reason;
        if (override) {
            // 偏好覆盖时明确说明依据的是最近的分类习惯，用户能自己核对
            reason = "根据你最近 " + recentHits.getOrDefault(category, 0) + " 次对该商户的分类习惯";
        } else if (count > 0) {
            reason = "根据你过去 " + count + " 次对该商户的记录";
        } else {
            reason = "该商户与你的历史记录相似";
        }
        return new CategoryRecommendResponse(category, confidence, best, reason, count);
    }

    /** 取最高分对应的分类；分数相同时取记录更多的那个 */
    private String winner(Map<String, Integer> scores, int best, Map<String, Integer> samples) {
        if (best <= 0) {
            return null;
        }
        String winner = null;
        int winnerSamples = -1;
        for (Map.Entry<String, Integer> entry : scores.entrySet()) {
            if (entry.getValue() != best) {
                continue;
            }
            int count = samples.getOrDefault(entry.getKey(), 0);
            if (count > winnerSamples) {
                winner = entry.getKey();
                winnerSamples = count;
            }
        }
        return winner;
    }

    /** 与历史账单的相似度：完全相同 > 互相包含 > 备注包含 */
    private int similarity(Bill bill, String merchant, String note) {
        String historyMerchant = normalize(bill.getMerchant());
        String historyNote = normalize(bill.getRemark());
        int best = 0;

        if (!merchant.isEmpty() && !historyMerchant.isEmpty()) {
            if (merchant.equals(historyMerchant)) {
                best = SCORE_MERCHANT_EXACT;
            } else if (merchant.contains(historyMerchant) || historyMerchant.contains(merchant)) {
                best = SCORE_MERCHANT_CONTAINS;
            }
        }
        if (!note.isEmpty() && !historyNote.isEmpty()) {
            int noteScore;
            if (note.equals(historyNote)) {
                noteScore = SCORE_NOTE_EXACT;
            } else if (note.contains(historyNote) || historyNote.contains(note)) {
                noteScore = SCORE_NOTE_CONTAINS;
            } else {
                noteScore = 0;
            }
            best = Math.max(best, noteScore);
        }
        return best;
    }

    /** 内置关键词规则兜底，结果只标为 LOW，只能作为建议 */
    private String keywordCategory(BillType billType, String merchant, String note) {
        if (merchant.isEmpty() && note.isEmpty()) {
            return null;
        }
        CategoryMatcher.Matched matched = categoryMatcher.match(billType, merchant, note, "");
        // DEFAULT 表示没命中任何关键词，不能当成推荐依据
        if (!"KEYWORD".equals(matched.from())) {
            return null;
        }
        return Category.isValid(billType, matched.category()) ? matched.category() : null;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim();
    }
}
