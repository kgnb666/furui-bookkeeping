package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.BudgetItemResponse;
import com.campus.ledger.dto.BudgetPredictionResponse;
import com.campus.ledger.dto.BudgetRequest;
import com.campus.ledger.dto.BudgetResponse;
import com.campus.ledger.service.BudgetPredictionService;
import com.campus.ledger.service.BudgetService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/budgets")
public class BudgetController {

    private final BudgetService budgetService;
    private final BudgetPredictionService budgetPredictionService;

    public BudgetController(BudgetService budgetService,
                            BudgetPredictionService budgetPredictionService) {
        this.budgetService = budgetService;
        this.budgetPredictionService = budgetPredictionService;
    }

    @GetMapping
    public ApiResponse<BudgetResponse> list(@RequestParam String month) {
        return ApiResponse.ok(budgetService.list(CurrentUser.get(), month));
    }

    /**
     * 预算预测：只预测当前月份，依据当前登录用户自己的账单与预算。
     * 数据不足或没有预算时返回明确状态，不编造预测结论。
     */
    @GetMapping("/predictions")
    public ApiResponse<BudgetPredictionResponse> predictions(@RequestParam String month) {
        return ApiResponse.ok(budgetPredictionService.predict(CurrentUser.get(), month));
    }

    @PostMapping
    public ApiResponse<BudgetItemResponse> create(@Valid @RequestBody BudgetRequest request) {
        return ApiResponse.ok("预算设置成功", budgetService.create(CurrentUser.get(), request));
    }

    @PutMapping("/{id}")
    public ApiResponse<BudgetItemResponse> update(@PathVariable Long id,
                                                  @Valid @RequestBody BudgetRequest request) {
        return ApiResponse.ok("预算修改成功", budgetService.update(CurrentUser.get(), id, request));
    }

    @DeleteMapping("/{id}")
    public ApiResponse<Void> delete(@PathVariable Long id) {
        budgetService.delete(CurrentUser.get(), id);
        return ApiResponse.ok("预算已删除", null);
    }
}
