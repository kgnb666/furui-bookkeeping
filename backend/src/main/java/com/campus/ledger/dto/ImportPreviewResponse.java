package com.campus.ledger.dto;

import java.util.List;

/**
 * 导入预览结果，本接口不写数据库。
 */
public class ImportPreviewResponse {

    private String source;
    private String sourceName;
    private String fileName;
    private int totalCount;
    private int newCount;
    private int duplicateCount;
    private int neutralCount;
    private int failedCount;
    private List<ImportPreviewItem> items;

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

    public int getNewCount() {
        return newCount;
    }

    public void setNewCount(int newCount) {
        this.newCount = newCount;
    }

    public int getDuplicateCount() {
        return duplicateCount;
    }

    public void setDuplicateCount(int duplicateCount) {
        this.duplicateCount = duplicateCount;
    }

    public int getNeutralCount() {
        return neutralCount;
    }

    public void setNeutralCount(int neutralCount) {
        this.neutralCount = neutralCount;
    }

    public int getFailedCount() {
        return failedCount;
    }

    public void setFailedCount(int failedCount) {
        this.failedCount = failedCount;
    }

    public List<ImportPreviewItem> getItems() {
        return items;
    }

    public void setItems(List<ImportPreviewItem> items) {
        this.items = items;
    }
}
