package com.campus.ledger.dto;

import com.campus.ledger.entity.Budget;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * 一条预算及其执行情况：预算金额、已使用、剩余、使用率、状态。
 * 已使用金额由后端根据账单统计得出，前端不再自己算。
 */
public class BudgetItemResponse {

    private Long id;
    private String category;
    private String categoryName;
    private String amount;
    private String used;
    private String remaining;
    private BigDecimal usageRate;
    /** NORMAL / REACHED / OVER */
    private String status;
    private String statusName;

    public static BudgetItemResponse of(Budget budget, BigDecimal usedAmount) {
        BigDecimal amount = budget.getAmount();
        BigDecimal used = usedAmount == null ? BigDecimal.ZERO : usedAmount;
        BigDecimal remaining = amount.subtract(used);
        BigDecimal usageRate = amount.signum() == 0
                ? BigDecimal.ZERO.setScale(2)
                : used.multiply(BigDecimal.valueOf(100)).divide(amount, 2, RoundingMode.HALF_UP);

        int compare = used.compareTo(amount);
        String status = compare < 0 ? "NORMAL" : compare == 0 ? "REACHED" : "OVER";
        String statusName = compare < 0 ? "正常" : compare == 0 ? "已达预算" : "已超支";

        BudgetItemResponse response = new BudgetItemResponse();
        response.id = budget.getId();
        response.category = budget.getCategory();
        response.categoryName = budget.getCategory().isEmpty() ? "月度总预算" : budget.getCategory();
        response.amount = amount.setScale(2, RoundingMode.HALF_UP).toPlainString();
        response.used = used.setScale(2, RoundingMode.HALF_UP).toPlainString();
        response.remaining = remaining.setScale(2, RoundingMode.HALF_UP).toPlainString();
        response.usageRate = usageRate;
        response.status = status;
        response.statusName = statusName;
        return response;
    }

    public Long getId() {
        return id;
    }

    public String getCategory() {
        return category;
    }

    public String getCategoryName() {
        return categoryName;
    }

    public String getAmount() {
        return amount;
    }

    public String getUsed() {
        return used;
    }

    public String getRemaining() {
        return remaining;
    }

    public BigDecimal getUsageRate() {
        return usageRate;
    }

    public String getStatus() {
        return status;
    }

    public String getStatusName() {
        return statusName;
    }
}
