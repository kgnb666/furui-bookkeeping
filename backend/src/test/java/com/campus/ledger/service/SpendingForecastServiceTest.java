package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.common.BillType;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.ForecastSampleMonth;
import com.campus.ledger.dto.SpendingForecastResponse;
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
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * 下月支出预估测试。时间固定在 2026-09-18，
 * 参考月固定为 2026-09，目标月为 2026-10，预测使用 2026-08 / 07 / 06 三个完整自然月。
 */
@ExtendWith(MockitoExtension.class)
class SpendingForecastServiceTest {

    private static final Long USER_ID = 31L;
    private static final String MONTH = "2026-09";
    private static final Clock FIXED = Clock.fixed(
            Instant.parse("2026-09-18T04:00:00Z"), ZoneId.of("Asia/Shanghai"));

    @Mock
    private BillMapper billMapper;

    private SpendingForecastService service;

    @BeforeEach
    void setUp() {
        service = new SpendingForecastService(billMapper, FIXED);
    }

    // ==================== 数据与状态 ====================

    @Test
    void 没有支出历史时返回NO_DATA() {
        stub(List.of());

        SpendingForecastResponse response = forecast();

        assertEquals("NO_DATA", response.getStatus());
        assertEquals("2026-10", response.getTargetMonth());
        assertEquals("0.00", response.getPredictedAmount());
        assertEquals("NONE", response.getConfidence());
        assertNull(response.getPredictedDifference());
        assertNull(response.getPredictedChangePercent());
        assertTrue(response.getSampleMonths().isEmpty());
        assertTrue(response.getMessage().length() > 0);
    }

