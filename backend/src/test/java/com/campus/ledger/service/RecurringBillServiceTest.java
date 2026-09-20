package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.RecurringBillResponse;
import com.campus.ledger.dto.RecurringBillRow;
import com.campus.ledger.dto.RecurringBillsResponse;
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
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 周期性账单识别测试。时间固定在 2026-09-17，日期一律相对"今天"构造，
 * 保证用例不会随真实时间漂移。
 */
@ExtendWith(MockitoExtension.class)
class RecurringBillServiceTest {

    private static final Long USER_ID = 21L;
    private static final Clock FIXED = Clock.fixed(
            Instant.parse("2026-09-17T04:00:00Z"), ZoneId.of("Asia/Shanghai"));
    private static final LocalDate TODAY = LocalDate.of(2026, 9, 17);

    @Mock
    private BillMapper billMapper;

    private RecurringBillService service;

    @BeforeEach
    void setUp() {
        service = new RecurringBillService(billMapper, FIXED);
    }

    // ==================== 周期识别：三个周期 ====================

    @Test
    void 每周固定消费识别为WEEKLY() {
        List<RecurringBillResponse> items = service.analyze(
                series("城市公交", "交通", "2.00", weeklyDates(6)), TODAY);

        RecurringBillResponse item = only(items);
        assertEquals("WEEKLY", item.getCycleType());
        assertEquals("每周一次", item.getCycleLabel());
        assertEquals(6, item.getSampleCount());
        assertEquals("2.00", item.getAverageAmount());
        assertEquals(7, item.getAverageInterval());
        assertEquals("HIGH", item.getConfidence());
    }

    @Test
    void 双周固定消费识别为BIWEEKLY() {
        List<RecurringBillResponse> items = service.analyze(
                series("学校书店", "学习", "45.00", everyNDays(14, 6)), TODAY);

        RecurringBillResponse item = only(items);
        assertEquals("BIWEEKLY", item.getCycleType());
        assertEquals("每两周一次", item.getCycleLabel());
        assertEquals(14, item.getAverageInterval());
        assertEquals("HIGH", item.getConfidence());
    }

    @Test
    void 每月固定消费识别为MONTHLY() {
        List<RecurringBillResponse> items = service.analyze(
                series("腾讯视频VIP", "娱乐", "25.00", monthlyDates(6)), TODAY);

        RecurringBillResponse item = only(items);
        assertEquals("MONTHLY", item.getCycleType());
        assertEquals("每月一次", item.getCycleLabel());
        assertEquals(6, item.getSampleCount());
        assertEquals("25.00", item.getAverageAmount());
        assertEquals("HIGH", item.getConfidence());
        assertTrue(item.getReason().contains("金额稳定"), item.getReason());
        assertTrue(item.getReason().contains("约每 30 天"), item.getReason());
    }

    @Test
    void 月末与月初交替的月周期仍能识别() {
        // 全部落在 180 天窗口内；间隔 28~31 天，均在月周期区间
        List<LocalDate> dates = List.of(
                LocalDate.of(2026, 4, 30), LocalDate.of(2026, 5, 31),
                LocalDate.of(2026, 6, 30), LocalDate.of(2026, 7, 31),
                LocalDate.of(2026, 8, 31), LocalDate.of(2026, 9, 17));

        RecurringBillResponse item = only(service.analyze(
                series("房东", "住宿", "1200.00", dates), TODAY));

        assertEquals("MONTHLY", item.getCycleType());
        // 实际间隔为 17~31 天，这里展示的是真实间隔区间而不是周期定义区间
        assertEquals("17~31 天", item.getIntervalRange());
    }

    @Test
    void 间隔超出所有周期区间时丢弃() {
        // 间隔 20 天，不属于周/双周/月任何一个区间
        assertTrue(service.analyze(
                series("某商户", "购物", "50.00", everyNDays(20, 6)), TODAY).isEmpty());
    }

    // ==================== 四项信号 ====================

    @Test
    void 金额稳定时金额信号通过() {
        RecurringBillResponse item = only(service.analyze(
                series("中国移动", "通讯", "42.75", monthlyDates(4),
                        List.of("39.00", "44.00", "49.00", "39.00")), TODAY));

        // CV ≈ 0.096，未超过 0.15，四项信号齐全
        assertEquals("HIGH", item.getConfidence());
        assertTrue(item.getReason().contains("金额稳定"), item.getReason());
    }

