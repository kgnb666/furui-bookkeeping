package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.common.BillType;
import com.campus.ledger.dto.ExpenseDetail;
import com.campus.ledger.dto.MerchantSpendingItem;
import com.campus.ledger.dto.SpendingMerchantResponse;
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
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * 消费对象分析测试。时间固定在 2026-09-18，参考月固定为 2026-09（30 天）。
 * 需要验证其它月长时另建固定时钟的 Service。
 */
@ExtendWith(MockitoExtension.class)
class SpendingMerchantServiceTest {

    private static final Long USER_ID = 41L;
    private static final String MONTH = "2026-09";
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final Clock FIXED = Clock.fixed(Instant.parse("2026-09-18T04:00:00Z"), ZONE);

    @Mock
    private BillMapper billMapper;

    private SpendingMerchantService service;

    @BeforeEach
    void setUp() {
        service = new SpendingMerchantService(billMapper, FIXED);
    }

    // ==================== 数据聚合 ====================

    @Test
    void 单商户时因对象不足返回INSUFFICIENT_DATA并保留事实数据() {
        stub(List.of(expense(d(1), "100.00", "食堂"),
                expense(d(2), "200.00", "食堂"),
                expense(d(3), "300.00", "食堂")));

        SpendingMerchantResponse response = analyze();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals("600.00", response.getTotalAmount());
        assertEquals(3, response.getTotalCount());
        assertEquals(1, response.getMerchantCount());
        assertEquals("100.00", response.getMerchantCoverage());
        assertTrue(response.getTopMerchants().isEmpty(), "数据不足时不给排行结论");
    }

    @Test
    void 多商户按金额降序排列() {
        stub(List.of(expense(d(1), "300.00", "全家"),
                expense(d(2), "500.00", "食堂"),
                expense(d(3), "100.00", "奶茶店")));

        SpendingMerchantResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals(List.of("食堂", "全家", "奶茶店"), names(response));
        assertEquals("500.00", response.getTopMerchants().get(0).getAmount());
    }

