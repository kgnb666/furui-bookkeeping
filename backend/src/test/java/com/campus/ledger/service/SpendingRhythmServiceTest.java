package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.common.BillType;
import com.campus.ledger.dto.DailySum;
import com.campus.ledger.dto.PeriodSpendingItem;
import com.campus.ledger.dto.SpendingRhythmResponse;
import com.campus.ledger.dto.WeekdaySpendingItem;
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
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * 消费节奏分析测试。时间固定在 2026-09-18，
 * 参考月固定为 2026-09（30 天），需要验证其它月份长度时另建固定时钟的 Service。
 *
 * 2026-09-01 是周二、2026-09-05 是周六、2026-09-06 是周日、2026-09-18 是周五。
 */
@ExtendWith(MockitoExtension.class)
class SpendingRhythmServiceTest {

    private static final Long USER_ID = 27L;
    private static final String MONTH = "2026-09";
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final Clock FIXED = Clock.fixed(
            Instant.parse("2026-09-18T04:00:00Z"), ZONE);

    @Mock
    private BillMapper billMapper;

    private SpendingRhythmService service;

    @BeforeEach
    void setUp() {
        service = new SpendingRhythmService(billMapper, FIXED);
    }

    // ==================== 基础：星期 / 阶段 / 百分比 / 峰值 ====================