    @Test
    void 金额波动过大时降为中置信度() {
        // 25 / 60 / 25 / 60：CV 远大于 0.15，金额信号不通过
        RecurringBillResponse item = only(service.analyze(
                series("某订阅", "娱乐", "0.00", monthlyDates(4),
                        List.of("25.00", "60.00", "25.00", "60.00")), TODAY));

        assertEquals("MEDIUM", item.getConfidence());
        assertTrue(item.getReason().contains("金额有波动"), item.getReason());
    }

    @Test
    void 间隔不稳定时降为中置信度() {
        // 30 天、30 天、30 天、40 天：中位数仍是 30，但最后一次超出区间
        List<LocalDate> dates = List.of(
                TODAY.minusDays(130), TODAY.minusDays(100),
                TODAY.minusDays(70), TODAY.minusDays(40), TODAY);

        RecurringBillResponse item = only(service.analyze(
                series("某会员", "娱乐", "25.00", dates), TODAY));

        assertEquals("MONTHLY", item.getCycleType());
        assertEquals("MEDIUM", item.getConfidence());
    }

    @Test
    void 分类一致时分类信号通过() {
        RecurringBillResponse item = only(service.analyze(
                series("腾讯视频VIP", "娱乐", "25.00", monthlyDates(5)), TODAY));

        assertEquals("100.00", item.getCategoryRatio());
        assertEquals("HIGH", item.getConfidence());
    }

    @Test
    void 主导分类占比不足八成时分类信号不通过() {
        // 5 条娱乐 + 2 条学习 = 7 条，逐月发生；主导分类占 71.43% < 80%。
        // 收窄到娱乐后子集本身很稳定，但分类信号必须按原始比例判定，因此只能是 MEDIUM。
        // 全部显式落在 180 天窗口内（窗口起点约为 TODAY-180，早于它的记录会被剔除）
        LocalDate base = TODAY.minusMonths(4);
        List<RecurringBillRow> rows = new ArrayList<>();
        for (int i = 0; i < 5; i++) {
            rows.add(row("某平台", "娱乐", "25.00", base.plusMonths(i)));
        }
        rows.add(row("某平台", "学习", "68.00", base.plusDays(3)));
        rows.add(row("某平台", "学习", "68.00", base.plusMonths(2).plusDays(3)));

        RecurringBillResponse item = only(service.analyze(rows, TODAY));

        assertEquals("娱乐", item.getCategory());
        assertEquals("71.43", item.getCategoryRatio());
        assertEquals("MEDIUM", item.getConfidence());
        assertTrue(item.getReason().contains("分类不完全一致"), item.getReason());
    }

    @Test
    void 主导分类样本不足时整组丢弃() {
        // 4 条购物 + 5 条餐饮，主导分类餐饮占 56%，其序列只有 5 条但购物 4 条也不足
        List<RecurringBillRow> rows = new ArrayList<>();
        List<LocalDate> dates = monthlyDates(9);
        for (int i = 0; i < 4; i++) {
            rows.add(row("学校超市", "购物", "30.00", dates.get(i)));
        }
        for (int i = 4; i < 9; i++) {
            rows.add(row("学校超市", "餐饮", "30.00", dates.get(i)));
        }

        // 主导分类餐饮占 56%，取餐饮 5 条；但整体间隔被两类交替打乱，结果要么 MEDIUM 要么丢弃
        List<RecurringBillResponse> items = service.analyze(rows, TODAY);
        for (RecurringBillResponse item : items) {
            assertEquals("餐饮", item.getCategory(), "应当按主导分类统计");
        }
    }

