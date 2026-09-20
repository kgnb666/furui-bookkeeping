package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.BillRequest;
import com.campus.ledger.dto.BillResponse;
import com.campus.ledger.dto.PageResult;
import com.campus.ledger.service.BillService;
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

import java.math.BigDecimal;

/**
 * 账单接口。当前用户 id 一律取自 JWT，不接受前端传入。
 */
@RestController
@RequestMapping("/api/bills")
public class BillController {

    private final BillService billService;

    public BillController(BillService billService) {
        this.billService = billService;
    }

    @PostMapping
    public ApiResponse<BillResponse> create(@Valid @RequestBody BillRequest request) {
        return ApiResponse.ok("记账成功", billService.create(CurrentUser.get(), request));
    }

    @GetMapping
    public ApiResponse<PageResult<BillResponse>> list(@RequestParam(required = false) String month,
                                                      @RequestParam(required = false) String type,
                                                      @RequestParam(required = false) String category,
                                                      @RequestParam(required = false) String source,
                                                      @RequestParam(required = false) String keyword,
                                                      @RequestParam(required = false) BigDecimal minAmount,
                                                      @RequestParam(required = false) BigDecimal maxAmount,
                                                      @RequestParam(defaultValue = "1") int page,
                                                      @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(billService.page(CurrentUser.get(), month, type, category,
                source, keyword, minAmount, maxAmount, page, size));
    }

    @GetMapping("/{id}")
    public ApiResponse<BillResponse> detail(@PathVariable Long id) {
        return ApiResponse.ok(billService.detail(CurrentUser.get(), id));
    }

    @PutMapping("/{id}")
    public ApiResponse<BillResponse> update(@PathVariable Long id, @Valid @RequestBody BillRequest request) {
        return ApiResponse.ok("修改成功", billService.update(CurrentUser.get(), id, request));
    }

    @DeleteMapping("/{id}")
    public ApiResponse<Void> delete(@PathVariable Long id) {
        billService.delete(CurrentUser.get(), id);
        return ApiResponse.ok("删除成功", null);
    }
}