    @Test
    void 星期聚合正确() {
        // 周二 300、周三 100、周六 100（三个不同星期，满足最少 3 天）
        stub(List.of(expense(d(1), "300.00"), expense(d(2), "100.00"), expense(d(5), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals(7, response.getWeekdayItems().size());
        WeekdaySpendingItem tuesday = response.getWeekdayItems().get(1);
        WeekdaySpendingItem saturday = response.getWeekdayItems().get(5);
        assertEquals(2, tuesday.getWeekday());
        assertEquals("周二", tuesday.getWeekdayName());
        assertEquals("300.00", tuesday.getAmount());
        assertEquals(6, saturday.getWeekday());
        assertEquals("周六", saturday.getWeekdayName());
        assertEquals("100.00", saturday.getAmount());
        assertEquals("0.00", response.getWeekdayItems().get(0).getAmount());
    }

    @Test
    void 星期名称按周一到周日固定排列() {
        stub(List.of(expense(d(1), "100.00"), expense(d(2), "100.00"), expense(d(3), "100.00")));

        List<WeekdaySpendingItem> items = analyze().getWeekdayItems();

        assertEquals(List.of("周一", "周二", "周三", "周四", "周五", "周六", "周日"),
                items.stream().map(WeekdaySpendingItem::getWeekdayName).toList());
        assertEquals(List.of(1, 2, 3, 4, 5, 6, 7),
                items.stream().map(WeekdaySpendingItem::getWeekday).toList());
    }

    @Test
    void 月内阶段正确() {
        // 5 日（1-10）100、15 日（11-20）200、25 日（21-月底）300
        stub(List.of(expense(d(5), "100.00"), expense(d(15), "200.00"), expense(d(25), "300.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals(3, response.getPeriodItems().size());
        PeriodSpendingItem first = response.getPeriodItems().get(0);
        assertEquals("1-10日", first.getPeriodName());
        assertEquals(1, first.getStartDay());
        assertEquals(10, first.getEndDay());
        assertEquals("100.00", first.getAmount());

        PeriodSpendingItem second = response.getPeriodItems().get(1);
        assertEquals("11-20日", second.getPeriodName());
        assertEquals(11, second.getStartDay());
        assertEquals(20, second.getEndDay());
        assertEquals("200.00", second.getAmount());

        PeriodSpendingItem third = response.getPeriodItems().get(2);
        assertEquals("21日-月底", third.getPeriodName());
        assertEquals(21, third.getStartDay());
        assertEquals(30, third.getEndDay(), "第三段的结束日是当月天数");
        assertEquals("300.00", third.getAmount());
    }

    @Test
    void 阶段边界日归类正确() {
        stub(List.of(expense(d(10), "100.00"), expense(d(11), "100.00"), expense(d(20), "100.00"),
                expense(d(21), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("100.00", response.getPeriodItems().get(0).getAmount(), "10 日属于第一阶段");
        assertEquals("200.00", response.getPeriodItems().get(1).getAmount(), "11 与 20 日属于第二阶段");
        assertEquals("100.00", response.getPeriodItems().get(2).getAmount(), "21 日属于第三阶段");
    }

    @Test
    void 百分比计算正确且合计约等于一百() {
        stub(List.of(expense(d(1), "300.00"), expense(d(2), "150.00"), expense(d(3), "50.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("60.00", response.getWeekdayItems().get(1).getPercentage());
        assertEquals("30.00", response.getWeekdayItems().get(2).getPercentage());
        assertEquals("10.00", response.getWeekdayItems().get(3).getPercentage());

        BigDecimal weekdaySum = BigDecimal.ZERO;
        for (WeekdaySpendingItem item : response.getWeekdayItems()) {
            weekdaySum = weekdaySum.add(new BigDecimal(item.getPercentage()));
        }
        BigDecimal periodSum = BigDecimal.ZERO;
        for (PeriodSpendingItem item : response.getPeriodItems()) {
            periodSum = periodSum.add(new BigDecimal(item.getPercentage()));
        }
        assertTrue(weekdaySum.subtract(new BigDecimal("100")).abs().compareTo(new BigDecimal("0.1")) <= 0,
                "星期占比合计应约等于 100：" + weekdaySum);
        assertTrue(periodSum.subtract(new BigDecimal("100")).abs().compareTo(new BigDecimal("0.1")) <= 0,
                "阶段占比合计应约等于 100：" + periodSum);
    }

    @Test
    void 峰值星期取金额最高的星期() {
        stub(List.of(expense(d(1), "100.00"), expense(d(5), "900.00"), expense(d(6), "200.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("周六", response.getPeakWeekday());
        // 900 / 1200 = 75.00
        assertEquals("75.00", response.getConcentration());
    }

    @Test
    void 峰值阶段取金额最高的阶段() {
        stub(List.of(expense(d(5), "100.00"), expense(d(15), "800.00"), expense(d(25), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("11-20日", response.getPeakPeriod());
    }

    @Test
    void 金额并列时取更早的星期保证结果稳定() {
        stub(List.of(expense(d(1), "500.00"), expense(d(2), "500.00"), expense(d(3), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("周二", response.getPeakWeekday(), "并列时按周一→周日顺序取第一个");
    }

    @Test
    void 全部支出集中在同一天时该星期占比一百() {
        // 2026-09-05 周六、09-15 周二、09-25 周五
        stub(List.of(expense(d(5), "600.00"), expense(d(15), "200.00"), expense(d(25), "200.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("周六", response.getPeakWeekday());
        assertEquals("60.00", response.getWeekdayItems().get(5).getPercentage());
        assertEquals("60.00", response.getConcentration());
    }

    // ==================== 月长边界：28 / 29 / 30 / 31 天 ====================

    @Test
    void 二十八天月份第三阶段结束日为二十八() {
        stub(List.of(expense(LocalDate.of(2026, 2, 3), "100.00"),
                expense(LocalDate.of(2026, 2, 15), "100.00"),
                expense(LocalDate.of(2026, 2, 27), "100.00")));

        SpendingRhythmResponse response = serviceOf("2026-02-15T04:00:00Z").analyze(USER_ID, "2026-02");

        assertEquals("OK", response.getStatus());
        assertEquals(28, response.getPeriodItems().get(2).getEndDay());
        assertEquals("10.71", response.getCoveredRate(), "3 / 28 = 10.71");
    }

    @Test
    void 二十九天闰月第三阶段结束日为二十九() {
        stub(List.of(expense(LocalDate.of(2024, 2, 3), "100.00"),
                expense(LocalDate.of(2024, 2, 15), "100.00"),
                expense(LocalDate.of(2024, 2, 29), "100.00")));

        SpendingRhythmResponse response = serviceOf("2024-02-15T04:00:00Z").analyze(USER_ID, "2024-02");

        assertEquals("OK", response.getStatus());
        assertEquals(29, response.getPeriodItems().get(2).getEndDay());
        assertEquals("10.34", response.getCoveredRate(), "3 / 29 = 10.34");
    }

    @Test
    void 三十天月份第三阶段结束日为三十() {
        stub(List.of(expense(d(1), "100.00"), expense(d(15), "100.00"), expense(d(30), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals(30, response.getPeriodItems().get(2).getEndDay());
        assertEquals("10.00", response.getCoveredRate(), "3 / 30 = 10.00");
    }

    @Test
    void 三十一天月份第三阶段结束日为三十一() {
        stub(List.of(expense(LocalDate.of(2026, 7, 1), "100.00"),
                expense(LocalDate.of(2026, 7, 15), "100.00"),
                expense(LocalDate.of(2026, 7, 31), "100.00")));

        SpendingRhythmResponse response = serviceOf("2026-07-15T04:00:00Z").analyze(USER_ID, "2026-07");

        assertEquals("OK", response.getStatus());
        assertEquals(31, response.getPeriodItems().get(2).getEndDay());
        assertEquals("9.68", response.getCoveredRate(), "3 / 31 = 9.68");
        assertEquals("100.00", response.getPeriodItems().get(2).getAmount(), "31 日属于第三阶段");
    }

    // ==================== 状态 ====================

    @Test
    void 正常数据返回OK并给出结论() {
        // 周六 400（1-10 日）、周二 300（11-20 日）、周五 300（21 日-月底）
        stub(List.of(expense(d(5), "400.00"), expense(d(15), "300.00"), expense(d(25), "300.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals(MONTH, response.getMonth());
        assertEquals("1000.00", response.getTotalAmount());
        assertEquals(3, response.getCoveredDays());
        assertTrue(response.getMessage().contains("3 天"), response.getMessage());
        assertTrue(response.getSummary().contains("周六"), response.getSummary());
        assertTrue(response.getSummary().contains("1-10日"), response.getSummary());
    }

    @Test
    void 没有支出时返回NO_DATA且列表为空() {
        stub(List.of());

        SpendingRhythmResponse response = analyze();

        assertEquals("NO_DATA", response.getStatus());
        assertEquals("0.00", response.getTotalAmount());
        assertEquals(0, response.getCoveredDays());
        assertEquals("0.00", response.getCoveredRate());
        assertTrue(response.getWeekdayItems().isEmpty());
        assertTrue(response.getPeriodItems().isEmpty());
        assertTrue(response.getSummary().isEmpty());
        assertEquals("", response.getPeakWeekday());
        assertEquals("", response.getPeakPeriod());
        assertEquals("0.00", response.getConcentration());
    }

    @Test
    void 只有收入记录时也算没有支出() {
        stub(List.of(row(d(5), BillType.INCOME.getCode(), "5000.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("NO_DATA", response.getStatus());
        assertEquals("0.00", response.getTotalAmount());
    }

    @Test
    void 消费天数不足三天时返回INSUFFICIENT_DATA() {
        stub(List.of(expense(d(5), "200.00"), expense(d(12), "300.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals(2, response.getCoveredDays());
        assertEquals("500.00", response.getTotalAmount(), "金额仍然如实返回");
        assertTrue(response.getWeekdayItems().isEmpty());
        assertTrue(response.getMessage().contains("2 天"), response.getMessage());
    }

    @Test
    void 恰好三天时返回OK() {
        stub(List.of(expense(d(5), "100.00"), expense(d(12), "100.00"), expense(d(19), "100.00")));

        assertEquals("OK", analyze().getStatus());
    }

    @Test
    void 历史月份返回NOT_APPLICABLE且不查库() {
        SpendingRhythmResponse response = service.analyze(USER_ID, "2026-08");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertEquals("2026-08", response.getMonth());
        assertTrue(response.getWeekdayItems().isEmpty());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 未来月份返回NOT_APPLICABLE且不查库() {
        SpendingRhythmResponse response = service.analyze(USER_ID, "2026-10");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 月份格式错误返回400() {
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, "2026-9")).getCode());
    }

    @Test
    void 月份为空返回400() {
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, "   ")).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> service.analyze(USER_ID, null)).getCode());
    }

    // ==================== 查询与安全 ====================

    @Test
    void 整个分析只执行一次聚合查询() {
        stub(List.of(expense(d(5), "100.00"), expense(d(12), "100.00"), expense(d(19), "100.00")));

        analyze();

        verify(billMapper, times(1)).sumByDay(anyLong(), any(), any());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 查询范围只覆盖目标月份() {
        stub(List.of());

        analyze();

        ArgumentCaptor<LocalDate> start = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper).sumByDay(anyLong(), start.capture(), end.capture());

        assertEquals(LocalDate.of(2026, 9, 1), start.getValue(), "从当月 1 日开始");
        assertEquals(LocalDate.of(2026, 9, 30), end.getValue(), "到当月最后一天结束，不读取历史月份");
    }

    @Test
    void 查询固定使用传入的用户标识() {
        stub(List.of());

        service.analyze(USER_ID, MONTH);
        service.analyze(88L, MONTH);

        ArgumentCaptor<Long> userIds = ArgumentCaptor.forClass(Long.class);
        verify(billMapper, times(2)).sumByDay(userIds.capture(), any(), any());
        assertEquals(List.of(USER_ID, 88L), userIds.getAllValues(),
                "用户 A 与用户 B 各自查询自己的数据，Service 不接受来自请求的 userId");
    }

    // ==================== 数据健壮性 ====================

    @Test
    void 不计收支与未知类型都不参与统计() {
        stub(List.of(row(d(5), BillType.NEUTRAL.getCode(), "500.00"),
                row(d(5), BillType.EXPENSE.getCode(), "100.00"),
                row(d(12), BillType.EXPENSE.getCode(), "100.00"),
                row(d(19), BillType.EXPENSE.getCode(), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("300.00", response.getTotalAmount());
        assertEquals(3, response.getCoveredDays());
    }

    @Test
    void 合计为零的日期不计入消费天数() {
        stub(List.of(row(d(5), BillType.EXPENSE.getCode(), "0.00"),
                expense(d(12), "100.00"),
                expense(d(19), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals(2, response.getCoveredDays(), "金额为 0 的日期不算消费日");
    }

    @Test
    void 空行与缺失字段被安全跳过() {
        DailySum broken = new DailySum();
        stub(List.of(broken, row(null, BillType.EXPENSE.getCode(), "100.00"),
                row(d(5), null, "100.00"), row(d(5), BillType.EXPENSE.getCode(), null),
                expense(d(5), "100.00"), expense(d(12), "100.00"), expense(d(19), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals("300.00", response.getTotalAmount());
    }

    @Test
    void 同一天出现多行时金额会合并() {
        stub(List.of(expense(d(5), "100.00"), expense(d(5), "50.00"),
                expense(d(15), "100.00"), expense(d(25), "100.00")));

        SpendingRhythmResponse response = analyze();

        assertEquals("350.00", response.getTotalAmount());
        assertEquals(3, response.getCoveredDays(), "同一天多行只算一天");
        assertEquals("150.00", response.getWeekdayItems().get(5).getAmount());
    }

    @Test
    void 大金额保持精度() {
        stub(List.of(expense(d(5), "99999999.99"), expense(d(12), "0.01"), expense(d(19), "0.01")));

        SpendingRhythmResponse response = analyze();

        assertEquals("100000000.01", response.getTotalAmount());
    }

    @Test
    void 记账覆盖率达到满月时返回一百() {
        List<DailySum> rows = new ArrayList<>();
        for (int day = 1; day <= 30; day++) {
            rows.add(expense(d(day), "10.00"));
        }
        stub(rows);

        SpendingRhythmResponse response = analyze();

        assertEquals(30, response.getCoveredDays());
        assertEquals("100.00", response.getCoveredRate());
    }

    // ==================== 工具方法 ====================

    @Test
    void 阶段索引边界正确() {
        assertEquals(0, SpendingRhythmService.periodIndex(1));
        assertEquals(0, SpendingRhythmService.periodIndex(10));
        assertEquals(1, SpendingRhythmService.periodIndex(11));
        assertEquals(1, SpendingRhythmService.periodIndex(20));
        assertEquals(2, SpendingRhythmService.periodIndex(21));
        assertEquals(2, SpendingRhythmService.periodIndex(31));
    }

    @Test
    void 占比在总金额为零时返回零() {
        assertEquals("0.00", SpendingRhythmService.percentage(BigDecimal.TEN, BigDecimal.ZERO));
        assertEquals("0.00", SpendingRhythmService.percentage(BigDecimal.TEN, null));
        assertEquals("100.00", SpendingRhythmService.percentage(BigDecimal.TEN, BigDecimal.TEN));
    }

    @Test
    void 覆盖率在非法天数下返回零() {
        assertEquals("0.00", SpendingRhythmService.coveredRate(0, 0));
        assertEquals("0.00", SpendingRhythmService.coveredRate(0, 30));
    }

    // ==================== 辅助方法 ====================

    private SpendingRhythmResponse analyze() {
        return service.analyze(USER_ID, MONTH);
    }

    private SpendingRhythmService serviceOf(String instant) {
        return new SpendingRhythmService(billMapper, Clock.fixed(Instant.parse(instant), ZONE));
    }

    private void stub(List<DailySum> rows) {
        when(billMapper.sumByDay(anyLong(), any(), any())).thenReturn(rows);
    }

    /** 2026 年 9 月的第 day 天 */
    private static LocalDate d(int day) {
        return LocalDate.of(2026, 9, day);
    }

    private static DailySum expense(LocalDate date, String amount) {
        return row(date, BillType.EXPENSE.getCode(), amount);
    }

    private static DailySum row(LocalDate date, Integer type, String amount) {
        DailySum sum = new DailySum();
        sum.setBillDate(date);
        sum.setType(type);
        sum.setAmount(amount == null ? null : new BigDecimal(amount));
        return sum;
    }
}