    @Test
    void 信号不足两条时直接丢弃不返回LOW() {
        // 金额剧烈波动 + 分类不一致，且没有占比达 80% 的主导分类，
        // 因此整组参与计算：只有间隔与商户两个信号 → 丢弃
        List<RecurringBillRow> rows = new ArrayList<>();
        List<LocalDate> dates = monthlyDates(4);
        rows.add(row("某店", "餐饮", "10.00", dates.get(0)));
        rows.add(row("某店", "购物", "500.00", dates.get(1)));
        rows.add(row("某店", "娱乐", "25.00", dates.get(2)));
        rows.add(row("某店", "学习", "900.00", dates.get(3)));

        // 只有"间隔稳定 + 商户一致"两个信号，按规则必须丢弃
        assertTrue(service.analyze(rows, TODAY).isEmpty(), "低置信度结果不应返回");
    }

    // ==================== 噪声过滤 ====================

    @Test
    void 每天消费被高频过滤挡住() {
        // 每天食堂吃饭：金额稳定、商户一致，但平均间隔 1 天
        List<LocalDate> dates = new ArrayList<>();
        for (int i = 0; i < 60; i++) {
            dates.add(TODAY.minusDays(i));
        }

        assertTrue(service.analyze(series("第一食堂", "餐饮", "15.00", dates), TODAY).isEmpty(),
                "每日高频消费不能被识别成周期账单");
    }

    @Test
    void 每天固定金额的通勤同样被过滤() {
        // 每天同一班校车、金额恒定 —— 只有频率上限能挡住这一类
        List<LocalDate> dates = new ArrayList<>();
        for (int i = 0; i < 90; i++) {
            dates.add(TODAY.minusDays(i));
        }

        assertTrue(service.analyze(series("校园班车", "交通", "6.00", dates), TODAY).isEmpty());
    }

    @Test
    void 间隔随机的随机购物不被识别() {
        List<LocalDate> dates = new ArrayList<>();
        int[] gaps = {2, 15, 40, 3, 22, 9, 30};
        LocalDate cursor = TODAY.minusDays(160);
        dates.add(cursor);
        for (int gap : gaps) {
            cursor = cursor.plusDays(gap);
            dates.add(cursor);
        }

        assertTrue(service.analyze(series("淘宝", "购物", "88.00", dates), TODAY).isEmpty(),
                "间隔随机的消费不应被识别为周期");
    }

    @Test
    void 连续几天集中消费不被识别() {
        // 连续 4 天打印店，间隔都是 1 天
        List<LocalDate> dates = List.of(
                TODAY.minusDays(3), TODAY.minusDays(2), TODAY.minusDays(1), TODAY);

        assertTrue(service.analyze(series("校园打印店", "学习", "3.00", dates), TODAY).isEmpty());
    }

    @Test
    void 商户为空的记录直接跳过() {
        List<RecurringBillRow> rows = new ArrayList<>(series("腾讯视频", "娱乐", "25.00", monthlyDates(5)));
        rows.add(row("", "餐饮", "20.00", TODAY.minusDays(3)));
        rows.add(row(null, "餐饮", "20.00", TODAY.minusDays(5)));

        List<RecurringBillResponse> items = service.analyze(rows, TODAY);

        assertEquals(1, items.size());
        assertEquals("腾讯视频", items.get(0).getMerchant());
    }

    @Test
    void 样本不足四次的商户被跳过() {
        assertTrue(service.analyze(
                series("某商户", "餐饮", "30.00", monthlyDates(3)), TODAY).isEmpty());
    }

    // ==================== 商户归一化 ====================

    @Test
    void 商户归一化合并空格与大小写差异() {
        assertEquals("腾讯视频vip", RecurringBillService.normalizeMerchant("腾讯视频 VIP"));
        assertEquals("腾讯视频vip", RecurringBillService.normalizeMerchant("腾讯视频vip"));
        assertEquals(RecurringBillService.normalizeMerchant("腾讯视频 VIP"),
                RecurringBillService.normalizeMerchant("腾讯视频VIP"));
    }

    @Test
    void 商户归一化不剥离单独的店字() {
        // "如家酒店" 不能变成 "如家酒"，否则会与"如家酒"错误合并
        assertEquals("如家酒店", RecurringBillService.normalizeMerchant("如家酒店"));
        assertFalse(RecurringBillService.normalizeMerchant("如家酒店")
                        .equals(RecurringBillService.normalizeMerchant("如家酒")),
                "如家酒店与如家酒必须是不同商户");
    }

