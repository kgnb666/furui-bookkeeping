package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.ImportBatchResponse;
import com.campus.ledger.dto.ImportConfirmRequest;
import com.campus.ledger.dto.ImportPreviewResponse;
import com.campus.ledger.dto.ImportResultResponse;
import com.campus.ledger.service.BillImportService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

@RestController
@RequestMapping("/api/bills/import")
public class BillImportController {

    private final BillImportService billImportService;

    public BillImportController(BillImportService billImportService) {
        this.billImportService = billImportService;
    }

    /** 上传账单文件解析并返回预览，不写数据库 */
    @PostMapping("/preview")
    public ApiResponse<ImportPreviewResponse> preview(@RequestParam("file") MultipartFile file,
                                                      @RequestParam("source") String source) {
        return ApiResponse.ok("解析完成", billImportService.preview(CurrentUser.get(), file, source));
    }

    /** 用户确认后才真正写入数据库 */
    @PostMapping("/confirm")
    public ApiResponse<ImportResultResponse> confirm(@Valid @RequestBody ImportConfirmRequest request) {
        return ApiResponse.ok("导入完成", billImportService.confirm(CurrentUser.get(), request));
    }

    @GetMapping("/batches")
    public ApiResponse<List<ImportBatchResponse>> batches() {
        return ApiResponse.ok(billImportService.batches(CurrentUser.get()));
    }
}
