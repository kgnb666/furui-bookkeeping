package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.AnomaliesResponse;
import com.campus.ledger.dto.AnomalyItem;
import com.campus.ledger.dto.CategoryMonthlySum;
import com.campus.ledger.dto.ExpenseDetail;
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
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 消费异常检测测试。时间固定在 2026-09-17，
 * 目标月份统一用 2026-09，基线月份为 2026-06 / 07 / 08。
 */
@ExtendWith(MockitoExtension.class)
class SpendingAnomalyServiceTest {

    private static final Long USER_ID = 31L;
    private static final String MONTH = "2026-09";
    private static final Clock FIXED = Clock.fixed(
            Instant.parse("2026-09-17T04:00:00Z"), ZoneId.of("Asia/Shanghai"));

    @Mock
    private BillMapper billMapper;

    private SpendingAnomalyService service;

    @BeforeEach
    void setUp() {
        service = new SpendingAnomalyService(billMapper, FIXED);
    }

    // ==================== 规则 1：CATEGORY_SPIKE ====================

    @Test
    void 分类月度上涨触发MEDIUM() {
        // 前三个月均 400 → 基线 400；本月 700（1.75 倍，差额 300）
        stub(monthly("餐饮", 400, 400, 400, 700), details());

        AnomalyItem item = onlyOfType(detect(), "CATEGORY_SPIKE");

        assertEquals("MEDIUM", item.getSeverity());
        assertEquals("留意", item.getSeverityLabel());
        assertEquals("餐饮", item.getCategory());
        assertEquals("700.00", item.getCurrentAmount());
        assertEquals("400.00", item.getBaselineAmount());
        assertEquals("300.00", item.getDifference());
        assertEquals("75.00", item.getChangePercent());
        assertTrue(item.getMessage().contains("多支出 ¥300.00"), item.getMessage());
    }

    @Test
    void 分类月度上涨超过二点五倍为HIGH() {
        stub(monthly("餐饮", 400, 400, 400, 1200), details());

        AnomalyItem item = onlyOfType(detect(), "CATEGORY_SPIKE");

        assertEquals("HIGH", item.getSeverity());
        assertEquals("需注意", item.getSeverityLabel());
        assertEquals("200.00", item.getChangePercent());
    }

    @Test
    void 上涨不足一点五倍时不触发() {
        // 基线 400，本月 560（1.4 倍），低于 1.5 倍门槛
        stub(monthly("餐饮", 400, 400, 400, 560), details());

        assertEquals("NO_ANOMALY", detect().getStatus());
    }

    @Test
    void 倍数达标但差额不足一百时不触发() {
        // 基线 20，本月 40（2 倍），但只多了 20 元
        stub(monthly("通讯", 20, 20, 20, 40), details());

        assertEquals("NO_ANOMALY", detect().getStatus(), "小额波动不应提醒");
    }

    @Test
    void 前三个月完全没有数据时返回NOT_ENOUGH_BASELINE() {
        // 只有目标月有数据
        List<CategoryMonthlySum> rows = List.of(sum("餐饮", MONTH, 700, 5));
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(rows);

        AnomaliesResponse response = detect();

        assertEquals("NOT_ENOUGH_BASELINE", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertTrue(response.getMessage().contains("积累几个月"), response.getMessage());
    }

    @Test
    void 基线只对有消费的月份取平均() {
        // 6 月无记录，7 月 400、8 月 600 → 有效月份 2 个 → 基线 500
        List<CategoryMonthlySum> rows = List.of(
                sum("餐饮", "2026-07", 400, 4),
                sum("餐饮", "2026-08", 600, 4),
                sum("餐饮", MONTH, 1000, 6));
        stubRaw(rows, details());

        AnomalyItem item = onlyOfType(detect(), "CATEGORY_SPIKE");

        assertEquals("500.00", item.getBaselineAmount(), "缺失月份不应按 0 计入平均");
        assertEquals("100.00", item.getChangePercent());
    }

    @Test
    void 基线的响应字段包含前三个自然月() {
        stub(monthly("餐饮", 400, 400, 400, 700), details());

        assertEquals(List.of("2026-06", "2026-07", "2026-08"), detect().getBaselineMonths());
    }

    // ==================== 规则 2：LARGE_TRANSACTION ====================

    @Test
    void 单笔显著高于同分类中位数时为HIGH() {
        // 基线（目标月之前）5 笔 20 元 → 中位数 20；
        // 目标月单笔 300 → 15 倍（≥5）→ HIGH，差额 280 ≥ 100
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("餐饮", "20.00", "2026-08-10", "食堂"));
        }
        details.add(detail("餐饮", "300.00", "2026-09-12", "某餐厅"));
        stub(monthly("餐饮", 100, 100, 100, 400), details);

