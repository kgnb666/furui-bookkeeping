package com.campus.ledger.service;

import com.campus.ledger.common.BizException;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.campus.ledger.dto.BillRequest;
import com.campus.ledger.dto.BillResponse;
import com.campus.ledger.dto.PageResult;
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
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BillServiceTest {

    private static final Long USER_ID = 3L;

    @Mock
    private BillMapper billMapper;

    private BillService billService;

    @BeforeEach
    void setUp() {
        billService = new BillService(billMapper);
    }

    @Test
    void 手动记账保存为MANUAL来源且去重键为空() {
        AtomicReference<Bill> saved = new AtomicReference<>();
        when(billMapper.insert(any(Bill.class))).thenAnswer(invocation -> {
            Bill bill = invocation.getArgument(0);
            bill.setId(5L);
            saved.set(bill);
            return 1;
        });
        when(billMapper.selectById(5L)).thenAnswer(invocation -> saved.get());

        BillResponse response = billService.create(USER_ID, request("1", "15.00", "餐饮", LocalDate.now()));

        ArgumentCaptor<Bill> captor = ArgumentCaptor.forClass(Bill.class);
        verify(billMapper).insert(captor.capture());
        Bill inserted = captor.getValue();
        assertEquals("MANUAL", inserted.getSource());
        assertNull(inserted.getDedupKey(), "手动记账不去重，允许同一天同金额同商户记两笔");
        assertEquals(1, inserted.getType());
        assertEquals(USER_ID, inserted.getUserId());
        assertEquals("15.00", response.getAmount());
        assertEquals("支出", response.getTypeName());
    }

    @Test
    void 金额必须大于0() {
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "0", "餐饮", LocalDate.now()))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "-32.00", "餐饮", LocalDate.now()))).getCode());
    }

    @Test
    void 金额不能超过上限且不能超过两位小数() {
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "100000000.00", "餐饮", LocalDate.now()))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "12.345", "餐饮", LocalDate.now()))).getCode());
    }

    @Test
    void 收支类型非法时拒绝() {
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("9", "15.00", "餐饮", LocalDate.now()))).getCode());
    }

    @Test
    void 分类必须属于当前收支类型() {
        // 生活费是收入分类，用在支出上不合法
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "15.00", "生活费", LocalDate.now()))).getCode());
        // 不存在的分类
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "15.00", "随便写的", LocalDate.now()))).getCode());
        // 不计收支有独立分类
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("3", "15.00", "餐饮", LocalDate.now()))).getCode());
    }

    @Test
    void 日期不能晚于今天() {
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.create(USER_ID, request("1", "15.00", "餐饮", LocalDate.now().plusDays(1)))).getCode());
    }

    @Test
    void 查询参数不合法时给出明确错误() {
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.page(USER_ID, "2026-13-01", null, null, null, null, null, null, 1, 20)).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.page(USER_ID, "2026-09", "5", null, null, null, null, null, 1, 20)).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.page(USER_ID, null, null, null, "UNKNOWN", null, null, null, 1, 20)).getCode());
    }

    @Test
    void 金额筛选条件不合法时拒绝() {
        // 负数金额区间没有意义
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.page(USER_ID, null, null, null, null, null, new BigDecimal("-1"), null, 1, 20)).getCode());
        // 超过两位小数
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.page(USER_ID, null, null, null, null, null, null, new BigDecimal("1.234"), 1, 20)).getCode());
        // 最小值大于最大值
        assertEquals(400, assertThrows(BizException.class,
                () -> billService.page(USER_ID, null, null, null, null, null,
                        new BigDecimal("50"), new BigDecimal("10"), 1, 20)).getCode());
    }

    @Test
    void 金额区间筛选会拼进查询条件并保持分页正确() {
        when(billMapper.selectPage(any(), any())).thenAnswer(invocation -> invocation.getArgument(0));

        PageResult<BillResponse> result = billService.page(USER_ID, "2026-09", "1", null, null, null,
                new BigDecimal("10.00"), new BigDecimal("50.00"), 2, 10);

        ArgumentCaptor<Page<Bill>> pageCaptor = ArgumentCaptor.forClass(Page.class);
        ArgumentCaptor<LambdaQueryWrapper<Bill>> wrapperCaptor =
                ArgumentCaptor.forClass(LambdaQueryWrapper.class);
        verify(billMapper).selectPage(pageCaptor.capture(), wrapperCaptor.capture());

        assertEquals(2, pageCaptor.getValue().getCurrent());
        assertEquals(10, pageCaptor.getValue().getSize());
        // 金额区间已作为查询条件拼进 wrapper（SQL 片段含 amount 与参数占位）
        assertTrue(wrapperCaptor.getValue().getExpression().getNormal().size() >= 4,
                "应包含用户、类型、月份区间与金额区间条件");
        assertEquals(2, result.getPage());
        assertEquals(0, result.getTotal());
    }

    @Test
    void 不能查看别人的账单() {
        when(billMapper.selectOne(any())).thenReturn(null);

        BizException e = assertThrows(BizException.class, () -> billService.detail(USER_ID, 100L));

        assertEquals(404, e.getCode());
        assertEquals("账单不存在", e.getMessage());
    }

    @Test
    void 不能修改别人的账单() {
        when(billMapper.selectOne(any())).thenReturn(null);

        BizException e = assertThrows(BizException.class,
                () -> billService.update(USER_ID, 100L, request("1", "15.00", "餐饮", LocalDate.now())));

        assertEquals(404, e.getCode());
    }

    @Test
    void 不能删除别人的账单() {
        when(billMapper.selectOne(any())).thenReturn(null);

        BizException e = assertThrows(BizException.class, () -> billService.delete(USER_ID, 100L));

        assertEquals(404, e.getCode());
    }

    private BillRequest request(String type, String amount, String category, LocalDate date) {
        BillRequest request = new BillRequest();
        request.setType(type);
        request.setAmount(new BigDecimal(amount));
        request.setCategory(category);
        request.setBillDate(date);
        request.setMerchant("食堂");
        request.setRemark("午饭");
        return request;
    }
}
