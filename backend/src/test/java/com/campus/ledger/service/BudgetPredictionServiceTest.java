package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.BudgetPredictionItem;
import com.campus.ledger.dto.BudgetPredictionResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.CategoryDailySum;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.entity.Budget;
import com.campus.ledger.mapper.BillMapper;
import com.campus.ledger.mapper.BudgetMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 预算预测算法测试。时间固定在 2026-09-16，所有期望值都可以按算式手工复核：
 * 日均 = 已支出 / 16，月末预测 = 日均 × 30。
 */
@ExtendWith(MockitoExtension.class)
class BudgetPredictionServiceTest {

    private static final Long USER_ID = 9L;
    private static final String MONTH = "2026-09";
    /** 2026-09-16，当月共 30 天，已过 16 天 */
    private static final Clock FIXED = Clock.fixed(
            Instant.parse("2026-09-16T04:00:00Z"), ZoneId.of("Asia/Shanghai"));

    @Mock
    private BudgetMapper budgetMapper;

    @Mock
    private BillMapper billMapper;

    private BudgetPredictionService service;

    @BeforeEach
    void setUp() {
        service = new BudgetPredictionService(budgetMapper, billMapper, FIXED);
    }

    // ==================== 正常预算 ====================

    @Test
    void 消费节奏正常时预测不会超支() {
        stub(budgets(total(1000)), dailySums(daily(1, "10.00"), daily(2, "10.00"), daily(3, "10.00")),
                List.of());

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertEquals("OK", response.getStatus());
        assertEquals(16, response.getElapsedDays());
        assertEquals(30, response.getDaysInMonth());
        assertEquals(14, response.getDaysLeft());

        BudgetPredictionItem item = response.getItems().get(0);
        assertTrue(item.isTotal());
        assertEquals("30.00", item.getSpent());
        assertEquals(3, item.getSpentDays());
        assertEquals("1.88", item.getDailyAverage());
        assertEquals("56.40", item.getProjected());
        assertEquals("0.00", item.getProjectedOver());
        assertEquals("5.64", item.getProjectedUsageRate());
        assertEquals("SAFE", item.getRiskLevel());
        assertNull(item.getOverDate());
        assertTrue(item.getMessage().contains("预计不会超出预算"), item.getMessage());
    }

    // ==================== 超预算预测 ====================

    @Test
    void 预测超支时给出超支金额与风险等级() {
        stub(budgets(total(600)), dailySums(daily(1, "160.00"), daily(2, "160.00"), daily(3, "160.00"),
                daily(4, "160.00")), List.of());

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        BudgetPredictionItem item = response.getItems().get(0);
        assertEquals("640.00", item.getSpent());
        assertEquals("40.00", item.getDailyAverage());
        assertEquals("1200.00", item.getProjected());
        assertEquals("600.00", item.getProjectedOver());
        assertEquals("200.00", item.getProjectedUsageRate());
        assertEquals("OVER", item.getRiskLevel());
        assertEquals("2026-09-15", item.getOverDate());
        assertTrue(response.getMessage().contains("预计超出 ¥600.00"), response.getMessage());
        assertTrue(response.getMessage().contains("2026-09-15"), response.getMessage());
    }

    @Test
    void 预计刚好超出一点时为HIGH() {
        stub(budgets(total(1000)), dailySums(daily(1, "181.34"), daily(2, "181.33"), daily(3, "181.33")),
                List.of());

        BudgetPredictionItem item = service.predict(USER_ID, MONTH).getItems().get(0);

        // 已支出 544，日均 34.00，月末 1020.00
        assertEquals("34.00", item.getDailyAverage());
        assertEquals("1020.00", item.getProjected());
        assertEquals("20.00", item.getProjectedOver());
        assertEquals("102.00", item.getProjectedUsageRate());
        assertEquals("HIGH", item.getRiskLevel());
    }

