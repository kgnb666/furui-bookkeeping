package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.common.BillType;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.IncomeBalanceResponse;
import com.campus.ledger.dto.IncomeCategoryItem;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.mapper.BillMapper;
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
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * 收支结余分析测试。时间固定在 2026-09-18，参考月 2026-09（30 天），对比月 2026-08。
 */
@ExtendWith(MockitoExtension.class)
class IncomeBalanceServiceTest {

    private static final Long USER_ID = 53L;
    private static final String MONTH = "2026-09";
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final Clock FIXED = Clock.fixed(Instant.parse("2026-09-18T04:00:00Z"), ZONE);

    @Mock
    private BillMapper billMapper;

    private IncomeBalanceService service;

    /** 月份（yyyy-MM）→ 该月的收支合计，供按区间分派的答案使用 */
    private final java.util.Map<String, List<TypeSum>> monthSums = new java.util.HashMap<>();

    @BeforeEach
    void setUp() {
        service = new IncomeBalanceService(billMapper, FIXED);
        // 按查询区间所属月份分派结果：直接连续 stub 同一方法会互相覆盖，
        // 这里注册一次"月份 → 结果"的答案，本月与上月的查询各自命中自己的数据
        // （28 / 31 天月份的用例也自动生效）。用 lenient 是因为 NOT_APPLICABLE 用例压根不查库。
        lenient().when(billMapper.sumByType(anyLong(), any(), any())).thenAnswer(invocation -> {
            LocalDate start = invocation.getArgument(1);
            if (start == null) {
                return List.of();
            }
            String key = String.format("%04d-%02d", start.getYear(), start.getMonthValue());
            return monthSums.getOrDefault(key, List.of());
        });
    }

    // ==================== 结余计算 ====================