    @Test
    void 只有本月支出时返回INSUFFICIENT_DATA() {
        stub(rows(row("2026-09", "餐饮", "800.00"), row("2026-09", "交通", "200.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals("1000.00", response.getCurrentMonthAmount(), "本月支出仍然要如实返回");
        assertEquals("0.00", response.getPredictedAmount());
        assertTrue(response.getSampleMonths().isEmpty());
    }

    @Test
    void 只有一个历史月份时返回INSUFFICIENT_DATA() {
        stub(rows(row("2026-08", "餐饮", "1200.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals("0.00", response.getPredictedAmount());
        assertEquals("NONE", response.getConfidence());
    }

    @Test
    void 只有两个历史月份时返回INSUFFICIENT_DATA() {
        stub(rows(row("2026-08", "餐饮", "1200.00"), row("2026-07", "餐饮", "1000.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals("0.00", response.getPredictedAmount());
        assertTrue(response.getMessage().contains("3"), response.getMessage());
    }

    @Test
    void 恰好三个历史月份时返回OK并按三二一加权() {
        // (1250×3 + 1180×2 + 1320×1) / 6 = 7430 / 6 = 1238.33
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("OK", response.getStatus());
        assertEquals("2026-09", response.getMonth());
        assertEquals("2026-10", response.getTargetMonth());
        assertEquals("1238.33", response.getPredictedAmount());
        assertEquals("1250.00", response.getPreviousMonthAmount());
        assertEquals("-11.67", response.getPredictedDifference());
        assertEquals("-0.93", response.getPredictedChangePercent());
        assertEquals("HIGH", response.getConfidence());
        assertEquals("高可信", response.getConfidenceLabel());
    }

    @Test
    void 四个以上历史月份时只取最近三个() {
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00"),
                row("2026-05", "餐饮", "9999.00"),
                row("2026-04", "餐饮", "8888.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("1238.33", response.getPredictedAmount(), "更早的月份不能影响预测");
        assertEquals(3, response.getSampleMonths().size());
        assertEquals(List.of("2026-08", "2026-07", "2026-06"),
                months(response.getSampleMonths()));
    }

    @Test
    void 中间存在空月份时向后顺延取有支出的月份() {
        // 08 有数据、07 空、06 有数据、05 空、04 有数据
        stub(rows(row("2026-08", "餐饮", "1200.00"),
                row("2026-06", "餐饮", "1000.00"),
                row("2026-04", "餐饮", "900.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("OK", response.getStatus());
        assertEquals(List.of("2026-08", "2026-06", "2026-04"), months(response.getSampleMonths()));
        // (1200×3 + 1000×2 + 900×1) / 6 = 6500 / 6 = 1083.33
        assertEquals("1083.33", response.getPredictedAmount());
    }

    @Test
    void 连续月份按倒序取最近三个() {
        stub(rows(row("2026-08", "餐饮", "1200.00"),
                row("2026-07", "餐饮", "1100.00"),
                row("2026-06", "餐饮", "1000.00")));

        SpendingForecastResponse response = forecast();

        assertEquals(List.of("2026-08", "2026-07", "2026-06"), months(response.getSampleMonths()));
    }

    @Test
    void 本月数据只做展示不参与预测() {
        stub(rows(row("2026-09", "餐饮", "5000.00"),
                row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("5000.00", response.getCurrentMonthAmount());
        assertEquals(18, response.getElapsedDays());
        assertEquals("1238.33", response.getPredictedAmount(), "本月金额不能进入预测");
        assertTrue(months(response.getSampleMonths()).stream().noneMatch("2026-09"::equals));
    }

    @Test
    void 同一月份多条分类记录会先按月份合并() {
        stub(rows(row("2026-08", "餐饮", "1000.00"),
                row("2026-08", "交通", "250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("1250.00", response.getSampleMonths().get(0).getAmount());
        assertEquals("1238.33", response.getPredictedAmount());
    }

    @Test
    void 支出合计为零的月份不参与预测() {
        stub(rows(row("2026-08", "餐饮", "0.00"),
                row("2026-07", "餐饮", "1000.00"),
                row("2026-06", "餐饮", "900.00"),
                row("2026-05", "餐饮", "800.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("OK", response.getStatus());
        assertEquals("2026-07", response.getSampleMonths().get(0).getMonth(),
                "合计为 0 的月份不能被当成有效月份");
    }

    // ==================== 查询与 N+1 ====================

    @Test
    void 整个预测只执行一次聚合查询() {
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        forecast();

        verify(billMapper, times(1)).sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 查询窗口覆盖六个完整月与当前月() {
        stub(List.of());

        forecast();

        ArgumentCaptor<LocalDate> start = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<Integer> type = ArgumentCaptor.forClass(Integer.class);
        ArgumentCaptor<String> pattern = ArgumentCaptor.forClass(String.class);
        verify(billMapper).sumByCategoryAndMonth(anyLong(), type.capture(),
                start.capture(), end.capture(), pattern.capture());

        assertEquals(LocalDate.of(2026, 3, 1), start.getValue(), "参考月之前 6 个完整自然月");
        assertEquals(LocalDate.of(2026, 9, 18), end.getValue(), "读取到今天为止");
        assertEquals(BillType.EXPENSE.getCode(), type.getValue());
        assertEquals("%Y-%m", pattern.getValue());
    }

    @Test
    void 查询固定使用传入的用户标识() {
        stub(List.of());

        service.forecast(USER_ID, MONTH);
        service.forecast(99L, MONTH);

        ArgumentCaptor<Long> userIds = ArgumentCaptor.forClass(Long.class);
        verify(billMapper, times(2)).sumByCategoryAndMonth(userIds.capture(), anyInt(), any(), any(), anyString());
        assertEquals(List.of(USER_ID, 99L), userIds.getAllValues(), "用户 A 与用户 B 各自查询自己的数据");
    }

    // ==================== 加权与异常月 ====================

    @Test
    void 样本权重按时间倒序为三二一() {
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        List<ForecastSampleMonth> samples = forecast().getSampleMonths();

        assertEquals(List.of(3, 2, 1), weights(samples));
    }

    @Test
    void 最近月份权重最高() {
        // 只把最近一个月抬高，预测值应当明显大于另外两个月的金额
        stub(rows(row("2026-08", "餐饮", "2000.00"),
                row("2026-07", "餐饮", "1000.00"),
                row("2026-06", "餐饮", "1000.00")));

        SpendingForecastResponse response = forecast();

        // (2000×3 + 1000×2 + 1000×1) / 6 = 9000 / 6 = 1500.00
        assertEquals("1500.00", response.getPredictedAmount());
        assertEquals(3, response.getSampleMonths().get(0).getWeight());
    }

    @Test
    void 异常月份超过中位数两倍时权重降为一() {
        // 08 8500 明显异常：中位数 1200，阈值 2400 → 权重降为 1
        stub(rows(row("2026-08", "餐饮", "8500.00"),
                row("2026-07", "餐饮", "1200.00"),
                row("2026-06", "餐饮", "1100.00")));

        SpendingForecastResponse response = forecast();

        assertEquals(List.of(1, 2, 1), weights(response.getSampleMonths()));
        // (8500×1 + 1200×2 + 1100×1) / 4 = 12000 / 4 = 3000.00
        assertEquals("3000.00", response.getPredictedAmount());
    }

    @Test
    void 异常月份会导致置信度不高于中等() {
        stub(rows(row("2026-08", "餐饮", "8500.00"),
                row("2026-07", "餐饮", "1200.00"),
                row("2026-06", "餐饮", "1100.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("LOW", response.getConfidence());
        assertTrue(response.getConfidenceReason().contains("2026-08"), response.getConfidenceReason());
        assertTrue(response.getConfidenceReason().contains("已降低其权重"), response.getConfidenceReason());
    }

    @Test
    void 异常月封顶规则会把高可信降为中等() {
        // 直接验证封顶规则本身：极差比很小（本可以 HIGH），但存在异常月时只能是 MEDIUM
        List<BigDecimal> amounts = List.of(new BigDecimal("1000.00"),
                new BigDecimal("1010.00"), new BigDecimal("1020.00"));

        assertEquals("HIGH", SpendingForecastService.confidence(amounts, new BigDecimal("1010.00"), false));
        assertEquals("MEDIUM", SpendingForecastService.confidence(amounts, new BigDecimal("1010.00"), true));
    }

    @Test
    void 金额相同或接近时置信度为高可信() {
        stub(rows(row("2026-08", "餐饮", "1000.00"),
                row("2026-07", "餐饮", "1000.00"),
                row("2026-06", "餐饮", "1000.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("1000.00", response.getPredictedAmount());
        assertEquals("HIGH", response.getConfidence());
        assertEquals("0.00", response.getPredictedDifference());
        assertEquals("0.00", response.getPredictedChangePercent());
        assertTrue(response.getMessage().contains("持平"), response.getMessage());
    }

    @Test
    void 波动中等时置信度为中等可信() {
        // 极差比 = (1400 − 1000) / 1200 = 0.3333 → MEDIUM
        stub(rows(row("2026-08", "餐饮", "1200.00"),
                row("2026-07", "餐饮", "1400.00"),
                row("2026-06", "餐饮", "1000.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("MEDIUM", response.getConfidence());
        assertEquals("中等可信", response.getConfidenceLabel());
    }

    @Test
    void 波动过大时置信度为仅供参考() {
        // 极差比 = (1400 − 400) / 1000 = 1.0 → LOW
        stub(rows(row("2026-08", "餐饮", "1000.00"),
                row("2026-07", "餐饮", "1400.00"),
                row("2026-06", "餐饮", "400.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("LOW", response.getConfidence());
        assertEquals("仅供参考", response.getConfidenceLabel());
    }

    @Test
    void 置信度依据给出最高最低与相差比例() {
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        String reason = forecast().getConfidenceReason();

        assertTrue(reason.contains("近 3 个月"), reason);
        assertTrue(reason.contains("¥1320.00"), reason);
        assertTrue(reason.contains("¥1180.00"), reason);
        assertTrue(reason.contains("11.31%"), reason);
    }

    // ==================== 对比与变化率 ====================

    @Test
    void 预测高于最近有效月份时差额为正() {
        stub(rows(row("2026-08", "餐饮", "1000.00"),
                row("2026-07", "餐饮", "1000.00"),
                row("2026-06", "餐饮", "2000.00")));

        SpendingForecastResponse response = forecast();

        // (1000×3 + 1000×2 + 2000×1) / 6 = 7000 / 6 = 1166.67
        assertEquals("1166.67", response.getPredictedAmount());
        assertEquals("166.67", response.getPredictedDifference());
        assertEquals("16.67", response.getPredictedChangePercent());
        assertTrue(response.getMessage().contains("多 ¥166.67"), response.getMessage());
    }

    @Test
    void 预测低于最近有效月份时差额为负() {
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("-11.67", response.getPredictedDifference());
        assertEquals("-0.93", response.getPredictedChangePercent());
        assertTrue(response.getMessage().contains("少 ¥11.67"), response.getMessage());
    }

    @Test
    void 最近有效月份不是上一个月时对比基准随之变化() {
        // 2026-08 没有记录，最近有效月份是 2026-07
        stub(rows(row("2026-07", "餐饮", "1000.00"),
                row("2026-06", "餐饮", "1000.00"),
                row("2026-05", "餐饮", "1000.00")));

        SpendingForecastResponse response = forecast();

        assertEquals("1000.00", response.getPreviousMonthAmount());
        assertEquals("0.00", response.getPredictedDifference());
        assertTrue(response.getMessage().contains("2026-07"), response.getMessage());
    }

    @Test
    void 非OK状态不生成变化率() {
        stub(List.of());

        assertNull(forecast().getPredictedChangePercent());
    }

    // ==================== 金额边界 ====================

    @Test
    void 大金额保持精度() {
        stub(rows(row("2026-08", "餐饮", "5000000.00"),
                row("2026-07", "餐饮", "4000000.00"),
                row("2026-06", "餐饮", "6000000.00")));

        SpendingForecastResponse response = forecast();

        // (5000000×3 + 4000000×2 + 6000000×1) / 6 = 29000000 / 6 = 4833333.33
        assertEquals("4833333.33", response.getPredictedAmount());
    }

    @Test
    void 小金额按两位小数四舍五入() {
        stub(rows(row("2026-08", "餐饮", "0.03"),
                row("2026-07", "餐饮", "0.02"),
                row("2026-06", "餐饮", "0.01")));

        SpendingForecastResponse response = forecast();

        // (0.03×3 + 0.02×2 + 0.01×1) / 6 = 0.14 / 6 = 0.0233 → 0.02
        assertEquals("0.02", response.getPredictedAmount());
    }

    @Test
    void 预估金额带两位小数() {
        stub(rows(row("2026-08", "餐饮", "1000.00"),
                row("2026-07", "餐饮", "1000.00"),
                row("2026-06", "餐饮", "1001.00")));

        assertEquals("1000.17", forecast().getPredictedAmount());
    }

    // ==================== 参数与边界 ====================

    @Test
    void 月份格式错误返回400() {
        BizException error = assertThrows(BizException.class,
                () -> service.forecast(USER_ID, "2026-9"));

        assertEquals(400, error.getCode());
    }

    @Test
    void 月份为空返回400() {
        assertEquals(400, assertThrows(BizException.class,
                () -> service.forecast(USER_ID, "  ")).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> service.forecast(USER_ID, null)).getCode());
    }

    @Test
    void 未来月份返回NOT_APPLICABLE且不查库() {
        SpendingForecastResponse response = service.forecast(USER_ID, "2026-10");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertEquals("2026-11", response.getTargetMonth());
        assertEquals("0.00", response.getPredictedAmount());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 历史月份返回NOT_APPLICABLE() {
        SpendingForecastResponse response = service.forecast(USER_ID, "2026-08");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertEquals("2026-09", response.getTargetMonth());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 跨年时历史月份仍然正确() {
        Clock january = Clock.fixed(Instant.parse("2026-01-15T04:00:00Z"), ZoneId.of("Asia/Shanghai"));
        SpendingForecastService crossYear = new SpendingForecastService(billMapper, january);
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(rows(row("2025-12", "餐饮", "1200.00"),
                        row("2025-11", "餐饮", "1100.00"),
                        row("2025-10", "餐饮", "1000.00")));

        SpendingForecastResponse response = crossYear.forecast(USER_ID, "2026-01");

        assertEquals("OK", response.getStatus());
        assertEquals("2026-02", response.getTargetMonth());
        assertEquals(List.of("2025-12", "2025-11", "2025-10"), months(response.getSampleMonths()));
    }

    @Test
    void 非OK状态的置信度为NONE且无样本() {
        stub(List.of());

        SpendingForecastResponse response = forecast();

        assertEquals("NONE", response.getConfidence());
        assertEquals("", response.getConfidenceLabel());
        assertEquals("", response.getConfidenceReason());
        assertTrue(response.getSampleMonths().isEmpty());
        assertEquals("2026-09", response.getMonth());
    }

    @Test
    void OK状态的样本与依据都不为空() {
        stub(rows(row("2026-08", "餐饮", "1250.00"),
                row("2026-07", "餐饮", "1180.00"),
                row("2026-06", "餐饮", "1320.00")));

        SpendingForecastResponse response = forecast();

        assertEquals(3, response.getSampleMonths().size());
        assertNotNull(response.getConfidenceReason());
        assertTrue(response.getConfidenceReason().length() > 0);
        assertTrue(response.getMessage().contains("2026-10"), response.getMessage());
    }

    // ==================== 辅助方法 ====================

    private SpendingForecastResponse forecast() {
        return service.forecast(USER_ID, MONTH);
    }

    private void stub(List<CategoryMonthlySum> rows) {
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(rows);
    }

    private static List<CategoryMonthlySum> rows(CategoryMonthlySum... items) {
        return new ArrayList<>(List.of(items));
    }

    private static CategoryMonthlySum row(String month, String category, String amount) {
        CategoryMonthlySum sum = new CategoryMonthlySum();
        sum.setMonth(month);
        sum.setCategory(category);
        sum.setAmount(new BigDecimal(amount));
        sum.setCount(1);
        return sum;
    }

    private static List<String> months(List<ForecastSampleMonth> samples) {
        List<String> result = new ArrayList<>(samples.size());
        for (ForecastSampleMonth sample : samples) {
            result.add(sample.getMonth());
        }
        return result;
    }

    private static List<Integer> weights(List<ForecastSampleMonth> samples) {
        List<Integer> result = new ArrayList<>(samples.size());
        for (ForecastSampleMonth sample : samples) {
            result.add(sample.getWeight());
        }
        return result;
    }
}