    @Test
    void 同商户多笔合并金额与笔数() {
        stub(List.of(expense(d(1), "100.00", "食堂"),
                expense(d(2), "50.00", "食堂"),
                expense(d(3), "200.00", "超市"),
                expense(d(4), "150.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals(2, response.getMerchantCount());
        assertEquals("500.00", response.getTotalAmount());
        assertEquals(4, response.getTotalCount());
        MerchantSpendingItem first = response.getTopMerchants().get(0);
        assertEquals("超市", first.getMerchantName());
        assertEquals("350.00", first.getAmount());
        assertEquals(2, first.getCount());
    }

    @Test
    void 金额与笔数汇总正确() {
        stub(healthy());

        SpendingMerchantResponse response = analyze();

        assertEquals("1000.00", response.getTotalAmount());
        assertEquals(4, response.getTotalCount());
    }

    @Test
    void 空明细返回NO_DATA() {
        stub(List.of());

        SpendingMerchantResponse response = analyze();

        assertEquals("NO_DATA", response.getStatus());
        assertEquals("0.00", response.getTotalAmount());
        assertEquals(0, response.getTotalCount());
        assertEquals(0, response.getMerchantCount());
        assertTrue(response.getTopMerchants().isEmpty());
    }

    // ==================== 商户清洗 ====================

    @Test
    void 前后空格会被清洗并合并() {
        stub(List.of(expense(d(1), "100.00", "  食堂  "),
                expense(d(2), "100.00", "食堂"),
                expense(d(3), "100.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals(2, response.getMerchantCount());
        assertEquals("食堂", response.getTopMerchants().get(0).getMerchantName());
        assertEquals(2, response.getTopMerchants().get(0).getCount());
    }

    @Test
    void 连续空格会被压缩为一个空格() {
        stub(List.of(expense(d(1), "100.00", "校园   超市"),
                expense(d(2), "100.00", "校园 超市"),
                expense(d(3), "100.00", "食堂")));

        SpendingMerchantResponse response = analyze();

        assertEquals(2, response.getMerchantCount());
        assertEquals("校园 超市", names(response).get(0));
    }

    @Test
    void 大小写不同视为同一个消费对象且展示名保留首次出现的大小写() {
        stub(List.of(expense(d(1), "100.00", "Starbucks"),
                expense(d(2), "100.00", "STARBUCKS"),
                expense(d(3), "100.00", "starbucks"),
                expense(d(4), "50.00", "食堂")));

        SpendingMerchantResponse response = analyze();

        assertEquals(2, response.getMerchantCount());
        assertEquals("Starbucks", names(response).get(0), "展示名保留第一条记录的写法");
        assertEquals(3, response.getTopMerchants().get(0).getCount());
        assertEquals("300.00", response.getTopMerchants().get(0).getAmount());
    }

    @Test
    void 不剥离店后缀不同门店保持两个对象() {
        stub(List.of(expense(d(1), "100.00", "星巴克"),
                expense(d(2), "100.00", "星巴克店"),
                expense(d(3), "100.00", "食堂")));

        SpendingMerchantResponse response = analyze();

        assertEquals(3, response.getMerchantCount(), "不允许把不同门店错误合并");
        assertTrue(names(response).contains("星巴克"));
        assertTrue(names(response).contains("星巴克店"));
    }

    @Test
    void 不做同义词合并() {
        stub(List.of(expense(d(1), "100.00", "美团外卖"),
                expense(d(2), "100.00", "饿了么"),
                expense(d(3), "100.00", "食堂")));

        assertEquals(3, analyze().getMerchantCount());
    }

    @Test
    void 空商户与纯空格商户归入未填写() {
        stub(List.of(expense(d(1), "100.00", ""),
                expense(d(2), "100.00", "   "),
                expense(d(3), "100.00", null),
                expense(d(1), "100.00", "食堂"),
                expense(d(2), "100.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals(2, response.getMerchantCount(), "未填写不计入消费对象");
        assertEquals("300.00", response.getUnknownMerchantAmount());
        assertEquals(5, response.getTotalCount());
    }

    // ==================== 指标 ====================

    @Test
    void 整体客单价等于总额除以笔数() {
        stub(healthy());

        SpendingMerchantResponse response = analyze();

        // 1000 / 4 = 250
        assertEquals("250.00", response.getAverageAmount());
    }

    @Test
    void 消费对象数量按归一化去重统计() {
        stub(List.of(expense(d(1), "10.00", "A"),
                expense(d(2), "10.00", "a"),
                expense(d(3), "10.00", "B"),
                expense(d(4), "10.00", "C")));

        assertEquals(3, analyze().getMerchantCount());
    }

    @Test
    void Top3集中度按Top3金额计算() {
        stub(List.of(expense(d(1), "400.00", "A"),
                expense(d(2), "300.00", "B"),
                expense(d(3), "200.00", "C"),
                expense(d(4), "100.00", "D")));

        SpendingMerchantResponse response = analyze();

        // (400 + 300 + 200) / 1000 = 90%
        assertEquals("90.00", response.getTop3Concentration());
    }

    @Test
    void 消费对象少于三个时集中度为一百() {
        stub(healthy());

        assertEquals("100.00", analyze().getTop3Concentration());
    }

    @Test
    void 排行最多返回五条且按金额降序() {
        stub(List.of(expense(d(1), "600.00", "A"),
                expense(d(2), "500.00", "B"),
                expense(d(3), "400.00", "C"),
                expense(d(4), "300.00", "D"),
                expense(d(5), "200.00", "E"),
                expense(d(6), "100.00", "F")));

        SpendingMerchantResponse response = analyze();

        assertEquals(5, response.getTopMerchants().size());
        assertEquals(List.of("A", "B", "C", "D", "E"), names(response));
        assertEquals(6, response.getMerchantCount(), "对象数量仍然统计全部");
    }

    @Test
    void 单项占比按总额计算() {
        stub(List.of(expense(d(1), "750.00", "食堂"),
                expense(d(2), "150.00", "超市"),
                expense(d(3), "100.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals("75.00", response.getTopMerchants().get(0).getPercentage());
        assertEquals("25.00", response.getTopMerchants().get(1).getPercentage());
    }

    @Test
    void 未填写商户的金额与占比正确() {
        stub(List.of(expense(d(1), "100.00", "食堂"),
                expense(d(2), "100.00", "超市"),
                expense(d(3), "800.00", "")));

        SpendingMerchantResponse response = analyze();

        assertEquals("800.00", response.getUnknownMerchantAmount());
        assertEquals("80.00", response.getUnknownMerchantRate());
        assertEquals("66.67", response.getMerchantCoverage(), "覆盖率是笔数口径：2 / 3");
    }

    // ==================== 状态 ====================

    @Test
    void 数据充分时返回OK并给出结论() {
        stub(healthy());

        SpendingMerchantResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals(MONTH, response.getMonth());
        assertEquals(2, response.getMerchantCount());
        assertTrue(response.getMessage().contains("2 个交易对象"), response.getMessage());
        assertTrue(response.getSummary().contains("支出主要集中在 2 个消费对象"), response.getSummary());
    }

    @Test
    void 没有支出时返回NO_DATA且列表为空() {
        stub(List.of());

        SpendingMerchantResponse response = analyze();

        assertEquals("NO_DATA", response.getStatus());
        assertEquals("0.00", response.getAverageAmount());
        assertEquals("0.00", response.getTop3Concentration());
        assertEquals("0.00", response.getUnknownMerchantAmount());
        assertEquals("", response.getSummary());
        assertTrue(response.getTopMerchants().isEmpty());
    }

    @Test
    void 只有一天消费时返回INSUFFICIENT_DATA() {
        stub(List.of(expense(d(1), "100.00", "食堂"), expense(d(1), "200.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals("300.00", response.getTotalAmount());
        assertEquals(2, response.getMerchantCount());
        assertTrue(response.getTopMerchants().isEmpty());
    }

    @Test
    void 商户覆盖率低于一半时返回INSUFFICIENT_DATA() {
        stub(List.of(expense(d(1), "100.00", "食堂"),
                expense(d(2), "100.00", "超市"),
                expense(d(3), "100.00", ""),
                expense(d(4), "100.00", ""),
                expense(d(5), "100.00", ""),
                expense(d(6), "100.00", ""),
                expense(d(7), "100.00", "")));

        SpendingMerchantResponse response = analyze();

        assertEquals("INSUFFICIENT_DATA", response.getStatus());
        assertEquals("28.57", response.getMerchantCoverage(), "2 / 7 = 28.57");
        assertEquals(2, response.getMerchantCount(), "事实数据仍然返回");
    }

    @Test
    void 历史月份返回NOT_APPLICABLE且不查库() {
        SpendingMerchantResponse response = service.analyze(USER_ID, "2026-08");

        assertEquals("NOT_APPLICABLE", response.getStatus());
        assertEquals("2026-08", response.getMonth());
        assertTrue(response.getTopMerchants().isEmpty());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 未来月份返回NOT_APPLICABLE且不查库() {
        assertEquals("NOT_APPLICABLE", service.analyze(USER_ID, "2026-10").getStatus());
        verifyNoMoreInteractions(billMapper);
    }

    // ==================== 参数 ====================

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
    void 整个分析只执行一次明细查询() {
        stub(healthy());

        analyze();

        verify(billMapper, times(1)).selectExpenseDetails(anyLong(), anyInt(), any(), any(), anyInt());
        verifyNoMoreInteractions(billMapper);
    }

    @Test
    void 查询范围为当月且限制明细条数() {
        stub(List.of());

        analyze();

        ArgumentCaptor<Integer> type = ArgumentCaptor.forClass(Integer.class);
        ArgumentCaptor<LocalDate> start = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        ArgumentCaptor<Integer> limit = ArgumentCaptor.forClass(Integer.class);
        verify(billMapper).selectExpenseDetails(anyLong(), type.capture(), start.capture(),
                end.capture(), limit.capture());

        assertEquals(BillType.EXPENSE.getCode(), type.getValue());
        assertEquals(LocalDate.of(2026, 9, 1), start.getValue());
        assertEquals(LocalDate.of(2026, 9, 30), end.getValue());
        assertEquals(SpendingMerchantService.MAX_DETAIL_ROWS, limit.getValue());
    }

    @Test
    void 查询固定使用传入的用户标识() {
        stub(List.of());

        service.analyze(USER_ID, MONTH);
        service.analyze(77L, MONTH);

        ArgumentCaptor<Long> userIds = ArgumentCaptor.forClass(Long.class);
        verify(billMapper, times(2)).selectExpenseDetails(userIds.capture(), anyInt(), any(), any(), anyInt());
        assertEquals(List.of(USER_ID, 77L), userIds.getAllValues(),
                "用户 A 与用户 B 各自查询自己的数据，Service 不接受来自请求的 userId");
    }

    @Test
    void 两个用户的聚合结果互不影响() {
        when(billMapper.selectExpenseDetails(anyLong(), anyInt(), any(), any(), anyInt()))
                .thenReturn(healthy())
                .thenReturn(List.of(expense(d(1), "10.00", "另一个店"),
                        expense(d(2), "10.00", "第三家店"),
                        expense(d(3), "10.00", "第四家店")));

        SpendingMerchantResponse first = service.analyze(USER_ID, MONTH);
        SpendingMerchantResponse second = service.analyze(99L, MONTH);

        assertEquals("1000.00", first.getTotalAmount());
        assertEquals("30.00", second.getTotalAmount());
        assertEquals(2, first.getMerchantCount());
        assertEquals(3, second.getMerchantCount());
    }

    // ==================== 边界（金额 / 月长） ====================

    @Test
    void 金额为零的记录被剔除() {
        stub(List.of(expense(d(1), "0.00", "食堂"),
                expense(d(2), "100.00", "食堂"),
                expense(d(3), "100.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals("200.00", response.getTotalAmount());
        assertEquals(2, response.getTotalCount());
    }

    @Test
    void 金额为空或明细为空时被安全跳过() {
        ExpenseDetail noAmount = new ExpenseDetail();
        noAmount.setBillDate(d(1));
        noAmount.setMerchant("食堂");
        // List.of 不接受 null 元素，这里用 ArrayList 手工构造含 null 的脏数据
        List<ExpenseDetail> details = new ArrayList<>();
        details.add(noAmount);
        details.add(null);
        details.add(expense(d(2), "100.00", "食堂"));
        details.add(expense(d(3), "100.00", "超市"));
        details.add(expense(d(4), "100.00", "超市"));
        stub(details);

        SpendingMerchantResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals("300.00", response.getTotalAmount());
        assertEquals(3, response.getTotalCount());
    }

    @Test
    void 日期为空的明细不影响天数统计() {
        ExpenseDetail noDate = new ExpenseDetail();
        noDate.setMerchant("食堂");
        noDate.setAmount(new BigDecimal("100.00"));
        stub(List.of(noDate, expense(d(1), "100.00", "食堂"),
                expense(d(2), "100.00", "超市"), expense(d(3), "100.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertEquals("OK", response.getStatus());
        assertEquals(4, response.getTotalCount(), "日期为空的明细仍然计入笔数");
    }

    @Test
    void 大金额保持精度() {
        stub(List.of(expense(d(1), "99999999.99", "食堂"),
                expense(d(2), "0.01", "食堂"),
                expense(d(3), "0.01", "超市")));

        assertEquals("100000000.01", analyze().getTotalAmount());
    }

    @Test
    void 二十八天月份查询范围正确() {
        stub(List.of(expense(LocalDate.of(2026, 2, 1), "100.00", "食堂"),
                expense(LocalDate.of(2026, 2, 2), "100.00", "超市"),
                expense(LocalDate.of(2026, 2, 3), "100.00", "超市")));

        SpendingMerchantResponse response = serviceOf("2026-02-15T04:00:00Z").analyze(USER_ID, "2026-02");

        assertEquals("OK", response.getStatus());
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper).selectExpenseDetails(anyLong(), anyInt(), any(), end.capture(), anyInt());
        assertEquals(LocalDate.of(2026, 2, 28), end.getValue());
    }

    @Test
    void 三十一天月份查询范围正确() {
        stub(List.of(expense(LocalDate.of(2026, 7, 1), "100.00", "食堂"),
                expense(LocalDate.of(2026, 7, 2), "100.00", "超市"),
                expense(LocalDate.of(2026, 7, 31), "100.00", "超市")));

        SpendingMerchantResponse response = serviceOf("2026-07-15T04:00:00Z").analyze(USER_ID, "2026-07");

        assertEquals("OK", response.getStatus());
        ArgumentCaptor<LocalDate> end = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper).selectExpenseDetails(anyLong(), anyInt(), any(), end.capture(), anyInt());
        assertEquals(LocalDate.of(2026, 7, 31), end.getValue());
    }

    // ==================== 排序稳定性与文案 ====================

    @Test
    void 金额与笔数都相同时按名称字典序() {
        stub(List.of(expense(d(1), "100.00", "bbb"),
                expense(d(2), "100.00", "aaa"),
                expense(d(3), "50.00", "ccc")));

        assertEquals(List.of("aaa", "bbb", "ccc"), names(analyze()));
    }

    @Test
    void 金额相同时按笔数降序() {
        stub(List.of(expense(d(1), "50.00", "AAA"),
                expense(d(2), "50.00", "AAA"),
                expense(d(3), "150.00", "BBB")));

        SpendingMerchantResponse response = analyze();

        assertEquals(List.of("BBB", "AAA"), names(response));
        assertEquals(2, response.getTopMerchants().get(1).getCount());
    }

    @Test
    void 未填写交易对象时总结会提示数据质量() {
        stub(List.of(expense(d(1), "100.00", "食堂"),
                expense(d(2), "100.00", "超市"),
                expense(d(3), "800.00", "")));

        String summary = analyze().getSummary();

        assertTrue(summary.contains("未填写交易对象"), summary);
        assertTrue(summary.contains("80.00%"), summary);
    }

    @Test
    void 非OK状态不给出排行与结论() {
        stub(List.of(expense(d(1), "100.00", "食堂"), expense(d(1), "100.00", "超市")));

        SpendingMerchantResponse response = analyze();

        assertTrue(response.getTopMerchants().isEmpty());
        assertEquals("", response.getSummary());
        assertEquals("0.00", response.getTop3Concentration());
    }

    @Test
    void 工具方法边界正确() {
        assertEquals("0.00", SpendingMerchantService.averageAmount(BigDecimal.TEN, 0));
        assertEquals("0.00", SpendingMerchantService.percentage(BigDecimal.TEN, BigDecimal.ZERO));
        assertEquals("0.00", SpendingMerchantService.percentage(BigDecimal.TEN, null));
        assertEquals("", SpendingMerchantService.displayName(null));
        assertEquals("", SpendingMerchantService.normalizeKey("   "));
    }

    // ==================== 辅助方法 ====================

    /** 两个消费对象、三天、覆盖率 100% 的标准数据（总额 1000 / 4 笔） */
    private static List<ExpenseDetail> healthy() {
        return List.of(expense(d(1), "400.00", "食堂"),
                expense(d(2), "300.00", "食堂"),
                expense(d(3), "200.00", "超市"),
                expense(d(4), "100.00", "超市"));
    }

    private SpendingMerchantResponse analyze() {
        return service.analyze(USER_ID, MONTH);
    }

    private SpendingMerchantService serviceOf(String instant) {
        return new SpendingMerchantService(billMapper, Clock.fixed(Instant.parse(instant), ZONE));
    }

    private void stub(List<ExpenseDetail> details) {
        when(billMapper.selectExpenseDetails(anyLong(), anyInt(), any(), any(), anyInt()))
                .thenReturn(details);
    }

    private static List<String> names(SpendingMerchantResponse response) {
        List<String> result = new ArrayList<>(response.getTopMerchants().size());
        for (MerchantSpendingItem item : response.getTopMerchants()) {
            result.add(item.getMerchantName());
        }
        return result;
    }

    private static LocalDate d(int day) {
        return LocalDate.of(2026, 9, day);
    }

    private static ExpenseDetail expense(LocalDate date, String amount, String merchant) {
        ExpenseDetail detail = new ExpenseDetail();
        detail.setCategory("餐饮");
        detail.setBillDate(date);
        detail.setAmount(new BigDecimal(amount));
        detail.setMerchant(merchant);
        return detail;
    }
}
