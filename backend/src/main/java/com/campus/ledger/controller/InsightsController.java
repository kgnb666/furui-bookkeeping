package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.MonthlyInsightsResponse;
import com.campus.ledger.dto.AnomaliesResponse;
import com.campus.ledger.dto.RecurringBillsResponse;
import com.campus.ledger.dto.SpendingForecastResponse;
import com.campus.ledger.dto.SpendingRhythmResponse;
import com.campus.ledger.dto.SpendingMerchantResponse;
import com.campus.ledger.dto.IncomeBalanceResponse;
import com.campus.ledger.service.InsightsService;
import com.campus.ledger.service.RecurringBillService;
import com.campus.ledger.service.SpendingAnomalyService;
import com.campus.ledger.service.SpendingForecastService;
import com.campus.ledger.service.SpendingRhythmService;
import com.campus.ledger.service.SpendingMerchantService;
import com.campus.ledger.service.IncomeBalanceService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 消费洞察。全部由后端按规则计算，不使用大模型，也不读取其他用户的数据。
 */
@RestController
@RequestMapping("/api/insights")
public class InsightsController {

    private final InsightsService insightsService;
    private final RecurringBillService recurringBillService;
    private final SpendingAnomalyService spendingAnomalyService;
    private final SpendingForecastService spendingForecastService;
    private final SpendingRhythmService spendingRhythmService;
    private final SpendingMerchantService spendingMerchantService;
    private final IncomeBalanceService incomeBalanceService;

    public InsightsController(InsightsService insightsService,
                              RecurringBillService recurringBillService,
                              SpendingAnomalyService spendingAnomalyService,
                              SpendingForecastService spendingForecastService,
                              SpendingRhythmService spendingRhythmService,
                              SpendingMerchantService spendingMerchantService,
                              IncomeBalanceService incomeBalanceService) {
        this.insightsService = insightsService;
        this.recurringBillService = recurringBillService;
        this.spendingAnomalyService = spendingAnomalyService;
        this.spendingForecastService = spendingForecastService;
        this.spendingRhythmService = spendingRhythmService;
        this.spendingMerchantService = spendingMerchantService;
        this.incomeBalanceService = incomeBalanceService;
    }

    @GetMapping("/monthly")
    public ApiResponse<MonthlyInsightsResponse> monthly(@RequestParam String month) {
        return ApiResponse.ok(insightsService.monthly(CurrentUser.get(), month));
    }

    /**
     * 周期性账单识别：分析最近 180 天的支出，返回可能的周期消费。
     * 只读取当前登录用户自己的账单，结果实时计算不落库。
     */
    @GetMapping("/recurring")
    public ApiResponse<RecurringBillsResponse> recurring(
            @RequestParam(required = false) String type) {
        return ApiResponse.ok(recurringBillService.detect(CurrentUser.get(), type));
    }

    /**
     * 消费异常检测：对比目标月份与它之前的 3 个自然月，找出偏离常态的消费。
     * 只允许查询最近 12 个自然月，用户身份取自 JWT。
     */
    @GetMapping("/anomalies")
    public ApiResponse<AnomaliesResponse> anomalies(@RequestParam String month) {
        return ApiResponse.ok(spendingAnomalyService.detect(CurrentUser.get(), month));
    }

    /**
     * 下月支出预估：用参考月之前最近 3 个「有支出的完整自然月」按 3:2:1 加权，
     * 预估下一个月的支出总额。不依赖预算，只对当前月份给出结论，
     * 过去与未来月份返回 NOT_APPLICABLE。用户身份取自 JWT，一次聚合查询、结果不落库。
     */
    @GetMapping("/forecast")
    public ApiResponse<SpendingForecastResponse> forecast(@RequestParam String month) {
        return ApiResponse.ok(spendingForecastService.forecast(CurrentUser.get(), month));
    }

    /**
     * 消费节奏分析：分析参考月里"钱花在什么时候"（星期分布与月内阶段分布）。
     * 只分析当前月份，过去与未来月份返回 NOT_APPLICABLE；
     * 用户身份取自 JWT，一次按天聚合查询、结果不落库。
     */
    @GetMapping("/rhythm")
    public ApiResponse<SpendingRhythmResponse> rhythm(@RequestParam String month) {
        return ApiResponse.ok(spendingRhythmService.analyze(CurrentUser.get(), month));
    }

    /**
     * 消费对象分析：回答"我的钱主要花在哪些商户"。
     * 只分析当前月份的支出明细，按消费对象聚合金额与笔数并给出集中度；
     * 用户身份取自 JWT，一次明细查询、结果不落库。
     */
    @GetMapping("/merchants")
    public ApiResponse<SpendingMerchantResponse> merchants(@RequestParam String month) {
        return ApiResponse.ok(spendingMerchantService.analyze(CurrentUser.get(), month));
    }

    /**
     * 收支结余分析：回答"我这个月存下了多少"，补齐此前只有支出分析的空白。
     * 只分析当前月份的收入、支出、结余、结余率与收入结构；
     * 没有收入记录时返回 NO_INCOME_DATA 并如实给出支出事实，不编造结余率。
     */
    @GetMapping("/balance")
    public ApiResponse<IncomeBalanceResponse> balance(@RequestParam String month) {
        return ApiResponse.ok(incomeBalanceService.analyze(CurrentUser.get(), month));
    }
}