    @Test
    void 预测使用率接近预算时为MEDIUM() {
        stub(budgets(total(1000)), dailySums(daily(1, "160.00"), daily(2, "160.00"), daily(3, "160.00")),
                List.of());

        BudgetPredictionItem item = service.predict(USER_ID, MONTH).getItems().get(0);

        // 已支出 480，日均 30.00，月末 900.00
        assertEquals("900.00", item.getProjected());
        assertEquals("90.00", item.getProjectedUsageRate());
        assertEquals("MEDIUM", item.getRiskLevel());
        assertEquals("0.00", item.getProjectedOver());
    }

    @Test
    void 预测使用率偏低时为LOW() {
        stub(budgets(total(1000)), dailySums(daily(1, "133.34"), daily(2, "133.33"), daily(3, "133.33")),
                List.of());

        BudgetPredictionItem item = service.predict(USER_ID, MONTH).getItems().get(0);

        // 已支出 400，日均 25.00，月末 750.00
        assertEquals("25.00", item.getDailyAverage());
        assertEquals("75.00", item.getProjectedUsageRate());
        assertEquals("LOW", item.getRiskLevel());
    }

    // ==================== 无预算 ====================

    @Test
    void 当月没有预算时返回空列表与引导文案() {
        when(budgetMapper.selectList(any())).thenReturn(List.of());

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertEquals("NO_BUDGET", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertTrue(response.getMessage().contains("还没有设置预算"), response.getMessage());
        verify(billMapper, times(0)).sumByDay(any(), any(), any());
    }

    // ==================== 无消费与数据不足 ====================

    @Test
    void 有预算但完全没有消费时返回数据不足() {
        stub(budgets(total(1000)), List.of(), List.of());

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        BudgetPredictionItem item = response.getItems().get(0);
        assertEquals("0.00", item.getSpent());
        assertEquals(0, item.getSpentDays());
        assertEquals("0.00", item.getProjected());
        assertEquals("0.00", item.getProjectedOver());
        assertEquals("INSUFFICIENT_DATA", item.getRiskLevel());
        assertNull(item.getOverDate());
        assertTrue(response.getMessage().contains("不足 3 天"), response.getMessage());
    }

    @Test
    void 消费天数只有两天时不生成预测结论() {
        stub(budgets(total(100)), dailySums(daily(1, "500.00"), daily(2, "500.00")), List.of());

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        BudgetPredictionItem item = response.getItems().get(0);
        assertEquals("1000.00", item.getSpent());
        assertEquals(2, item.getSpentDays());
        assertEquals("0.00", item.getProjected());
        assertEquals("INSUFFICIENT_DATA", item.getRiskLevel());
        assertEquals("已使用 1000.00 / 预算 100.00", item.getMessage());
    }

    @Test
    void 恰好三天时开始给出预测() {
        stub(budgets(total(100)), dailySums(daily(1, "50.00"), daily(2, "50.00"), daily(3, "50.00")),
                List.of());

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertEquals("OK", response.getStatus());
        BudgetPredictionItem item = response.getItems().get(0);
        assertEquals(3, item.getSpentDays());
        assertEquals("9.38", item.getDailyAverage());
        assertEquals("281.40", item.getProjected());
        assertEquals("181.40", item.getProjectedOver());
        assertEquals("OVER", item.getRiskLevel());
    }

    // ==================== 分类预算 ====================

    @Test
    void 同时返回总预算与分类预算的预测() {
        stub(budgets(total(1000), category("餐饮", 300), category("交通", 100)),
                dailySums(daily(1, "90.00"), daily(2, "90.00"), daily(3, "90.00")),
                List.of(categorySum("餐饮", "180.00"), categorySum("交通", "90.00")),
                List.of(categoryDaily("餐饮", 1, "60.00"), categoryDaily("餐饮", 2, "60.00"),
                        categoryDaily("餐饮", 3, "60.00"),
                        categoryDaily("交通", 1, "30.00"), categoryDaily("交通", 2, "30.00"),
                        categoryDaily("交通", 3, "30.00")));

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertEquals(3, response.getItems().size());

        BudgetPredictionItem totalItem = response.getItems().get(0);
        assertTrue(totalItem.isTotal());
        assertEquals("270.00", totalItem.getSpent());
        assertEquals("506.40", totalItem.getProjected());
        assertEquals("SAFE", totalItem.getRiskLevel());

        BudgetPredictionItem food = findItem(response, "餐饮");
        assertEquals("180.00", food.getSpent());
        assertEquals("11.25", food.getDailyAverage());
        assertEquals("337.50", food.getProjected());
        assertEquals("37.50", food.getProjectedOver());
        assertEquals("HIGH", food.getRiskLevel());
        assertEquals("2026-09-27", food.getOverDate());

        BudgetPredictionItem transport = findItem(response, "交通");
        assertEquals("90.00", transport.getSpent());
        assertEquals("168.90", transport.getProjected());
        assertEquals("OVER", transport.getRiskLevel());
    }

    @Test
    void 有预算但没有消费的分类按数据不足处理() {
        stub(budgets(category("娱乐", 200)),
                dailySums(daily(1, "50.00"), daily(2, "50.00"), daily(3, "50.00")),
                List.of(categorySum("餐饮", "150.00")),
                List.of(categoryDaily("餐饮", 1, "50.00"), categoryDaily("餐饮", 2, "50.00"),
                        categoryDaily("餐饮", 3, "50.00")));

        BudgetPredictionItem item = service.predict(USER_ID, MONTH).getItems().get(0);

        assertEquals("娱乐", item.getCategory());
        assertEquals("0.00", item.getSpent());
        assertEquals("0.00", item.getProjected());
        assertEquals("INSUFFICIENT_DATA", item.getRiskLevel());
        assertEquals("已使用 0.00 / 预算 200.00", item.getMessage());
    }

    @Test
    void 顶部说明优先提示风险最高的预算() {
        stub(budgets(total(1000), category("餐饮", 300)),
                dailySums(daily(1, "90.00"), daily(2, "90.00"), daily(3, "90.00")),
                List.of(categorySum("餐饮", "180.00")),
                List.of(categoryDaily("餐饮", 1, "60.00"), categoryDaily("餐饮", 2, "60.00"),
                        categoryDaily("餐饮", 3, "60.00")));

        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);

        assertTrue(response.getMessage().contains("餐饮"), response.getMessage());
        assertTrue(response.getMessage().contains("37.50"), response.getMessage());
    }

