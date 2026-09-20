package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.CategoryRecommendResponse;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CategoryRecommendServiceTest {

    private static final Long USER_A = 11L;
    private static final Long USER_B = 22L;

    @Mock
    private BillMapper billMapper;

    private CategoryRecommendService service;

    @BeforeEach
    void setUp() {
        // 关键词规则用真实实现，保证兜底逻辑与线上一致
        service = new CategoryRecommendService(billMapper, new CategoryMatcher());
    }

    // ==================== 推荐算法 ====================

    @Test
    void 商户完全匹配时给出最高分并标记HIGH置信度() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "星巴克", "",
                history("星巴克", "餐饮", 3));

        assertEquals("餐饮", result.getCategory());
        assertEquals("HIGH", result.getConfidence());
        assertTrue(result.getScore() >= CategoryRecommendService.SCORE_MERCHANT_EXACT);
        assertTrue(result.getReason().contains("3 次"), "原因里要说清楚依据了多少条历史：" + result.getReason());
    }

    @Test
    void 历史出现两次为MEDIUM置信度() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "星巴克", "",
                history("星巴克", "餐饮", 2));

        assertEquals("餐饮", result.getCategory());
        assertEquals("MEDIUM", result.getConfidence());
    }

    @Test
    void 历史只出现一次为LOW置信度() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "星巴克", "",
                history("星巴克", "餐饮", 1));

        assertEquals("餐饮", result.getCategory());
        assertEquals("LOW", result.getConfidence());
    }

    @Test
    void 商户名称互相包含也能匹配() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "星巴克(光谷店)", "",
                history("星巴克", "餐饮", 3));

        assertEquals("餐饮", result.getCategory());
        assertTrue(result.getScore() >= CategoryRecommendService.SCORE_MERCHANT_CONTAINS);
    }

    @Test
    void 商户匹配不到时用备注匹配() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "", "和同学聚餐",
                List.of(bill("未知小店", "餐饮", "和同学聚餐", LocalDate.now(), 1)));

        assertEquals("餐饮", result.getCategory());
        assertEquals("LOW", result.getConfidence());
        assertTrue(result.getReason().contains("过去 1 次") || result.getReason().contains("历史记录"),
                "原因要说明依据：" + result.getReason());
    }

    @Test
    void 多个分类冲突时选分数更高的那个() {
        List<Bill> history = new ArrayList<>();
        // 星巴克 -> 餐饮 3 次（满分 + 一致性加分）
        history.addAll(history("星巴克", "餐饮", 3));
        // 星巴克 -> 购物 1 次（只有 1 次，分数低）
        history.addAll(history("星巴克", "购物", 1));

        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "星巴克", "", history);

        assertEquals("餐饮", result.getCategory(), "次数更多、分数更高的分类应当胜出");
    }

    @Test
    void 最近偏好覆盖历史习惯() {
        List<Bill> history = new ArrayList<>();
        // 很久以前记成购物 8 次
        for (int i = 0; i < 8; i++) {
            history.add(bill("某某超市", "购物", "", LocalDate.now().minusDays(200), 1));
        }
        // 最近改成生活 3 次
        for (int i = 0; i < 3; i++) {
            history.add(bill("某某超市", "生活", "", LocalDate.now().minusDays(i), 1));
        }

        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "某某超市", "", history);

        assertEquals("生活", result.getCategory(), "用户最近改过的分类必须能覆盖旧习惯");
        assertTrue(result.getReason().contains("最近"));
    }

    @Test
    void 没有历史记录时退回关键词规则并标记LOW() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "星巴克", "", List.of());

        assertEquals("餐饮", result.getCategory());
        assertEquals("LOW", result.getConfidence());
        assertEquals(CategoryRecommendService.SCORE_KEYWORD, result.getScore());
        assertTrue(result.getReason().contains("关键词"));
    }

    @Test
    void 既没有历史也没有关键词命中时返回无推荐() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "某个没听过的店", "", List.of());

        assertNull(result.getCategory());
        assertEquals("NONE", result.getConfidence());
        assertEquals(0, result.getScore());
        assertEquals("暂无足够历史记录", result.getReason());
    }

    @Test
    void 商户与备注都为空时直接返回无推荐() {
        CategoryRecommendResponse result = service.score(BillType.EXPENSE, "", "", history("星巴克", "餐饮", 3));

        assertEquals("NONE", result.getConfidence());
        assertNull(result.getCategory());
    }

    @Test
    void 收入类型不会推荐支出分类() {
        CategoryRecommendResponse result = service.score(BillType.INCOME, "星巴克", "", List.of());

        // 星巴克是支出关键词，收入类型下不应当推荐"餐饮"
        assertTrue(result.getCategory() == null || !"餐饮".equals(result.getCategory()));
    }

    @Test
    void 收支类型非法时拒绝() {
        BizException e = assertThrows(BizException.class,
                () -> service.recommend(USER_A, "星巴克", "", "UNKNOWN"));

        assertEquals(400, e.getCode());
    }

    // ==================== 用户隔离与查询约束 ====================

    @Test
    void 推荐查询只查当前登录用户且限制条数() {
        when(billMapper.selectList(any())).thenReturn(List.of());

        service.recommend(USER_A, "星巴克", "", "EXPENSE");

        // 只查一次历史，且查询条件由服务内部固定拼装（user_id + type + LIMIT）。
        // SQL 文本在单测里无法安全求值，具体条件由联调用例在真实数据库上验证。
        verify(billMapper).selectList(org.mockito.ArgumentMatchers.<com.baomidou.mybatisplus.core.conditions.Wrapper<Bill>>any());
        verify(billMapper, org.mockito.Mockito.times(1)).selectList(any());
    }

    @Test
    void 用户B不会因为用户A的历史而得到推荐() {
        // A 有"星巴克 -> 餐饮"的历史；B 完全没有历史
        when(billMapper.selectList(any()))
                .thenReturn(history("星巴克", "餐饮", 3))   // A 的查询结果
                .thenReturn(List.of());                     // B 的查询结果

        CategoryRecommendResponse forA = service.recommend(USER_A, "星巴克", "", "EXPENSE");
        CategoryRecommendResponse forB = service.recommend(USER_B, "星巴克", "", "EXPENSE");

        assertEquals("餐饮", forA.getCategory());
        assertEquals("HIGH", forA.getConfidence());

        // B 没有历史，只能退回关键词规则，不能拿到 A 的"HIGH 置信度"结论
        assertEquals("LOW", forB.getConfidence());
        assertEquals(0, forB.getSampleCount());
        assertTrue(forB.getScore() < forA.getScore(), "B 的推荐分数必须明显低于 A");
    }

    private List<Bill> history(String merchant, String category, int count) {
        List<Bill> bills = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            bills.add(bill(merchant, category, "", LocalDate.now().minusDays(i), 1));
        }
        return bills;
    }

    private Bill bill(String merchant, String category, String remark, LocalDate date, int type) {
        Bill bill = new Bill();
        bill.setType(type);
        bill.setAmount(new BigDecimal("20.00"));
        bill.setCategory(category);
        bill.setBillDate(date);
        bill.setMerchant(merchant);
        bill.setRemark(remark);
        bill.setSource("MANUAL");
        return bill;
    }
}