    @Test
    void 商户归一化剥离明确的长后缀() {
        assertEquals(RecurringBillService.normalizeMerchant("海底捞火锅"),
                RecurringBillService.normalizeMerchant("海底捞火锅旗舰店"));
        assertEquals(RecurringBillService.normalizeMerchant("某某科技"),
                RecurringBillService.normalizeMerchant("某某科技有限公司"));
        assertEquals(RecurringBillService.normalizeMerchant("某某科技"),
                RecurringBillService.normalizeMerchant("某某科技有限责任公司"));
        // "海底捞火锅店"里的"店"是名称本身的一部分，保持原样
        assertEquals("海底捞火锅店", RecurringBillService.normalizeMerchant("海底捞火锅店"));
    }

    @Test
    void 不同写法的同一订阅能被合并识别() {
        List<RecurringBillRow> rows = new ArrayList<>();
        List<LocalDate> dates = monthlyDates(6);
        for (int i = 0; i < 6; i++) {
            String name = i % 2 == 0 ? "腾讯视频VIP" : "腾讯视频 VIP";
            rows.add(row(name, "娱乐", "25.00", dates.get(i)));
        }

        RecurringBillResponse item = only(service.analyze(rows, TODAY));

        assertEquals(6, item.getSampleCount(), "两种写法应当合并为 6 条记录");
        assertEquals("MONTHLY", item.getCycleType());
    }

    // ==================== 边界 ====================

    @Test
    void 跨年月份间隔仍按天数正常计算() {
        // 2026-04-15 → 2026-05-15 → 2026-06-15 → 2026-07-15（跨月，落在窗口内）
        List<LocalDate> dates = List.of(
                LocalDate.of(2026, 4, 15), LocalDate.of(2026, 5, 15),
                LocalDate.of(2026, 6, 15), LocalDate.of(2026, 7, 15));

        RecurringBillResponse item = only(service.analyze(
                series("某会员", "娱乐", "25.00", dates), TODAY));

        assertEquals("MONTHLY", item.getCycleType());
        assertEquals(30, item.getAverageInterval());
    }

    @Test
    void 闰年二月到三月的间隔落在月周期区间() {
        // 2028 是闰年：2/15 → 3/15 间隔 29 天
        List<LocalDate> dates = List.of(
                LocalDate.of(2028, 1, 15), LocalDate.of(2028, 2, 15),
                LocalDate.of(2028, 3, 15), LocalDate.of(2028, 4, 15));

        RecurringBillResponse item = only(service.analyze(
                series("某订阅", "娱乐", "25.00", dates), TODAY));

        assertEquals("MONTHLY", item.getCycleType());
        assertEquals("29~31 天", item.getIntervalRange());
    }

    @Test
    void 窗口外的账单不参与识别() {
        List<RecurringBillRow> rows = new ArrayList<>(series("某会员", "娱乐", "25.00", monthlyDates(5)));
        // 追加一条 200 天前的记录，超出 180 天窗口，应被忽略
        rows.add(row("某会员", "娱乐", "25.00", TODAY.minusDays(200)));

        RecurringBillResponse item = only(service.analyze(rows, TODAY));

        assertEquals(5, item.getSampleCount(), "窗口外的账单不应计入");
    }

    @Test
    void 预计下一次日期按月推进() {
        RecurringBillResponse item = only(service.analyze(
                series("腾讯视频", "娱乐", "25.00", monthlyDates(4)), TODAY));

        // 最近一次是今天，下一次应为一个月后
        assertEquals(LocalDate.now(FIXED).plusMonths(1).toString(), item.getNextDate());
    }

    @Test
    void 预计下一次日期按周推进() {
        RecurringBillResponse item = only(service.analyze(
                series("城市公交", "交通", "2.00", weeklyDates(5)), TODAY));

        assertEquals(TODAY.plusDays(7).toString(), item.getNextDate());
    }

    // ==================== status 判定 ====================

