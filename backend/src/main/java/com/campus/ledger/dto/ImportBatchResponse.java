package com.campus.ledger.dto;

import com.campus.ledger.common.BillSource;
import com.campus.ledger.entity.ImportBatch;
import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.LocalDateTime;

public class ImportBatchResponse {

    private Long id;
    private String source;
    private String sourceName;
    private String fileName;
    private int totalCount;
    private int importedCount;
    private int duplicateCount;
    private int failedCount;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;

    public static ImportBatchResponse from(ImportBatch batch) {
        ImportBatchResponse response = new ImportBatchResponse();
        response.id = batch.getId();
        response.source = batch.getSource();
        BillSource source = BillSource.parse(batch.getSource());
        response.sourceName = source == null ? "" : source.getLabel();
        response.fileName = batch.getFileName();
        response.totalCount = batch.getTotalCount() == null ? 0 : batch.getTotalCount();
        response.importedCount = batch.getImportedCount() == null ? 0 : batch.getImportedCount();
        response.duplicateCount = batch.getDuplicateCount() == null ? 0 : batch.getDuplicateCount();
        response.failedCount = batch.getFailedCount() == null ? 0 : batch.getFailedCount();
        response.createdAt = batch.getCreatedAt();
        return response;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public String getSourceName() {
        return sourceName;
    }

    public void setSourceName(String sourceName) {
        this.sourceName = sourceName;
    }

    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    public int getTotalCount() {
        return totalCount;
    }

    public void setTotalCount(int totalCount) {
        this.totalCount = totalCount;
    }

    public int getImportedCount() {
        return importedCount;
    }

    public void setImportedCount(int importedCount) {
        this.importedCount = importedCount;
    }

    public int getDuplicateCount() {
        return duplicateCount;
    }

    public void setDuplicateCount(int duplicateCount) {
        this.duplicateCount = duplicateCount;
    }

    public int getFailedCount() {
        return failedCount;
    }

    public void setFailedCount(int failedCount) {
        this.failedCount = failedCount;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