    @Test
    void 收入大于支出时结余为正且结余率正确() {
        stubMonth(typeSum(BillType.INCOME, "3000.00"), typeSum(BillType.EXPENSE, "1000.00"));
        stubIncomeItems(income("生活费", "3000.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "3000.00"), typeSum(BillType.EXPENSE, "1000.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals("3000.00", response.getIncomeAmount());
        assertEquals("1000.00", response.getExpenseAmount());
        assertEquals("2000.00", response.getBalance());
        assertEquals("66.67", response.getBalanceRate());
        assertTrue(response.getSummary().contains("本月结余 ¥2000.00"), response.getSummary());
    }

    @Test
    void 支出大于收入时结余为负并提示超支() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "1500.00"));
        stubIncomeItems(income("生活费", "1000.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "1500.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals("-500.00", response.getBalance());
        assertEquals("-50.00", response.getBalanceRate());
        assertTrue(response.getSummary().contains("支出超过收入 ¥500.00"), response.getSummary());
    }

    @Test
    void 收入等于支出时结余为零() {
        stubMonth(typeSum(BillType.INCOME, "800.00"), typeSum(BillType.EXPENSE, "800.00"));
        stubIncomeItems(income("生活费", "800.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "800.00"), typeSum(BillType.EXPENSE, "800.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals("0.00", response.getBalance());
        assertEquals("0.00", response.getBalanceRate());
        assertTrue(response.getSummary().contains("本月结余 ¥0.00"), response.getSummary());
    }

    @Test
    void 只有收入没有支出时结余等于收入() {
        stubMonth(typeSum(BillType.INCOME, "500.00"));
        stubIncomeItems(income("奖助学金", "500.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "500.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals("0.00", response.getExpenseAmount());
        assertEquals("500.00", response.getBalance());
        assertEquals("100.00", response.getBalanceRate());
    }

    // ==================== 收入结构 ====================

    @Test
    void 收入结构按金额降序排列() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "100.00"));
        stubIncomeItems(income("生活费", "600.00", 1), income("兼职收入", "300.00", 1),
                income("红包", "100.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "1000.00"));

        List<String> categories = new ArrayList<>();
        for (IncomeCategoryItem item : analyze().getIncomeItems()) {
            categories.add(item.getCategory());
        }

        assertEquals(List.of("生活费", "兼职收入", "红包"), categories);
    }

    @Test
    void 收入结构最多返回五项() {
        stubMonth(typeSum(BillType.INCOME, "1500.00"), typeSum(BillType.EXPENSE, "100.00"));
        stubIncomeItems(income("A", "500.00", 1), income("B", "400.00", 1), income("C", "300.00", 1),
                income("D", "200.00", 1), income("E", "50.00", 1), income("F", "50.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "1500.00"));

        assertEquals(5, analyze().getIncomeItems().size());
    }

    @Test
    void 收入结构占比按总收入计算() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "100.00"));
        stubIncomeItems(income("生活费", "750.00", 1), income("兼职收入", "250.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "1000.00"));

        List<IncomeCategoryItem> items = analyze().getIncomeItems();

        assertEquals("75.00", items.get(0).getPercentage());
        assertEquals("25.00", items.get(1).getPercentage());
    }

    @Test
    void 收入笔数按分类笔数合计() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "100.00"));
        stubIncomeItems(income("生活费", "600.00", 2), income("红包", "400.00", 3));
        stubPrevious(typeSum(BillType.INCOME, "1000.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals(5, response.getIncomeCount());
        assertEquals(2, response.getIncomeItems().get(0).getCount());
    }

    @Test
    void 收入分类为空时被跳过() {
        stubMonth(typeSum(BillType.INCOME, "500.00"), typeSum(BillType.EXPENSE, "100.00"));
        CategoryMonthlySum broken = new CategoryMonthlySum();
        broken.setAmount(new BigDecimal("100.00"));
        broken.setCount(1);
        stubIncomeItems(income("生活费", "500.00", 1), broken);
        stubPrevious(typeSum(BillType.INCOME, "500.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals(1, response.getIncomeItems().size());
        assertEquals("生活费", response.getIncomeItems().get(0).getCategory());
    }

    @Test
    void 收入笔数缺失时按零处理() {
        stubMonth(typeSum(BillType.INCOME, "500.00"), typeSum(BillType.EXPENSE, "100.00"));
        CategoryMonthlySum noCount = new CategoryMonthlySum();
        noCount.setCategory("生活费");
        noCount.setAmount(new BigDecimal("500.00"));
        stubIncomeItems(noCount);
        stubPrevious(typeSum(BillType.INCOME, "500.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals(0, response.getIncomeCount());
        assertEquals(0, response.getIncomeItems().get(0).getCount());
    }

    // ==================== 与上月对比 ====================

    @Test
    void 比上月多存时提示多存金额() {
        stubMonth(typeSum(BillType.INCOME, "3000.00"), typeSum(BillType.EXPENSE, "1000.00"));
        stubIncomeItems(income("生活费", "3000.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "2500.00"), typeSum(BillType.EXPENSE, "1500.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals("1000.00", response.getPreviousBalance());
        assertEquals("1000.00", response.getBalanceChange());
        assertTrue(response.isHasPreviousData());
        assertTrue(response.getSummary().contains("比上月多存 ¥1000.00"), response.getSummary());
    }

    @Test
    void 比上月少存时提示少存金额() {
        stubMonth(typeSum(BillType.INCOME, "2000.00"), typeSum(BillType.EXPENSE, "1800.00"));
        stubIncomeItems(income("生活费", "2000.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "3000.00"), typeSum(BillType.EXPENSE, "1000.00"));

        IncomeBalanceResponse response = analyze();

        assertEquals("200.00", response.getBalance());
        assertEquals("2000.00", response.getPreviousBalance());
        assertEquals("-1800.00", response.getBalanceChange());
        assertTrue(response.getSummary().contains("比上月少存 ¥1800.00"), response.getSummary());
    }

    @Test
    void 与上月持平时提示持平() {
        stubMonth(typeSum(BillType.INCOME, "3000.00"), typeSum(BillType.EXPENSE, "1000.00"));
        stubIncomeItems(income("生活费", "3000.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "3000.00"), typeSum(BillType.EXPENSE, "1000.00"));

        IncomeBalanceResponse response = analyze();

        assertTrue(response.getSummary().contains("与上月持平"), response.getSummary());
    }

    @Test
    void 上月没有记录时不生成对比() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "200.00"));
        stubIncomeItems(income("生活费", "1000.00", 1));
        stubPrevious();

        IncomeBalanceResponse response = analyze();

        assertFalse(response.isHasPreviousData());
        assertNull(response.getBalanceChange());
        assertEquals("0.00", response.getPreviousBalance());
        assertFalse(response.getSummary().contains("上月"));
    }

    // ==================== 状态 ====================

    @Test
    void 当月既无收入也无支出时返回NO_DATA() {
        stubMonth();

        IncomeBalanceResponse response = analyze();

        assertEquals("NO_DATA", response.getStatus());
        assertEquals("0.00", response.getIncomeAmount());
        assertEquals("0.00", response.getExpenseAmount());
        assertEquals("0.00", response.getBalance());
        assertEquals("", response.getSummary());
        assertTrue(response.getIncomeItems().isEmpty());
    }

    @Test
    void 只有支出没有收入时返回NO_INCOME_DATA并保留支出事实() {
        stubMonth(typeSum(BillType.EXPENSE, "900.00"));
        stubIncomeItems();

        IncomeBalanceResponse response = analyze();

        assertEquals("NO_INCOME_DATA", response.getStatus());
        assertEquals("0.00", response.getIncomeAmount());
        assertEquals("900.00", response.getExpenseAmount());
        assertEquals("-900.00", response.getBalance());
        assertEquals("0.00", response.getBalanceRate());
        assertEquals(0, response.getIncomeCount());
        assertTrue(response.getIncomeItems().isEmpty());
        assertTrue(response.getMessage().contains("没有收入记录"), response.getMessage());
        assertEquals("", response.getSummary());
    }

    @Test
    void 历史月份返回NOT_APPLICABLE且不查库() {
        IncomeBalanceResponse response = service.analyze(USER_ID, "2026-08");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertEquals("2026-08", response.getMonth());
        assertTrue(response.getIncomeItems().isEmpty());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 未来月份返回NOT_APPLICABLE且不查库() {
        assertEquals("NOT_APPLICABLE", service.analyze(USER_ID, "2026-10").getStatus());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 月份为空返回400() {
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, "  ")).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, null)).getCode());
    }

    @Test
    void 月份格式错误返回400() {
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, "2026-9")).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, "abc")).getCode());
    }

    // ==================== 查询与安全 ====================

    @Test
    void 正常分析共执行三次查询() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "200.00"));
        stubIncomeItems(income("生活费", "1000.00", 1));
        stubPrevious(typeSum(BillType.INCOME, "900.00"));

        analyze();

        verify(billMapper, times(2)).sumByType(anyLong(), any(), any());
        verify(billMapper, times(1)).sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 只有支出时只执行两次查询不查上月() {
        stubMonth(typeSum(BillType.EXPENSE, "900.00"));
        stubIncomeItems();

        analyze();

        verify(billMapper, times(1)).sumByType(anyLong(), any(), any());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 查询范围为当月与上月且收入结构只取收入类型() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"));
        stubIncomeItems(income("生活费", "1000.00", 1));
        stubPrevious();

        analyze();

        ArgumentCaptor<LocalDate> start = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper, times(2)).sumByType(anyLong(), start.capture(), end.capture());
        assertEquals(LocalDate.of(2026, 9, 1), start.getAllValues().get(0));
        assertEquals(LocalDate.of(2026, 9, 30), end.getAllValues().get(0));
        assertEquals(LocalDate.of(2026, 8, 1), start.getAllValues().get(1));
        assertEquals(LocalDate.of(2026, 8, 31), end.getAllValues().get(1));

        ArgumentCaptor<Integer> type = ArgumentCaptor.forClass(Integer.class);
        verify(billMapper).sumByCategoryAndMonth(anyLong(), type.capture(), any(), any(), anyString());
        assertEquals(BillType.INCOME.getCode(), type.getValue());
    }

