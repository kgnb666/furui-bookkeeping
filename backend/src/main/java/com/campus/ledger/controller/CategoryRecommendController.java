package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.CategoryRecommendResponse;
import com.campus.ledger.service.CategoryRecommendService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 分类推荐。只是"建议"，不会修改任何账单；
 * 依据的历史记录固定取自当前登录用户，前端无法指定用户。
 */
@RestController
@RequestMapping("/api/categories")
public class CategoryRecommendController {

    private final CategoryRecommendService categoryRecommendService;

    public CategoryRecommendController(CategoryRecommendService categoryRecommendService) {
        this.categoryRecommendService = categoryRecommendService;
    }

    @GetMapping("/recommend")
    public ApiResponse<CategoryRecommendResponse> recommend(
            @RequestParam(required = false) String merchant,
            @RequestParam(required = false) String note,
            @RequestParam(defaultValue = "EXPENSE") String type) {
        return ApiResponse.ok(categoryRecommendService.recommend(
                CurrentUser.get(), merchant, note, type));
    }
}
