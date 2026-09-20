package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.dto.ExportResult;
import com.campus.ledger.service.BillExportService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/**
 * 账单导出。导出范围永远是当前登录用户，不接受前端传入的用户标识。
 */
@RestController
@RequestMapping("/api/bills/export")
public class BillExportController {

    private final BillExportService billExportService;

    public BillExportController(BillExportService billExportService) {
        this.billExportService = billExportService;
    }

    @GetMapping
    public ResponseEntity<byte[]> export(@RequestParam(defaultValue = "csv") String format,
                                         @RequestParam(required = false) String month) {
        ExportResult result = billExportService.export(CurrentUser.get(), format, month);
        String encoded = URLEncoder.encode(result.getFileName(), StandardCharsets.UTF_8)
                .replace("+", "%20");
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_TYPE, result.getContentType())
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"" + result.getFileName() + "\"; filename*=UTF-8''" + encoded)
                .header("X-Export-Filename", encoded)
                .contentType(MediaType.parseMediaType(result.getContentType()))
                .body(result.getContent());
    }
}