    // ==================== 跨月份与边界 ====================

    @Test
    void 过去的月份不做预测() {
        BudgetPredictionResponse response = service.predict(USER_ID, "2026-08");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertEquals(31, response.getDaysInMonth());
        assertEquals(0, response.getElapsedDays());
        assertTrue(response.getMessage().contains("仅支持预测本月"), response.getMessage());
        verify(budgetMapper, times(0)).selectList(any());
    }

    @Test
    void 未来的月份不做预测() {
        BudgetPredictionResponse response = service.predict(USER_ID, "2026-12");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertEquals(31, response.getDaysInMonth());
    }

    @Test
    void 跨年时按目标月份的天数计算() {
        Clock january = Clock.fixed(Instant.parse("2027-01-10T04:00:00Z"), ZoneId.of("Asia/Shanghai"));
        BudgetPredictionService januaryService =
                new BudgetPredictionService(budgetMapper, billMapper, january);
        when(budgetMapper.selectList(any())).thenReturn(List.of(total(1000)));
        when(billMapper.sumByDay(any(), any(), any())).thenReturn(
                dailySums(daily(1, "100.00"), daily(2, "100.00"), daily(3, "100.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());
        when(billMapper.sumByDayAndCategory(any(), any(), any())).thenReturn(List.of());

        BudgetPredictionItem item = januaryService.predict(USER_ID, "2027-01").getItems().get(0);

        assertEquals("930.00", item.getProjected());
    }

    @Test
    void 闰年二月按二十九天计算() {
        Clock leapFebruary = Clock.fixed(Instant.parse("2028-02-10T04:00:00Z"),
                ZoneId.of("Asia/Shanghai"));
        BudgetPredictionService februaryService =
                new BudgetPredictionService(budgetMapper, billMapper, leapFebruary);
        when(budgetMapper.selectList(any())).thenReturn(List.of(total(1000)));
        when(billMapper.sumByDay(any(), any(), any())).thenReturn(
                dailySums(daily(1, "100.00"), daily(2, "100.00"), daily(3, "100.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());
        when(billMapper.sumByDayAndCategory(any(), any(), any())).thenReturn(List.of());

        BudgetPredictionItem item = februaryService.predict(USER_ID, "2028-02").getItems().get(0);

        assertEquals("870.00", item.getProjected());
    }

    @Test
    void 月份格式不正确时返回参数错误() {
        BizException e = assertThrows(BizException.class, () -> service.predict(USER_ID, "2026-13-01"));

        assertEquals(400, e.getCode());
    }

    @Test
    void 月份为空时返回参数错误() {
        BizException e = assertThrows(BizException.class, () -> service.predict(USER_ID, null));

        assertEquals(400, e.getCode());
    }

    // ==================== 数据口径 ====================

    @Test
    void 收入与不计收支不计入消费天数与金额() {
        List<DailySum> sums = new ArrayList<>(dailySums(
                daily(1, "100.00"), daily(2, "100.00"), daily(3, "100.00")));
        sums.add(sum(1, 2, "5000.00"));
        sums.add(sum(2, 3, "2000.00"));
        stub(budgets(total(1000)), sums, List.of());

        BudgetPredictionItem item = service.predict(USER_ID, MONTH).getItems().get(0);

        assertEquals("300.00", item.getSpent(), "只有支出参与预测");
        assertEquals(3, item.getSpentDays());
    }

    @Test
    void 预测查询始终带当前登录用户() {
        stub(budgets(total(1000)), dailySums(daily(1, "50.00"), daily(2, "50.00"), daily(3, "50.00")),
                List.of());

        service.predict(USER_ID, MONTH);

        ArgumentCaptor<Long> userCaptor = ArgumentCaptor.forClass(Long.class);
        verify(billMapper).sumByDay(userCaptor.capture(), any(), any());
        assertEquals(USER_ID, userCaptor.getValue(), "按天聚合必须限定当前用户");
        verify(billMapper).sumByCategory(userCaptor.capture(), any(), any());
        assertEquals(USER_ID, userCaptor.getValue(), "分类聚合必须限定当前用户");
    }

    @Test
    void 两个用户的预测结果互不影响() {
        when(budgetMapper.selectList(any()))
                .thenReturn(List.of(total(600)))
                .thenReturn(List.of());
        when(billMapper.sumByDay(any(), any(), any()))
                .thenReturn(dailySums(daily(1, "160.00"), daily(2, "160.00"), daily(3, "160.00"),
                        daily(4, "160.00")))
                .thenReturn(List.of());
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());
        when(billMapper.sumByDayAndCategory(any(), any(), any())).thenReturn(List.of());

        BudgetPredictionResponse forA = service.predict(USER_ID, MONTH);
        BudgetPredictionResponse forB = service.predict(USER_ID + 1, MONTH);

        assertEquals("OK", forA.getStatus());
        assertEquals("600.00", forA.getItems().get(0).getProjectedOver());
        assertEquals("NO_BUDGET", forB.getStatus(), "B 没有预算时不应看到 A 的预测");
        assertTrue(forB.getItems().isEmpty());
    }

    @Test
    void 大数据量下仍然只做固定次数的聚合查询() {
        List<DailySum> manyDays = new ArrayList<>();
        for (int day = 1; day <= 16; day++) {
            manyDays.add(daily(day, "25.00"));
        }
        List<CategorySum> manyCategories = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            manyCategories.add(categorySum("分类" + i, "40.00"));
        }
        List<Budget> manyBudgets = new ArrayList<>();
        manyBudgets.add(total(2000));
        for (int i = 0; i < 10; i++) {
            manyBudgets.add(category("分类" + i, 100));
        }
        List<CategoryDailySum> manyCategoryDays = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            manyCategoryDays.add(categoryDaily("分类" + i, 1, "15.00"));
            manyCategoryDays.add(categoryDaily("分类" + i, 2, "15.00"));
            manyCategoryDays.add(categoryDaily("分类" + i, 3, "10.00"));
        }
        stub(manyBudgets, manyDays, manyCategories, manyCategoryDays);

        long start = System.nanoTime();
        BudgetPredictionResponse response = service.predict(USER_ID, MONTH);
        long elapsedMillis = (System.nanoTime() - start) / 1_000_000;

        assertEquals(11, response.getItems().size());
        assertEquals(16, response.getItems().get(0).getSpentDays());
        verify(billMapper, times(1)).sumByDay(any(), any(), any());
        verify(billMapper, times(1)).sumByCategory(any(), any(), any());
        verify(billMapper, times(1)).sumByDayAndCategory(any(), any(), any());
        assertTrue(elapsedMillis < 2000, "预测计算不应有明显耗时：" + elapsedMillis + "ms");
    }

    // ==================== 测试数据构造 ====================

    private void stub(List<Budget> budgets, List<DailySum> daily, List<CategorySum> categories) {
        stub(budgets, daily, categories, List.of());
    }

    private void stub(List<Budget> budgets, List<DailySum> daily, List<CategorySum> categories,
                      List<CategoryDailySum> categoryDaily) {
        when(budgetMapper.selectList(any())).thenReturn(budgets);
        when(billMapper.sumByDay(any(), any(), any())).thenReturn(daily);
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(categories);
        when(billMapper.sumByDayAndCategory(any(), any(), any())).thenReturn(categoryDaily);
    }

    private List<Budget> budgets(Budget... items) {
        return new ArrayList<>(List.of(items));
    }

    private BudgetPredictionItem findItem(BudgetPredictionResponse response, String category) {
        return response.getItems().stream()
                .filter(item -> category.equals(item.getCategory()))
                .findFirst()
                .orElseThrow(() -> new AssertionError("找不到分类预算：" + category));
    }

    private Budget total(long amount) {
        return budget("", amount);
    }

    private Budget category(String category, long amount) {
        return budget(category, amount);
    }

    private Budget budget(String category, long amount) {
        Budget budget = new Budget();
        budget.setId(category.isEmpty() ? 1L : (long) (Math.abs(category.hashCode()) % 100000));
        budget.setUserId(USER_ID);
        budget.setMonth(MONTH);
        budget.setCategory(category);
        budget.setAmount(new BigDecimal(amount).setScale(2));
        return budget;
    }

    private List<DailySum> dailySums(DailySum... sums) {
        return new ArrayList<>(List.of(sums));
    }

    private DailySum daily(int day, String amount) {
        return sum(day, 1, amount);
    }

    private DailySum sum(int day, int type, String amount) {
        DailySum sum = new DailySum();
        sum.setBillDate(LocalDate.of(2026, 9, day));
        sum.setType(type);
        sum.setAmount(new BigDecimal(amount));
        return sum;
    }

    private CategorySum categorySum(String category, String amount) {
        CategorySum sum = new CategorySum();
        sum.setCategory(category);
        sum.setAmount(new BigDecimal(amount));
        return sum;
    }

    private CategoryDailySum categoryDaily(String category, int day, String amount) {
        CategoryDailySum sum = new CategoryDailySum();
        sum.setCategory(category);
        sum.setBillDate(LocalDate.of(2026, 9, day));
        sum.setAmount(new BigDecimal(amount));
        return sum;
    }
}