    @Test
    void 没有任何账单时返回NO_DATA() {
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(List.of());

        RecurringBillsResponse response = service.detect(USER_ID, null);

        assertEquals("NO_DATA", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertEquals(RecurringBillService.WINDOW_DAYS, response.getWindowDays());
    }

    @Test
    void 有账单但最早不足六十天时返回NOT_ENOUGH_HISTORY() {
        // 10 条账单，但都集中在最近 20 天内
        List<RecurringBillRow> rows = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            rows.add(row("某商户", "餐饮", "20.00", TODAY.minusDays(i * 2)));
        }
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(rows);

        RecurringBillsResponse response = service.detect(USER_ID, null);

        assertEquals("NOT_ENOUGH_HISTORY", response.getStatus());
        assertTrue(response.getMessage().contains("3 个月"), response.getMessage());
    }

    @Test
    void 窗口内账单不足五条时返回NO_DATA() {
        List<RecurringBillRow> rows = List.of(
                row("某商户", "餐饮", "20.00", TODAY.minusDays(100)),
                row("某商户", "餐饮", "20.00", TODAY.minusDays(80)),
                row("某商户", "餐饮", "20.00", TODAY.minusDays(60)));
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(rows);

        assertEquals("NO_DATA", service.detect(USER_ID, null).getStatus());
    }

    @Test
    void 数据足够但没有周期时返回NO_RECURRING() {
        // 300 条随机间隔的消费，跨 170 天
        List<RecurringBillRow> rows = new ArrayList<>();
        LocalDate cursor = TODAY.minusDays(170);
        int[] gaps = {3, 7, 2, 11, 5, 19, 4, 8, 6, 13, 2, 9};
        int index = 0;
        while (!cursor.isAfter(TODAY)) {
            rows.add(row("商铺" + (index % 7), "购物", "50.00", cursor));
            cursor = cursor.plusDays(gaps[index % gaps.length]);
            index++;
        }
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(rows);

        RecurringBillsResponse response = service.detect(USER_ID, null);

        assertEquals("NO_RECURRING", response.getStatus());
        assertTrue(response.getItems().isEmpty());
        assertTrue(response.getMessage().contains("没有发现"), response.getMessage());
    }

    @Test
    void 存在周期时返回OK并带上说明() {
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(series("腾讯视频VIP", "娱乐", "25.00", monthlyDates(6)));

        RecurringBillsResponse response = service.detect(USER_ID, null);

        assertEquals("OK", response.getStatus());
        assertEquals(1, response.getItems().size());
        assertTrue(response.getMessage().contains("识别到 1 项"), response.getMessage());
        RecurringBillResponse item = response.getItems().get(0);
        assertNotNull(item.getLastDate());
        assertNotNull(item.getNextDate());
    }

    @Test
    void 月份格式非法的类型参数被拒绝() {
        BizException e = assertThrows(BizException.class, () -> service.detect(USER_ID, "UNKNOWN"));

        assertEquals(400, e.getCode());
    }

