package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.dto.BudgetItemResponse;
import com.campus.ledger.dto.BudgetResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.Insight;
import com.campus.ledger.dto.MonthlyInsightsResponse;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.entity.Bill;
import com.campus.ledger.mapper.BillMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class InsightsServiceTest {

    private static final Long USER_ID = 5L;

    @Mock
    private BillMapper billMapper;

    @Mock
    private BudgetService budgetService;

    private InsightsService insightsService;

    @BeforeEach
    void setUp() {
        insightsService = new InsightsService(billMapper, budgetService);
        // 默认没有预算，避免影响与预算无关的用例
        when(budgetService.list(any(), anyString()))
                .thenReturn(new BudgetResponse("2026-09", "0.00", null, List.of()));
    }

    @Test
    void 月度洞察给出收支结余与摘要() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "600.00"), typeSum(BillType.INCOME, "1500.00")))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "500.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "600.00")))
                .thenReturn(List.of(categorySum("餐饮", "500.00")));

        MonthlyInsightsResponse response = insightsService.monthly(USER_ID, "2026-09");

        assertEquals("2026-09", response.getMonth());
        assertEquals("600.00", response.getExpense());
        assertEquals("1500.00", response.getIncome());
        assertEquals("900.00", response.getBalance());
        assertEquals("20.00", response.getExpenseChangePercent());
        assertEquals("餐饮", response.getTopCategory());
        assertEquals("100.00", response.getTopCategoryPercent());
        assertTrue(response.getSummary().contains("餐饮是主要支出类别"), response.getSummary());
    }

    @Test
    void 本月支出增加时生成增加提示() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "1200.00")))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "1000.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        Insight change = find(insights, "SPENDING_CHANGE");
        assertNotNull(change, "应当给出整体消费变化");
        assertTrue(change.getMessage().contains("增加 200.00"), change.getMessage());
    }

    @Test
    void 本月支出减少时生成减少提示() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "800.00")))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "1000.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        Insight change = find(insights, "SPENDING_CHANGE");
        assertNotNull(change);
        assertTrue(change.getMessage().contains("减少 200.00"), change.getMessage());
    }

    @Test
    void 分类占比超过百分之三十时提示消费重点() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "1000.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "450.00"), categorySum("交通", "550.00")));

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        Insight focus = find(insights, "CATEGORY_FOCUS");
        assertNotNull(focus, "占比超过 30% 应当触发消费重点");
        assertTrue(focus.getMessage().contains("45"), focus.getMessage());
    }

    @Test
    void 分类环比增长超过百分之二十时提示() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "700.00")))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "500.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("娱乐", "300.00"), categorySum("餐饮", "400.00")))
                .thenReturn(List.of(categorySum("娱乐", "100.00"), categorySum("餐饮", "400.00")));

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        Insight growth = find(insights, "CATEGORY_GROWTH");
        assertNotNull(growth, "娱乐从 100 涨到 300，应当提示");
        assertTrue(growth.getMessage().contains("娱乐"), growth.getMessage());
        assertTrue(growth.getMessage().contains("200"), growth.getMessage());
    }

    @Test
    void 上月没有数据时不生成环比提示() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "300.00")))
                .thenReturn(List.of());
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "300.00")))
                .thenReturn(List.of());

        MonthlyInsightsResponse response = insightsService.monthly(USER_ID, "2026-09");

        assertNull(response.getExpenseChangePercent());
        assertNull(find(response.getInsights(), "SPENDING_CHANGE"));
        assertNull(find(response.getInsights(), "CATEGORY_GROWTH"));
    }

    @Test
    void 预算使用达到百分之八十时提醒() {
        BudgetItemResponse item = budgetItem("餐饮", "430.00", "500.00", new BigDecimal("86.00"));
        when(budgetService.list(any(), anyString()))
                .thenReturn(new BudgetResponse("2026-09", "430.00", null, List.of(item)));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "430.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "430.00")));

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        Insight budget = find(insights, "BUDGET_WARNING");
        assertNotNull(budget);
        assertTrue(budget.getMessage().contains("餐饮"), budget.getMessage());
        assertTrue(budget.getMessage().contains("86"), budget.getMessage());
    }

    @Test
    void 预算超支时给出超支提示且优先级最高() {
        BudgetItemResponse item = budgetItem("餐饮", "300.00", "200.00", new BigDecimal("150.00"));
        when(budgetService.list(any(), anyString()))
                .thenReturn(new BudgetResponse("2026-09", "300.00", null, List.of(item)));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "300.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "300.00")));

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        assertEquals("BUDGET_OVER", insights.get(0).getType(), "超支提醒必须排在最前面");
        assertTrue(insights.get(0).getMessage().contains("超过本月预算"), insights.get(0).getMessage());
    }

    @Test
    void 预算未达到提醒线时不提示() {
        BudgetItemResponse item = budgetItem("餐饮", "100.00", "1000.00", new BigDecimal("10.00"));
        when(budgetService.list(any(), anyString()))
                .thenReturn(new BudgetResponse("2026-09", "100.00", null, List.of(item)));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "100.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "100.00")));

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        assertNull(find(insights, "BUDGET_WARNING"));
        assertNull(find(insights, "BUDGET_OVER"));
    }

    @Test
    void 最多只返回五条洞察() {
        List<BudgetItemResponse> items = new ArrayList<>();
        for (int i = 0; i < 6; i++) {
            items.add(budgetItem("分类" + i, "120.00", "100.00", new BigDecimal("120.00")));
        }
        when(budgetService.list(any(), anyString()))
                .thenReturn(new BudgetResponse("2026-09", "720.00", null, items));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "720.00")));
        when(billMapper.sumByCategory(any(), any(), any()))
                .thenReturn(List.of(categorySum("餐饮", "720.00")));

        List<Insight> insights = insightsService.monthly(USER_ID, "2026-09").getInsights();

        assertEquals(InsightsService.MAX_INSIGHTS, insights.size());
    }

    @Test
    void 没有任何账单时返回空洞察与友好摘要() {
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        MonthlyInsightsResponse response = insightsService.monthly(USER_ID, "2026-09");

        assertEquals("0.00", response.getExpense());
        assertTrue(response.getInsights().isEmpty());
        assertNull(response.getTopCategory());
        assertEquals("本月还没有支出记录", response.getSummary());
    }

    @Test
    void 跨年月份的上月是去年十二月() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "200.00")))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "100.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        MonthlyInsightsResponse response = insightsService.monthly(USER_ID, "2027-01");

        assertEquals("2027-01", response.getMonth());
        assertEquals("100.00", response.getExpenseChangePercent());
    }

    private Insight find(List<Insight> insights, String type) {
        return insights.stream().filter(item -> type.equals(item.getType())).findFirst().orElse(null);
    }

    private TypeSum typeSum(BillType type, String amount) {
        TypeSum sum = new TypeSum();
        sum.setType(type.getCode());
        sum.setAmount(new BigDecimal(amount));
        return sum;
    }

    private CategorySum categorySum(String category, String amount) {
        CategorySum sum = new CategorySum();
        sum.setCategory(category);
        sum.setAmount(new BigDecimal(amount));
        return sum;
    }

    private BudgetItemResponse budgetItem(String category, String used, String amount, BigDecimal rate) {
        // 直接复用线上的预算计算逻辑，避免测试里自己造一个和线上不一致的响应
        BillSample sample = new BillSample();
        return BudgetItemResponse.of(sample.budget(category, amount), new BigDecimal(used));
    }

    /** 构造预算实体的小工具 */
    private static class BillSample {
        com.campus.ledger.entity.Budget budget(String category, String amount) {
            com.campus.ledger.entity.Budget budget = new com.campus.ledger.entity.Budget();
            budget.setId(1L);
            budget.setUserId(USER_ID);
            budget.setMonth("2026-09");
            budget.setCategory(category);
            budget.setAmount(new BigDecimal(amount));
            return budget;
        }
    }

    private Bill expense(String merchant, String category, String amount, LocalDate date) {
        Bill bill = new Bill();
        bill.setType(BillType.EXPENSE.getCode());
        bill.setAmount(new BigDecimal(amount));
        bill.setCategory(category);
        bill.setBillDate(date);
        bill.setMerchant(merchant);
        bill.setRemark("");
        return bill;
    }
}
