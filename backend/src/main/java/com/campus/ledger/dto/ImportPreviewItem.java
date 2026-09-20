package com.campus.ledger.dto;

public class ImportPreviewItem {

    private int rowIndex;
    private String billDate;
    private String sourceTradeTime;
    private String merchant;
    private String remark;
    private String amount;
    private Integer type;
    private String typeName;
    private String category;
    /** 推荐分类来自哪一步：ALIPAY_CATEGORY / KEYWORD / DEFAULT */
    private String categoryFrom;
    private String sourceTradeId;
    private boolean duplicate;
    private String duplicateReason;
    /** 解析失败的行不允许导入 */
    private boolean importable;
    private boolean defaultSelected;
    private String failReason;

    public int getRowIndex() {
        return rowIndex;
    }

    public void setRowIndex(int rowIndex) {
        this.rowIndex = rowIndex;
    }

    public String getBillDate() {
        return billDate;
    }

    public void setBillDate(String billDate) {
        this.billDate = billDate;
    }

    public String getSourceTradeTime() {
        return sourceTradeTime;
    }

    public void setSourceTradeTime(String sourceTradeTime) {
        this.sourceTradeTime = sourceTradeTime;
    }

    public String getMerchant() {
        return merchant;
    }

    public void setMerchant(String merchant) {
        this.merchant = merchant;
    }

    public String getRemark() {
        return remark;
    }

    public void setRemark(String remark) {
        this.remark = remark;
    }

    public String getAmount() {
        return amount;
    }

    public void setAmount(String amount) {
        this.amount = amount;
    }

    public Integer getType() {
        return type;
    }

    public void setType(Integer type) {
        this.type = type;
    }

    public String getTypeName() {
        return typeName;
    }

    public void setTypeName(String typeName) {
        this.typeName = typeName;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getCategoryFrom() {
        return categoryFrom;
    }

    public void setCategoryFrom(String categoryFrom) {
        this.categoryFrom = categoryFrom;
    }

    public String getSourceTradeId() {
        return sourceTradeId;
    }

    public void setSourceTradeId(String sourceTradeId) {
        this.sourceTradeId = sourceTradeId;
    }

    public boolean isDuplicate() {
        return duplicate;
    }

    public void setDuplicate(boolean duplicate) {
        this.duplicate = duplicate;
    }

    public String getDuplicateReason() {
        return duplicateReason;
    }

    public void setDuplicateReason(String duplicateReason) {
        this.duplicateReason = duplicateReason;
    }

    public boolean isImportable() {
        return importable;
    }

    public void setImportable(boolean importable) {
        this.importable = importable;
    }

    public boolean isDefaultSelected() {
        return defaultSelected;
    }

    public void setDefaultSelected(boolean defaultSelected) {
        this.defaultSelected = defaultSelected;
    }

    public String getFailReason() {
        return failReason;
    }

    public void setFailReason(String failReason) {
        this.failReason = failReason;
    }
}
