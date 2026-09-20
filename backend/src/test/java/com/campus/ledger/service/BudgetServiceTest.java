package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.BudgetItemResponse;
import com.campus.ledger.dto.BudgetRequest;
import com.campus.ledger.dto.BudgetResponse;
import com.campus.ledger.dto.CategorySum;
import com.campus.ledger.dto.TypeSum;
import com.campus.ledger.entity.Budget;
import com.campus.ledger.mapper.BillMapper;
import com.campus.ledger.mapper.BudgetMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DuplicateKeyException;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class BudgetServiceTest {

    private static final Long USER_ID = 3L;
    private static final String MONTH = "2026-09";

    @Mock
    private BudgetMapper budgetMapper;

    @Mock
    private BillMapper billMapper;

    private BudgetService budgetService;

    @BeforeEach
    void setUp() {
        budgetService = new BudgetService(budgetMapper, billMapper);
    }

    @Test
    void 查询预算时带上执行情况() {
        when(budgetMapper.selectList(any())).thenReturn(List.of(
                budget(1L, "", "2000.00"),
                budget(2L, "餐饮", "600.00"),
                budget(3L, "交通", "200.00")));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "856.50")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of(
                categorySum("餐饮", "286.50"),
                categorySum("交通", "570.00")));

        BudgetResponse response = budgetService.list(USER_ID, MONTH);

        assertEquals("2026-09", response.getMonth());
        assertEquals("856.50", response.getMonthExpense());

        BudgetItemResponse total = response.getTotal();
        assertEquals("2000.00", total.getAmount());
        assertEquals("856.50", total.getUsed());
        assertEquals("1143.50", total.getRemaining());
        assertEquals(new BigDecimal("42.83"), total.getUsageRate());
        assertEquals("NORMAL", total.getStatus());
        assertEquals("月度总预算", total.getCategoryName());

        assertEquals(2, response.getCategories().size());
        BudgetItemResponse food = response.getCategories().get(0);
        assertEquals("餐饮", food.getCategory());
        assertEquals("286.50", food.getUsed());
        assertEquals("313.50", food.getRemaining());
        assertEquals(new BigDecimal("47.75"), food.getUsageRate());
    }

    @Test
    void 没有设置预算时返回空结构() {
        when(budgetMapper.selectList(any())).thenReturn(List.of());
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        BudgetResponse response = budgetService.list(USER_ID, MONTH);

        assertNull(response.getTotal());
        assertTrue(response.getCategories().isEmpty());
        assertEquals("0.00", response.getMonthExpense());
    }

    @Test
    void 实际支出超过预算时状态为超支() {
        when(budgetMapper.selectList(any())).thenReturn(List.of(budget(1L, "", "200.00")));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "256.50")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        BudgetItemResponse total = budgetService.list(USER_ID, MONTH).getTotal();

        assertEquals("OVER", total.getStatus());
        assertEquals("已超支", total.getStatusName());
        assertEquals("-56.50", total.getRemaining());
    }

    @Test
    void 实际支出等于预算时状态为已达预算() {
        when(budgetMapper.selectList(any())).thenReturn(List.of(budget(1L, "", "200.00")));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "200.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        BudgetItemResponse total = budgetService.list(USER_ID, MONTH).getTotal();

        assertEquals("REACHED", total.getStatus());
        assertEquals(new BigDecimal("100.00"), total.getUsageRate());
    }

    @Test
    void 使用率按两位小数四舍五入() {
        when(budgetMapper.selectList(any())).thenReturn(List.of(budget(1L, "", "300.00")));
        when(billMapper.sumByType(any(), any(), any()))
                .thenReturn(List.of(typeSum(BillType.EXPENSE, "100.00")));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of());

        BudgetItemResponse total = budgetService.list(USER_ID, MONTH).getTotal();

        assertEquals(new BigDecimal("33.33"), total.getUsageRate());
    }

    @Test
    void 新增月度总预算使用空分类() {
        when(budgetMapper.selectCount(any())).thenReturn(0L);
        when(budgetMapper.insert(any(Budget.class))).thenAnswer(invocation -> {
            Budget entity = invocation.getArgument(0);
            entity.setId(9L);
            return 1;
        });
        when(budgetMapper.selectById(9L)).thenReturn(budget(9L, "", "2000.00"));
        when(billMapper.sumByType(any(), any(), any())).thenReturn(List.of());

        BudgetItemResponse response = budgetService.create(USER_ID, request(MONTH, "", "2000.00"));

        ArgumentCaptor<Budget> captor = ArgumentCaptor.forClass(Budget.class);
        verify(budgetMapper).insert(captor.capture());
        assertEquals("", captor.getValue().getCategory());
        assertEquals(USER_ID, captor.getValue().getUserId());
        assertEquals("2000.00", captor.getValue().getAmount().toPlainString());
        assertEquals(9L, response.getId());
    }

    @Test
    void 新增分类预算会带上该分类的已用金额() {
        when(budgetMapper.selectCount(any())).thenReturn(0L);
        when(budgetMapper.insert(any(Budget.class))).thenAnswer(invocation -> {
            Budget entity = invocation.getArgument(0);
            entity.setId(10L);
            return 1;
        });
        when(budgetMapper.selectById(10L)).thenReturn(budget(10L, "餐饮", "600.00"));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of(categorySum("餐饮", "286.50")));

        BudgetItemResponse response = budgetService.create(USER_ID, request(MONTH, "餐饮", "600.00"));

        assertEquals("餐饮", response.getCategory());
        assertEquals("286.50", response.getUsed());
        assertEquals("313.50", response.getRemaining());
    }

    @Test
    void 非法分类会被拒绝() {
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "生活费", "100.00"))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "转账", "100.00"))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "随便写的", "100.00"))).getCode());
    }

    @Test
    void 非法金额与非法月份会被拒绝() {
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "", "0"))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "", "-10"))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "", "10.555"))).getCode());
        assertEquals(400, assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request("2026-9-1", "", "100"))).getCode());
    }

    @Test
    void 重复预算是冲突而不是新增() {
        when(budgetMapper.selectCount(any())).thenReturn(1L);

        BizException e = assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "", "2000.00")));

        assertEquals(409, e.getCode());
    }

    @Test
    void 并发下的重复插入由唯一约束兜底() {
        when(budgetMapper.selectCount(any())).thenReturn(0L);
        when(budgetMapper.insert(any(Budget.class))).thenThrow(new DuplicateKeyException("duplicate"));

        BizException e = assertThrows(BizException.class,
                () -> budgetService.create(USER_ID, request(MONTH, "餐饮", "600.00")));

        assertEquals(409, e.getCode());
    }

    @Test
    void 修改预算只改金额不改分类() {
        when(budgetMapper.selectOne(any())).thenReturn(budget(5L, "餐饮", "600.00"));
        when(budgetMapper.selectById(5L)).thenReturn(budget(5L, "餐饮", "800.00"));
        when(billMapper.sumByCategory(any(), any(), any())).thenReturn(List.of(categorySum("餐饮", "286.50")));

        BudgetItemResponse response = budgetService.update(USER_ID, 5L, request(MONTH, "交通", "800.00"));

        assertEquals("800.00", response.getAmount());
        assertEquals("餐饮", response.getCategory(), "分类是这条预算的身份，不允许通过修改接口改变");
    }

    @Test
    void 不能修改或删除别人的预算() {
        when(budgetMapper.selectOne(any())).thenReturn(null);

        assertEquals(404, assertThrows(BizException.class,
                () -> budgetService.update(USER_ID, 100L, request(MONTH, "", "100.00"))).getCode());
        assertEquals(404, assertThrows(BizException.class, () -> budgetService.delete(USER_ID, 100L)).getCode());
    }

    private Budget budget(Long id, String category, String amount) {
        Budget budget = new Budget();
        budget.setId(id);
        budget.setUserId(USER_ID);
        budget.setMonth(MONTH);
        budget.setCategory(category);
        budget.setAmount(new BigDecimal(amount));
        return budget;
    }

    private BudgetRequest request(String month, String category, String amount) {
        BudgetRequest request = new BudgetRequest();
        request.setMonth(month);
        request.setCategory(category);
        request.setAmount(new BigDecimal(amount));
        return request;
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
}