        AnomalyItem item = onlyOfType(detect(), "LARGE_TRANSACTION");

        assertEquals("HIGH", item.getSeverity());
        assertEquals("餐饮", item.getCategory());
        assertEquals("300.00", item.getCurrentAmount());
        assertEquals("20.00", item.getBaselineAmount());
        assertEquals("某餐厅", item.getMerchant());
        assertEquals("2026-09-12", item.getBillDate());
        assertTrue(item.getMessage().contains("15.0 倍"), item.getMessage());
    }

    @Test
    void 单笔达到五倍时为HIGH() {
        // 基线中位数 60，目标月单笔 400 → 6.7 倍（≥5）→ HIGH
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("购物", "60.00", "2026-08-05", "某店"));
        }
        details.add(detail("购物", "400.00", "2026-09-03", "数码店"));
        stub(monthly("购物", 120, 120, 120, 520), details);

        assertEquals("HIGH", onlyOfType(detect(), "LARGE_TRANSACTION").getSeverity());
    }

    @Test
    void 单笔约为中位数三点六倍时为MEDIUM() {
        // 中位数 60，单笔 200 → 3.3 倍（≥3 且 <5），差额 140 ≥ 100 → MEDIUM
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("学习", "60.00", "2026-08-05", "书店"));
        }
        details.add(detail("学习", "200.00", "2026-09-05", "教材中心"));
        stub(monthly("学习", 100, 100, 100, 300), details);

        AnomalyItem item = onlyOfType(detect(), "LARGE_TRANSACTION");

        assertEquals("60.00", item.getBaselineAmount());
        assertTrue(item.getMessage().contains("约为 3.3 倍"), item.getMessage());
        assertEquals("MEDIUM", item.getSeverity());
    }

    @Test
    void 商户为空时用分类与日期定位且不丢弃() {
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("餐饮", "20.00", "2026-08-10", ""));
        }
        details.add(detail("餐饮", "300.00", "2026-09-12", ""));
        stub(monthly("餐饮", 100, 100, 100, 400), details);

        AnomalyItem item = onlyOfType(detect(), "LARGE_TRANSACTION");

        assertEquals("餐饮", item.getMerchant(), "商户为空时回退到分类名");
        assertEquals("2026-09-12", item.getBillDate());
    }

    @Test
    void 分类样本不足五笔时不做单笔判断() {
        // 餐饮只有 4 笔：20/20/20/300，样本不足
        List<ExpenseDetail> details = List.of(
                detail("餐饮", "20.00", "2026-08-10", "食堂"),
                detail("餐饮", "20.00", "2026-08-11", "食堂"),
                detail("餐饮", "20.00", "2026-08-12", "食堂"),
                detail("餐饮", "300.00", "2026-09-12", "某餐厅"));
        stub(monthly("餐饮", 100, 100, 100, 360), details);

        assertTrue(detect().getItems().stream()
                .noneMatch(item -> "LARGE_TRANSACTION".equals(item.getType())));
    }

    @Test
    void 中位数取奇数个样本时取中间那位() {
        // 10 / 20 / 20 / 30 / 40 → 排序后中间那位是 20
        List<ExpenseDetail> details = List.of(
                detail("学习", "10.00", "2026-08-01", "书店"),
                detail("学习", "20.00", "2026-08-02", "书店"),
                detail("学习", "20.00", "2026-08-03", "书店"),
                detail("学习", "30.00", "2026-08-04", "书店"),
                detail("学习", "40.00", "2026-08-06", "书店"),
                detail("学习", "300.00", "2026-09-05", "教材中心"));
        stub(monthly("学习", 25, 25, 25, 400), details);

        AnomalyItem item = onlyOfType(detect(), "LARGE_TRANSACTION");

        assertEquals("20.00", item.getBaselineAmount());
        assertEquals("2026-09-05", item.getBillDate());
    }

    @Test
    void 中位数取偶数个样本的中间两笔平均() {
        // 10 / 20 / 30 / 40 / 50 / 60 → 偶数个样本取中间两位平均 = 35
        List<ExpenseDetail> details = List.of(
                detail("学习", "10.00", "2026-08-01", "书店"),
                detail("学习", "20.00", "2026-08-02", "书店"),
                detail("学习", "30.00", "2026-08-03", "书店"),
                detail("学习", "40.00", "2026-08-04", "书店"),
                detail("学习", "50.00", "2026-08-05", "书店"),
                detail("学习", "60.00", "2026-08-07", "书店"),
                detail("学习", "500.00", "2026-09-05", "教材中心"));
        stub(monthly("学习", 30, 30, 30, 650), details);

        assertEquals("35.00", onlyOfType(detect(), "LARGE_TRANSACTION").getBaselineAmount());
    }

    @Test
    void 单笔倍数不足三倍时不触发() {
        // 中位数 100，单笔 280（2.8 倍）
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("购物", "100.00", "2026-08-05", "某店"));
        }
        details.add(detail("购物", "280.00", "2026-09-03", "数码店"));
        stub(monthly("购物", 200, 200, 200, 780), details);

        assertTrue(detect().getItems().stream()
                .noneMatch(item -> "LARGE_TRANSACTION".equals(item.getType())));
    }

    @Test
    void 单笔倍数达标但差额不足一百时不触发() {
        // 中位数 10，单笔 40（4 倍），但只多了 30 元
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("通讯", "10.00", "2026-08-05", "运营商"));
        }
        details.add(detail("通讯", "40.00", "2026-09-03", "运营商"));
        stub(monthly("通讯", 20, 20, 20, 90), details);

        assertTrue(detect().getItems().stream()
                .noneMatch(item -> "LARGE_TRANSACTION".equals(item.getType())));
    }

    @Test
    void 单笔异常只报目标月份内的账单() {
        // 目标月是 2026-09，7 月那笔 500 不应被报出来
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("购物", "50.00", "2026-08-05", "某店"));
        }
        details.add(detail("购物", "500.00", "2026-07-20", "旧账单"));
        stub(monthly("购物", 250, 100, 100, 100), details);

        assertTrue(detect().getItems().stream()
                .noneMatch(item -> "LARGE_TRANSACTION".equals(item.getType())),
                "基线窗口内的历史账单本身不应被报为异常");
    }

    @Test
    void 多笔单笔异常都会返回并按金额差额排序() {
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("购物", "50.00", "2026-08-05", "某店"));
        }
        details.add(detail("购物", "200.00", "2026-09-03", "小店"));
        details.add(detail("购物", "900.00", "2026-09-08", "大店"));
        stub(monthly("购物", 250, 250, 250, 1300), details);

        List<AnomalyItem> large = detect().getItems().stream()
                .filter(item -> "LARGE_TRANSACTION".equals(item.getType())).toList();

        assertEquals(2, large.size(), "同月多笔异常都要返回");
        assertEquals("900.00", large.get(0).getCurrentAmount(), "差额大的排前面");
        assertEquals("200.00", large.get(1).getCurrentAmount());
    }

    // ==================== 规则 3：FREQUENCY_SPIKE ====================

    @Test
    void 消费笔数翻倍触发MEDIUM() {
        // 基线每月 4 笔，本月 10 笔（2.5 倍），多 6 笔
        stub(monthlyCounts("餐饮", 4, 4, 4, 10, 400), details());

        AnomalyItem item = onlyOfType(detect(), "FREQUENCY_SPIKE");

        assertEquals("MEDIUM", item.getSeverity());
        assertEquals("10", item.getCurrentAmount());
        assertEquals("4", item.getBaselineAmount());
        assertEquals("6", item.getDifference());
        assertTrue(item.getMessage().contains("多 6 笔"), item.getMessage());
    }

    @Test
    void 消费笔数达到三倍时为HIGH() {
        stub(monthlyCounts("餐饮", 4, 4, 4, 12, 400), details());

        assertEquals("HIGH", onlyOfType(detect(), "FREQUENCY_SPIKE").getSeverity());
    }

    @Test
    void 基线笔数不足两笔时不判断频次() {
        // 基线每月 1 笔，本月 8 笔——虽然涨得多，但"每月 1 次"谈不上频次习惯
        stub(monthlyCounts("医疗", 1, 1, 1, 8, 400), details());

        assertTrue(detect().getItems().stream()
                .noneMatch(item -> "FREQUENCY_SPIKE".equals(item.getType())));
    }

    @Test
    void 笔数达标但增量不足五笔时不触发() {
        // 基线 3 笔，本月 7 笔（2.3 倍），但只多了 4 笔
        stub(monthlyCounts("餐饮", 3, 3, 3, 7, 400), details());

        assertTrue(detect().getItems().stream()
                .noneMatch(item -> "FREQUENCY_SPIKE".equals(item.getType())));
    }

    @Test
    void 频次基线同样只对有消费的月份取平均() {
        // 6 月无记录，7 月 4 笔、8 月 8 笔 → 基线 6，本月 18 笔（3 倍）
        List<CategoryMonthlySum> rows = List.of(
                sum("餐饮", "2026-07", 100, 4),
                sum("餐饮", "2026-08", 200, 8),
                sum("餐饮", MONTH, 400, 18));
        stubRaw(rows, details());

        AnomalyItem item = onlyOfType(detect(), "FREQUENCY_SPIKE");

        assertEquals("6", item.getBaselineAmount());
        assertEquals("12", item.getDifference());
    }

    // ==================== status 分支 ====================

    @Test
    void 目标月份没有支出时返回NO_DATA() {
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(List.of(sum("餐饮", "2026-08", 400, 4)));

        AnomaliesResponse response = detect();

        assertEquals("NO_DATA", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertTrue(response.getMessage().contains("还没有支出记录"), response.getMessage());
    }

    @Test
    void 有目标月数据且无异常时返回NO_ANOMALY() {
        stub(monthly("餐饮", 400, 400, 400, 400), details());

        AnomaliesResponse response = detect();

        assertEquals("NO_ANOMALY", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertTrue(response.getMessage().contains("正常"), response.getMessage());
    }

    @Test
    void 检测到异常时返回OK并给出数量() {
        stub(monthly("餐饮", 400, 400, 400, 1200), details());

        AnomaliesResponse response = detect();

        assertEquals("OK", response.getStatus());
        assertEquals(1, response.getItems().size());
        assertTrue(response.getMessage().contains("1 处"), response.getMessage());
    }

    @Test
    void 只有基线月数据时按无本月数据返回NO_DATA() {
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(List.of(
                sum("餐饮", "2026-07", 400, 4),
                sum("餐饮", "2026-08", 500, 5)));

        assertEquals("NO_DATA", detect().getStatus());
    }

    // ==================== 排序与上限 ====================

    @Test
    void HIGH优先于MEDIUM() {
        // 餐饮 HIGH（3 倍上涨）；购物 MEDIUM（2 倍上涨，差额较小）
        List<CategoryMonthlySum> rows = List.of(
                sum("餐饮", "2026-06", 400, 4), sum("餐饮", "2026-07", 400, 4),
                sum("餐饮", "2026-08", 400, 4), sum("餐饮", MONTH, 1400, 6),
                sum("购物", "2026-06", 200, 2), sum("购物", "2026-07", 200, 2),
                sum("购物", "2026-08", 200, 2), sum("购物", MONTH, 400, 2));
        stubRaw(rows, details());

        List<AnomalyItem> items = detect().getItems();

        assertEquals("HIGH", items.get(0).getSeverity());
        assertEquals("餐饮", items.get(0).getCategory());
        assertEquals("MEDIUM", items.get(1).getSeverity());
    }

    @Test
    void 同级异常按差额降序() {
        List<CategoryMonthlySum> rows = List.of(
                // 差额 200
                sum("购物", "2026-06", 200, 2), sum("购物", "2026-07", 200, 2),
                sum("购物", "2026-08", 200, 2), sum("购物", MONTH, 400, 2),
                // 差额 500
                sum("餐饮", "2026-06", 400, 4), sum("餐饮", "2026-07", 400, 4),
                sum("餐饮", "2026-08", 400, 4), sum("餐饮", MONTH, 900, 5));
        stubRaw(rows, details());

        List<AnomalyItem> items = detect().getItems();

        assertEquals("餐饮", items.get(0).getCategory(), "同级时差额大的排前面");
        assertEquals("购物", items.get(1).getCategory());
    }

    @Test
    void 结果最多五条() {
        List<CategoryMonthlySum> rows = new ArrayList<>();
        // 6 个分类同时触发上涨，每个差额递增
        for (int i = 0; i < 6; i++) {
            String category = "分类" + i;
            int baseline = 100;
            int current = 500 + i * 100;
            for (String month : List.of("2026-06", "2026-07", "2026-08")) {
                rows.add(sum(category, month, baseline, 2));
            }
            rows.add(sum(category, MONTH, current, 3));
        }
        stubRaw(rows, details());

        List<AnomalyItem> items = detect().getItems();

        assertEquals(SpendingAnomalyService.MAX_ITEMS, items.size());
        assertEquals("分类5", items.get(0).getCategory(), "差额最大的应保留");
    }

    // ==================== 参数校验 ====================

    @Test
    void 月份格式错误返回400() {
        BizException e = assertThrows(BizException.class,
                () -> service.detect(USER_ID, "2026-13-01"));

        assertEquals(400, e.getCode());
    }

    @Test
    void 月份为空返回400() {
        BizException e = assertThrows(BizException.class, () -> service.detect(USER_ID, null));

        assertEquals(400, e.getCode());
    }

    @Test
    void 超过十二个月的历史月份返回400() {
        // 当前 2026-09，最早允许 2025-09（12 个月前）
        BizException e = assertThrows(BizException.class,
                () -> service.detect(USER_ID, "2025-08"));

        assertEquals(400, e.getCode());
        assertTrue(e.getMessage().contains("12"), e.getMessage());
    }

    @Test
    void 恰好十二个月前的月份允许查询() {
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(List.of(sum("餐饮", MONTH, 400, 4)));

        AnomaliesResponse response = service.detect(USER_ID, "2025-09");

        assertEquals("2025-09", response.getMonth());
        // 该月没有数据，返回 NO_DATA 而不是抛异常
        assertEquals("NO_DATA", response.getStatus());
    }

    @Test
    void 未来月份返回400() {
        BizException e = assertThrows(BizException.class,
                () -> service.detect(USER_ID, "2026-10"));

        assertEquals(400, e.getCode());
        assertTrue(e.getMessage().contains("未来"), e.getMessage());
    }

    // ==================== 安全与查询方式 ====================

    @Test
    void 两个查询都固定带当前登录用户与支出类型() {
        stub(monthly("餐饮", 400, 400, 400, 700), details());

        detect();

        ArgumentCaptor<Long> monthlyUser = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<Integer> monthlyType = ArgumentCaptor.forClass(Integer.class);
        verify(billMapper).sumByCategoryAndMonth(monthlyUser.capture(), monthlyType.capture(),
                any(), any(), anyString());
        assertEquals(USER_ID, monthlyUser.getValue(), "月度聚合必须限定当前用户");
        assertEquals(1, monthlyType.getValue(), "只分析支出");

        ArgumentCaptor<Long> detailUser = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<Integer> detailType = ArgumentCaptor.forClass(Integer.class);
        verify(billMapper).selectExpenseDetails(detailUser.capture(), detailType.capture(),
                any(), any(), anyInt());
        assertEquals(USER_ID, detailUser.getValue(), "明细查询必须限定当前用户");
        assertEquals(1, detailType.getValue(), "只分析支出");
    }

    @Test
    void 明细查询只调用一次且不按分类循环查库() {
        List<CategoryMonthlySum> rows = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            String category = "分类" + i;
            rows.add(sum(category, "2026-08", 100, 2));
            rows.add(sum(category, MONTH, 120, 2));
        }
        stubRaw(rows, details());

        detect();

        // 10 个分类依然只查两次：一次月度聚合 + 一次明细
        verify(billMapper, times(1)).sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString());
        verify(billMapper, times(1)).selectExpenseDetails(anyLong(), anyInt(), any(), any(), anyInt());
    }

    @Test
    void 明细查询覆盖基线窗口与目标月且带上限() {
        stub(monthly("餐饮", 400, 400, 400, 700), details());

        detect();

        ArgumentCaptor<LocalDate> start = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<Integer> limit = ArgumentCaptor.forClass(Integer.class);
        verify(billMapper).selectExpenseDetails(anyLong(), anyInt(), start.capture(), end.capture(),
                limit.capture());

        assertEquals(LocalDate.of(2026, 9, 30), end.getValue(), "窗口结束于目标月末");
        assertEquals(LocalDate.of(2026, 9, 1).minusDays(91), start.getValue(),
                "起点为目标月之前 90 天");
        assertEquals(SpendingAnomalyService.MAX_DETAIL_ROWS, limit.getValue());
    }

    @Test
    void 两个用户的结果互不影响() {
        // 用户 A 有异常，用户 B 没有目标月数据
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(monthly("餐饮", 400, 400, 400, 1200))
                .thenReturn(List.of(sum("餐饮", "2026-08", 400, 4)));
        when(billMapper.selectExpenseDetails(anyLong(), anyInt(), any(), any(), anyInt()))
                .thenReturn(List.of());

        AnomaliesResponse forA = service.detect(USER_ID, MONTH);
        AnomaliesResponse forB = service.detect(USER_ID + 1, MONTH);

        assertEquals("OK", forA.getStatus());
        assertEquals("NO_DATA", forB.getStatus(), "B 没有本月数据，不应看到 A 的异常");
        assertTrue(forB.getItems().isEmpty());
    }

    @Test
    void 月度聚合查询的日期范围覆盖前三个月() {
        stub(monthly("餐饮", 400, 400, 400, 700), details());

        detect();

        ArgumentCaptor<LocalDate> start = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper).sumByCategoryAndMonth(anyLong(), anyInt(), start.capture(), end.capture(),
                anyString());

        assertEquals(LocalDate.of(2026, 6, 1), start.getValue());
        assertEquals(LocalDate.of(2026, 9, 30), end.getValue());
    }

    @Test
    void 中位数工具方法忽略空金额() {
        List<ExpenseDetail> details = new ArrayList<>();
        details.add(detail("餐饮", "10.00", "2026-08-01", "食堂"));
        details.add(detail("餐饮", null, "2026-08-02", "食堂"));
        details.add(detail("餐饮", "30.00", "2026-08-03", "食堂"));

        assertEquals(0, SpendingAnomalyService.medianAmount(details).compareTo(new BigDecimal("20.00")));
    }

    @Test
    void 中位数工具方法在无有效金额时返回零() {
        List<ExpenseDetail> details = new ArrayList<>();
        details.add(detail("餐饮", null, "2026-08-01", "食堂"));

        assertEquals(0, SpendingAnomalyService.medianAmount(details).signum());
    }

    @Test
    void 三类异常可以同时出现在结果中() {
        // 餐饮金额暴涨 + 笔数暴涨 + 一笔大额
        List<CategoryMonthlySum> rows = List.of(
                sum("餐饮", "2026-06", 200, 4), sum("餐饮", "2026-07", 200, 4),
                sum("餐饮", "2026-08", 200, 4), sum("餐饮", MONTH, 1500, 12));
        List<ExpenseDetail> details = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            details.add(detail("餐饮", "50.00", "2026-08-05", "食堂"));
        }
        details.add(detail("餐饮", "600.00", "2026-09-10", "某餐厅"));
        stubRaw(rows, details);

        List<String> types = detect().getItems().stream().map(AnomalyItem::getType).toList();

        assertTrue(types.contains("CATEGORY_SPIKE"));
        assertTrue(types.contains("FREQUENCY_SPIKE"));
        assertTrue(types.contains("LARGE_TRANSACTION"));
    }

    @Test
    void 异常项不包含技术性辅助字段之外的内容() {
        stub(monthly("餐饮", 400, 400, 400, 700), details());

        AnomalyItem item = onlyOfType(detect(), "CATEGORY_SPIKE");

        // 金额一律是字符串，不做浮点运算
        assertNotNull(item.getCurrentAmount());
        assertNotNull(item.getBaselineAmount());
        assertNotNull(item.getDifference());
        assertNotNull(item.getChangePercent());
        // 分类类异常的商户与日期为空
        assertNull(item.getMerchant());
        assertNull(item.getBillDate());
        assertFalse(item.getTitle().isEmpty());
    }

    // ==================== 测试数据构造 ====================

    private AnomaliesResponse detect() {
        return service.detect(USER_ID, MONTH);
    }

    private AnomalyItem onlyOfType(AnomaliesResponse response, String type) {
        List<AnomalyItem> items = response.getItems().stream()
                .filter(item -> type.equals(item.getType())).toList();
        assertEquals(1, items.size(), "期望恰好一条 " + type + "，实际 " + items.size());
        return items.get(0);
    }

    private void stub(List<CategoryMonthlySum> rows, List<ExpenseDetail> details) {
        stubRaw(rows, details);
    }

    private void stubRaw(List<CategoryMonthlySum> rows, List<ExpenseDetail> details) {
        when(billMapper.sumByCategoryAndMonth(anyLong(), anyInt(), any(), any(), anyString()))
                .thenReturn(rows);
        when(billMapper.selectExpenseDetails(anyLong(), anyInt(), any(), any(), anyInt()))
                .thenReturn(details);
    }

    /** 同一分类：前三个月金额、本月金额 */
    private List<CategoryMonthlySum> monthly(String category, int m1, int m2, int m3, int current) {
        return List.of(
                sum(category, "2026-06", m1, 4),
                sum(category, "2026-07", m2, 4),
                sum(category, "2026-08", m3, 4),
                sum(category, MONTH, current, 4));
    }

    /** 同一分类：前三个月笔数、本月笔数（金额按笔数等比例放大，避免误触金额规则） */
    private List<CategoryMonthlySum> monthlyCounts(String category, int c1, int c2, int c3,
                                                   int current, int currentAmount) {
        return List.of(
                sum(category, "2026-06", c1 * 10, c1),
                sum(category, "2026-07", c2 * 10, c2),
                sum(category, "2026-08", c3 * 10, c3),
                sum(category, MONTH, currentAmount, current));
    }

    private CategoryMonthlySum sum(String category, String month, int amount, int count) {
        CategoryMonthlySum sum = new CategoryMonthlySum();
        sum.setCategory(category);
        sum.setMonth(month);
        sum.setAmount(new BigDecimal(amount).setScale(2));
        sum.setCount(count);
        return sum;
    }

    private ExpenseDetail detail(String category, String amount, String date, String merchant) {
        ExpenseDetail detail = new ExpenseDetail();
        detail.setCategory(category);
        detail.setAmount(amount == null ? null : new BigDecimal(amount));
        detail.setBillDate(LocalDate.parse(date));
        detail.setMerchant(merchant);
        return detail;
    }

    private List<ExpenseDetail> details() {
        return List.of();
    }
}