    @Test
    void 查询固定使用传入的用户标识() {
        stubMonth();
        service.analyze(USER_ID, MONTH);
        stubMonth();
        service.analyze(66L, MONTH);

        ArgumentCaptor<Long> userIds = ArgumentCaptor.forClass(Long.class);
        verify(billMapper, times(2)).sumByType(userIds.capture(), any(), any());
        assertEquals(List.of(USER_ID, 66L), userIds.getAllValues());
    }

    // ==================== 数据健壮性与边界 ====================

    @Test
    void 不计收支与未知类型不参与结余() {
        stubMonth(typeSum(BillType.INCOME, "1000.00"), typeSum(BillType.EXPENSE, "200.00"),
                typeSum(BillType.NEUTRAL, "999.00"));
        stubIncomeItems(income("生活费", "1000.00", 1));
        stubPrevious();

        IncomeBalanceResponse response = analyze();

        assertEquals("1000.00", response.getIncomeAmount());
        assertEquals("200.00", response.getExpenseAmount());
        assertEquals("800.00", response.getBalance());
    }

    @Test
    void 空行与缺失字段被安全跳过() {
        TypeSum broken = new TypeSum();
        stubMonth(broken, typeSum(null, "999.00"), typeSum(BillType.INCOME, "1000.00"),
                typeSum(BillType.EXPENSE, null));
        stubIncomeItems(income("生活费", "1000.00", 1));
        stubPrevious();

        IncomeBalanceResponse response = analyze();

        assertEquals("1000.00", response.getIncomeAmount());
        assertEquals("0.00", response.getExpenseAmount());
    }

