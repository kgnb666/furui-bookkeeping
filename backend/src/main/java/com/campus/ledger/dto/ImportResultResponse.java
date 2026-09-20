package com.campus.ledger.dto;

import java.util.List;

public class ImportResultResponse {

    private Long batchId;
    private int totalCount;
    private int importedCount;
    private int duplicateCount;
    private int failedCount;
    private List<FailItem> failures;

    public Long getBatchId() {
        return batchId;
    }

    public void setBatchId(Long batchId) {
        this.batchId = batchId;
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

    public List<FailItem> getFailures() {
        return failures;
    }

    public void setFailures(List<FailItem> failures) {
        this.failures = failures;
    }

    /** 服务端二次校验失败的原因，便于用户定位 */
    public record FailItem(int index, String merchant, String reason) {
    }
}