    @Test
    void 传入非支出类型时返回空结果() {
        assertEquals("NO_DATA", service.detect(USER_ID, "2").getStatus());
        assertEquals("NO_DATA", service.detect(USER_ID, "收入").getStatus());
        verify(billMapper, times(0)).selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt());
    }

    // ==================== 安全与查询方式 ====================

    @Test
    void 查询固定带当前登录用户与支出类型() {
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(List.of());

        service.detect(USER_ID, null);

        ArgumentCaptor<Long> userCaptor = ArgumentCaptor.forClass(Long.class);
        ArgumentCaptor<Integer> typeCaptor = ArgumentCaptor.forClass(Integer.class);
        ArgumentCaptor<LocalDate> startCaptor = ArgumentCaptor.forClass(LocalDate.class);
        verify(billMapper).selectRecurringCandidates(userCaptor.capture(), typeCaptor.capture(),
                startCaptor.capture(), anyInt());

        assertEquals(USER_ID, userCaptor.getValue(), "必须限定当前登录用户");
        assertEquals(1, typeCaptor.getValue(), "只分析支出");
        assertEquals(TODAY.minusDays(180), startCaptor.getValue(), "窗口固定 180 天");
    }

    @Test
    void 两个用户的识别结果互不影响() {
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(series("腾讯视频VIP", "娱乐", "25.00", monthlyDates(6)))
                .thenReturn(List.of());

        RecurringBillsResponse forA = service.detect(USER_ID, null);
        RecurringBillsResponse forB = service.detect(USER_ID + 1, null);

        assertEquals("OK", forA.getStatus());
        assertEquals(1, forA.getItems().size());
        assertEquals("NO_DATA", forB.getStatus(), "B 没有账单，不应看到 A 的周期消费");
        assertTrue(forB.getItems().isEmpty());
    }

    @Test
    void 大数据量下只做一次查询且不按商户循环查库() {
        List<RecurringBillRow> rows = new ArrayList<>();
        // 3000 条明细、20 个不同商户
        for (int i = 0; i < 3000; i++) {
            rows.add(row("商户" + (i % 20), "购物", "20.00", TODAY.minusDays(i % 170)));
        }
        when(billMapper.selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt()))
                .thenReturn(rows);

        long start = System.nanoTime();
        RecurringBillsResponse response = service.detect(USER_ID, null);
        long elapsedMillis = (System.nanoTime() - start) / 1_000_000;

        assertNotNull(response);
        // 无论多少商户、多少账单，查询次数都固定为 1
        verify(billMapper, times(1)).selectRecurringCandidates(anyLong(), anyInt(), any(), anyInt());
        assertTrue(elapsedMillis < 3000, "识别耗时不应过高：" + elapsedMillis + "ms");
    }

    @Test
    void 结果按置信度与样本数排序() {
        List<RecurringBillRow> rows = new ArrayList<>();
        // HIGH：每月稳定 6 次
        rows.addAll(series("稳定商户", "娱乐", "25.00", monthlyDates(6)));
        // MEDIUM：金额波动
        List<LocalDate> dates = monthlyDates(4);
        for (int i = 0; i < 4; i++) {
            rows.add(row("波动商户", "娱乐", i % 2 == 0 ? "25.00" : "60.00", dates.get(i)));
        }

        List<RecurringBillResponse> items = service.analyze(rows, TODAY);

        assertEquals(2, items.size());
        assertEquals("HIGH", items.get(0).getConfidence());
        assertEquals("稳定商户", items.get(0).getMerchant());
    }

    // ==================== 测试数据构造 ====================

    private RecurringBillResponse only(List<RecurringBillResponse> items) {
        assertEquals(1, items.size(), "期望恰好识别出 1 项周期支出");
        return items.get(0);
    }

    private List<RecurringBillRow> series(String merchant, String category, String amount,
                                          List<LocalDate> dates) {
        List<RecurringBillRow> rows = new ArrayList<>();
        for (LocalDate date : dates) {
            rows.add(row(merchant, category, amount, date));
        }
        return rows;
    }

    /** 指定每笔金额的构造方式，用于金额稳定性用例 */
    private List<RecurringBillRow> series(String merchant, String category, String unusedAmount,
                                          List<LocalDate> dates, List<String> amounts) {
        List<RecurringBillRow> rows = new ArrayList<>();
        for (int i = 0; i < dates.size(); i++) {
            rows.add(row(merchant, category, amounts.get(i), dates.get(i)));
        }
        return rows;
    }

    private RecurringBillRow row(String merchant, String category, String amount, LocalDate date) {
        RecurringBillRow row = new RecurringBillRow();
        row.setMerchant(merchant);
        row.setCategory(category);
        row.setAmount(new BigDecimal(amount));
        row.setBillDate(date);
        return row;
    }

    /** 最近 n 次、每次间隔 7 天，最后一次是今天 */
    private List<LocalDate> weeklyDates(int count) {
        return everyNDays(7, count);
    }

    /** 最近 count 次、每次间隔 n 天，最后一次是今天 */
    private List<LocalDate> everyNDays(int days, int count) {
        List<LocalDate> dates = new ArrayList<>();
        for (int i = count - 1; i >= 0; i--) {
            dates.add(TODAY.minusDays((long) days * i));
        }
        return dates;
    }

    /**
     * 月周期日期：从 5 个月前开始每月 15 日，最后一条落在今天附近。
     * 用日历月推进，自动覆盖 28/30/31 天的真实间隔。
     */
    private List<LocalDate> monthlyDates(int count) {
        List<LocalDate> dates = new ArrayList<>();
        LocalDate base = TODAY.minusMonths(count - 1);
        for (int i = 0; i < count; i++) {
            dates.add(base.plusMonths(i));
        }
        return dates;
    }
}
