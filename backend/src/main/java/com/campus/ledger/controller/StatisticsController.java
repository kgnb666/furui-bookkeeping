package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.CategoryStatResponse;
import com.campus.ledger.dto.DailyStatResponse;
import com.campus.ledger.dto.DailySummaryResponse;
import com.campus.ledger.dto.MonthlyStatResponse;
import com.campus.ledger.dto.SourceStatResponse;
import com.campus.ledger.dto.TrendsResponse;
import com.campus.ledger.service.StatisticsService;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;

/**
 * 统计接口。统计范围始终是当前登录用户，前端不传 userId。
 */
@RestController
@RequestMapping("/api/statistics")
public class StatisticsController {

    private final StatisticsService statisticsService;

    public StatisticsController(StatisticsService statisticsService) {
        this.statisticsService = statisticsService;
    }

    @GetMapping("/monthly")
    public ApiResponse<MonthlyStatResponse> monthly(@RequestParam String month) {
        return ApiResponse.ok(statisticsService.monthly(CurrentUser.get(), month));
    }

    @GetMapping("/category")
    public ApiResponse<List<CategoryStatResponse>> category(@RequestParam String month) {
        return ApiResponse.ok(statisticsService.category(CurrentUser.get(), month));
    }

    @GetMapping("/daily")
    public ApiResponse<List<DailyStatResponse>> daily(@RequestParam String month) {
        return ApiResponse.ok(statisticsService.daily(CurrentUser.get(), month));
    }

    @GetMapping("/source")
    public ApiResponse<List<SourceStatResponse>> source(@RequestParam String month) {
        return ApiResponse.ok(statisticsService.source(CurrentUser.get(), month));
    }

    /** 某天的收支合计，不传 date 表示服务器当天（首页今日收入/支出使用） */
    @GetMapping("/daily-summary")
    public ApiResponse<DailySummaryResponse> dailySummary(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return ApiResponse.ok(statisticsService.dailySummary(CurrentUser.get(), date));
    }

    /** 消费趋势：本月与上月支出对比（首页使用） */
    @GetMapping("/trends")
    public ApiResponse<TrendsResponse> trends(@RequestParam String month) {
        return ApiResponse.ok(statisticsService.trends(CurrentUser.get(), month));
    }
}
