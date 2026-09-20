package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.CategoryStatResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.DailyStatResponse;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.dto.MonthlyStatResponse;
import com.campus.ledger.dto.SourceStatResponse;
import com.campus.ledger.dto.SourceSum;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.mapper.BillMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class StatisticsServiceTest {

    private static final Long USER_ID = 3L;
    private static final String MONTH = "2026-09";

    @Mock
    private BillMapper billMapper;

    private StatisticsService statisticsService;

    @BeforeEach
    void setUp() {
        statisticsService = new StatisticsService(billMapper);
    }

    @Test
    void 月度概览返回收入支出与结余() {
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of(
                typeSum(BillType.INCOME, "500.00"),
                typeSum(BillType.EXPENSE, "214.00")));

        MonthlyStatResponse response = statisticsService.monthly(USER_ID, MONTH);

        assertEquals("2026-09", response.getMonth());
        assertEquals("500.00", response.getIncome());
        assertEquals("214.00", response.getExpense());
        assertEquals("286.00", response.getBalance());
    }

    @Test
    void 不计收支不参与统计() {
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of(
                typeSum(BillType.INCOME, "500.00"),
                typeSum(BillType.EXPENSE, "214.00"),
                typeSum(BillType.NEUTRAL, "999.00")));

        MonthlyStatResponse response = statisticsService.monthly(USER_ID, MONTH);

        assertEquals("500.00", response.getIncome());
        assertEquals("214.00", response.getExpense(), "不计收支不能计入支出");
        assertEquals("286.00", response.getBalance());
    }

    @Test
    void 空月份返回零且不报错() {
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());

        MonthlyStatResponse response = statisticsService.monthly(USER_ID, MONTH);

        assertEquals("0.00", response.getIncome());
        assertEquals("0.00", response.getExpense());
        assertEquals("0.00", response.getBalance());
    }

    @Test
    void 月份格式非法时拒绝() {
        BizException e = assertThrows(BizException.class, () -> statisticsService.monthly(USER_ID, "2026-13-01"));

        assertEquals(400, e.getCode());
    }

    @Test
    void 统计查询带当前用户与整月日期范围() {
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());
        ArgumentCaptor<Long> userIdCaptor = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<LocalDate> startCaptor = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> endCaptor = ArgumentCaptor.forClass(LocalDate.class);

        statisticsService.monthly(USER_ID, MONTH);

        verify(billMapper).sumByType(userIdCaptor.capture(), startCaptor.capture(), endCaptor.capture());
        assertEquals(USER_ID, userIdCaptor.getValue());
        assertEquals(LocalDate.of(2026, 9, 1), startCaptor.getValue());
        assertEquals(LocalDate.of(2026, 9, 30), endCaptor.getValue());
    }

    @Test
    void 分类统计返回金额与占比() {
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of(
                categorySum("餐饮", "86.50"),
                categorySum("购物", "45.60"),
                categorySum("交通", "32.50")));

        List<CategoryStatResponse> result = statisticsService.category(USER_ID, MONTH);

        assertEquals(3, result.size());
        assertEquals("餐饮", result.get(0).getCategory());
        assertEquals("86.50", result.get(0).getAmount());
        // 总支出 164.60：餐饮 86.50/164.60 = 52.55%，购物 45.60/164.60 = 27.70%
        assertEquals(new BigDecimal("52.55"), result.get(0).getPercentage());
        assertEquals(new BigDecimal("27.70"), result.get(1).getPercentage());
    }

    @Test
    void 分类统计没有数据时返回空列表() {
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        assertTrue(statisticsService.category(USER_ID, MONTH).isEmpty());
    }

    @Test
    void 分类总额为零时占比为零() {
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of(categorySum("餐饮", "0.00")));

        List<CategoryStatResponse> result = statisticsService.category(USER_ID, MONTH);

        assertEquals(1, result.size());
        assertEquals(new BigDecimal("0.00"), result.get(0).getPercentage());
    }

    @Test
    void 每日趋势覆盖整月并补零() {
        when(billMapper.sumByDay(any(), any(), any())).thenReturn(List.of(
                dailySum(LocalDate.of(2026, 9, 1), BillType.EXPENSE, "18.50"),
                dailySum(LocalDate.of(2026, 9, 2), BillType.INCOME, "500.00"),
                dailySum(LocalDate.of(2026, 9, 2), BillType.EXPENSE, "45.60"),
                dailySum(LocalDate.of(2026, 9, 2), BillType.NEUTRAL, "200.00")));

        List<DailyStatResponse> result = statisticsService.daily(USER_ID, MONTH);

        assertEquals(30, result.size(), "9 月应返回 30 天");
        assertEquals("2026-09-01", result.get(0).getDate());
        assertEquals("0.00", result.get(0).getIncome());
        assertEquals("18.50", result.get(0).getExpense());
        assertEquals("500.00", result.get(1).getIncome());
        assertEquals("45.60", result.get(1).getExpense(), "不计收支不计入当日支出");
        assertEquals("0.00", result.get(2).getExpense());
        assertEquals("2026-09-30", result.get(29).getDate());
    }

    @Test
    void 来源统计返回金额与占比() {
        when(billMapper.sumBySource(any(), any(), any())).thenReturn(List.of(
                sourceSum("WECHAT", "120.50"),
                sourceSum("ALIPAY", "73.50"),
                sourceSum("MANUAL", "20.00")));

        List<SourceStatResponse> result = statisticsService.source(USER_ID, MONTH);

        assertEquals(3, result.size());
        assertEquals("WECHAT", result.get(0).getSource());
        assertEquals("微信", result.get(0).getSourceName());
        assertEquals("120.50", result.get(0).getAmount());
        // 总支出 214.00：120.50 → 56.31%，73.50 → 34.35%，20.00 → 9.35%
        assertEquals(new BigDecimal("56.31"), result.get(0).getPercentage());
        assertEquals("支付宝", result.get(1).getSourceName());
        assertEquals(new BigDecimal("34.35"), result.get(1).getPercentage());
        assertEquals("手动记录", result.get(2).getSourceName());
        assertEquals(new BigDecimal("9.35"), result.get(2).getPercentage());
    }

    @Test
    void 来源统计空月份返回空列表() {
        when(billMapper.sumBySource(any(), any(), any())).thenReturn(List.of());

        assertTrue(statisticsService.source(USER_ID, MONTH).isEmpty());
    }

    @Test
    void 来源统计查询带当前用户与整月范围() {
        when(billMapper.sumBySource(any(), any(), any())).thenReturn(List.of());
        ArgumentCaptor<Long> userIdCaptor = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<LocalDate> startCaptor = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> endCaptor = ArgumentCaptor.forClass(LocalDate.class);

        statisticsService.source(USER_ID, MONTH);

        verify(billMapper).sumBySource(userIdCaptor.capture(), startCaptor.capture(), endCaptor.capture());
        assertEquals(USER_ID, userIdCaptor.getValue(), "来源统计只能查当前登录用户");
        assertEquals(LocalDate.of(2026, 9, 1), startCaptor.getValue());
        assertEquals(LocalDate.of(2026, 9, 30), endCaptor.getValue());
    }

    @Test
    void 来源统计总额为零时占比为零() {
        when(billMapper.sumBySource(any(), any(), any())).thenReturn(List.of(sourceSum("MANUAL", "0.00")));

        List<SourceStatResponse> result = statisticsService.source(USER_ID, MONTH);

        assertEquals(1, result.size());
        assertEquals(new BigDecimal("0.00"), result.get(0).getPercentage());
        assertEquals("手动记录", result.get(0).getSourceName());
    }

    @Test
    void 来源统计遇到未知来源时返回原始值() {
        when(billMapper.sumBySource(any(), any(), any())).thenReturn(List.of(sourceSum("OTHER", "10.00")));

        List<SourceStatResponse> result = statisticsService.source(USER_ID, MONTH);

        assertEquals("OTHER", result.get(0).getSourceName());
    }

    @Test
    void 指定日期的收支合计只算收入与支出() {
        LocalDate date = LocalDate.of(2026, 9, 16);
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of(
                typeSum(BillType.INCOME, "100.00"),
                typeSum(BillType.EXPENSE, "20.00")));

        var response = statisticsService.dailySummary(USER_ID, date);

        assertEquals("2026-09-16", response.getDate());
        assertEquals("100.00", response.getIncome());
        assertEquals("20.00", response.getExpense());
    }

    @Test
    void 指定日期没有账单时收支都是零() {
        LocalDate date = LocalDate.of(2026, 9, 16);
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());

        var response = statisticsService.dailySummary(USER_ID, date);

        assertEquals("0.00", response.getIncome());
        assertEquals("0.00", response.getExpense());
    }

    @Test
    void 日期汇总的查询范围就是当天且带当前用户() {
        LocalDate date = LocalDate.of(2026, 9, 16);
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());

        statisticsService.dailySummary(USER_ID, date);

        ArgumentCaptor<Long> userIdCaptor = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<LocalDate> startCaptor = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> endCaptor = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper).sumByType(userIdCaptor.capture(), startCaptor.capture(), endCaptor.capture());

        assertEquals(USER_ID, userIdCaptor.getValue());
        assertEquals(date, startCaptor.getValue());
        assertEquals(date, endCaptor.getValue());
    }

    @Test
    void 消费趋势给出本月与上月支出以及变化率() {
        when(billMapper.sumByType(any(), any(), any()))
                // 本月：支出 120.00，收入 500.00
                .thenReturn(List.of(
                        typeSum(BillType.EXPENSE, "120.00"),
                        typeSum(BillType.INCOME, "500.00")))
                // 上月：支出 100.00
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "100.00")));

        var response = statisticsService.trends(USER_ID, "2026-09");

        assertEquals("2026-09", response.getMonth());
        assertEquals("120.00", response.getCurrentExpense());
        assertEquals("500.00", response.getCurrentIncome());
        assertEquals("2026-08", response.getPreviousMonth());
        assertEquals("100.00", response.getPreviousExpense());
        assertTrue(response.isPreviousHasData());
        assertEquals("20.00", response.getExpenseChangePercent());
    }

    @Test
    void 消费趋势在上月没有账单时不给出变化率() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "80.00")))
                .thenReturn(List.of());

        var response = statisticsService.trends(USER_ID, "2026-09");

        assertFalse(response.isPreviousHasData());
        assertNull(response.getExpenseChangePercent(), "上月无数据时不应给出对比结论");
        assertEquals("0.00", response.getPreviousExpense());
    }

    @Test
    void 消费趋势跨年时上月是去年12月() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "50.00")))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "200.00")));

        var response = statisticsService.trends(USER_ID, "2027-01");

        assertEquals("2027-01", response.getMonth());
        assertEquals("2026-12", response.getPreviousMonth());
        // 50 vs 200，下降 75%
        assertEquals("-75.00", response.getExpenseChangePercent());
    }

    @Test
    void 消费趋势的上月支出为0时不做百分比计算() {
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.INCOME, "300.00")))
                .thenReturn(List.of(typeSum(BillType.INCOME, "300.00")));

        var response = statisticsService.trends(USER_ID, "2026-09");

        // 上月只有收入没有支出：有数据但支出为 0，除零没有意义
        assertTrue(response.isPreviousHasData());
        assertNull(response.getExpenseChangePercent());
    }

    private SourceSum sourceSum(String source, String amount) {
        SourceSum sum = new SourceSum();
        sum.setSource(source);
        sum.setAmount(new BigDecimal(amount));
        return sum;
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

    private DailySum dailySum(LocalDate date, BillType type, String amount) {
        DailySum sum = new DailySum();
        sum.setBillDate(date);
        sum.setType(type.getCode());
        sum.setAmount(new BigDecimal(amount));
        return sum;
    }
}