    @Test
    void 大金额保持精度() {
        stubMonth(typeSum(BillType.INCOME, "99999999.99"), typeSum(BillType.EXPENSE, "0.01"));
        stubIncomeItems(income("生活费", "99999999.99", 1));
        stubPrevious();

        assertEquals("99999999.98", analyze().getBalance());
    }

    @Test
    void 二十八天月份查询范围正确() {
        monthSums.put("2026-02", List.of(typeSum(BillType.INCOME, "1000.00")));
        monthSums.put("2026-01", List.of());
        stubIncomeItems(income("生活费", "1000.00", 1));

        serviceOf("2026-02-15T04:00:00Z").analyze(USER_ID, "2026-02");

        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper, times(2)).sumByType(anyLong(), any(), end.capture());
        assertEquals(LocalDate.of(2026, 2, 28), end.getAllValues().get(0));
    }

    @Test
    void 三十一天月份查询范围正确() {
        monthSums.put("2026-07", List.of(typeSum(BillType.INCOME, "1000.00")));
        monthSums.put("2026-06", List.of());
        stubIncomeItems(income("生活费", "1000.00", 1));

        serviceOf("2026-07-15T04:00:00Z").analyze(USER_ID, "2026-07");

        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper, times(2)).sumByType(anyLong(), any(), end.capture());
        assertEquals(LocalDate.of(2026, 7, 31), end.getAllValues().get(0));
    }

    @Test
    void 工具方法边界正确() {
        assertEquals("0.00", IncomeBalanceService.percentage(BigDecimal.TEN, BigDecimal.ZERO));
        assertEquals("0.00", IncomeBalanceService.percentage(BigDecimal.TEN, null));
        assertEquals("100.00", IncomeBalanceService.percentage(BigDecimal.TEN, BigDecimal.TEN));
    }

    // ==================== 辅助方法 ====================

    private IncomeBalanceResponse analyze() {
        return service.analyze(USER_ID, MONTH);
    }

    private IncomeBalanceService serviceOf(String instant) {
        return new IncomeBalanceService(billMapper, Clock.fixed(Instant.parse(instant), ZONE));
    }

    private void stubMonth(TypeSum... sums) {
        monthSums.put(MONTH, List.of(sums));
    }

    private void stubPrevious(TypeSum... sums) {
        monthSums.put("2026-08", List.of(sums));
    }

    private void stubIncomeItems(CategoryMonthlySum... sums) {
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(List.of(sums));
    }

    private static TypeSum typeSum(BillType type, String amount) {
        TypeSum sum = new TypeSum();
        sum.setType(type == null ? null : type.getCode());
        sum.setAmount(amount == null ? null : new BigDecimal(amount));
        return sum;
    }

    private static CategoryMonthlySum income(String category, String amount, int count) {
        CategoryMonthlySum sum = new CategoryMonthlySum();
        sum.setCategory(category);
        sum.setMonth(MONTH);
        sum.setAmount(new BigDecimal(amount));
        sum.setCount(count);
        return sum;
    }
}
