package com.campus.ledger.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;

public class ImportConfirmRequest {

    @NotBlank(message = "账单来源不能为空")
    private String source;

    @Size(max = 128, message = "文件名长度不能超过 128 位")
    private String fileName;

    /** 预览阶段解析出的总条数，仅用于导入批次记录 */
    private Integer totalCount;

    @NotEmpty(message = "没有需要导入的记录")
    private List<ImportConfirmItem> items;

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    public Integer getTotalCount() {
        return totalCount;
    }

    public void setTotalCount(Integer totalCount) {
        this.totalCount = totalCount;
    }

    public List<ImportConfirmItem> getItems() {
        return items;
    }

    public void setItems(List<ImportConfirmItem> items) {
        this.items = items;
    }
}
