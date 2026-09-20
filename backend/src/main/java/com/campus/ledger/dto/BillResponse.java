package com.campus.ledger.dto;

import com.campus.ledger.common.BillSource;
import com.campus.ledger.common.BillType;
import com.campus.ledger.entity.Bill;
import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.LocalDate;
import java.time.LocalDateTime;

public class BillResponse {

    private Long id;
    private Integer type;
    private String typeName;
    /** 金额用字符串返回，避免前端浮点精度问题 */
    private String amount;
    private String category;

    @JsonFormat(pattern = "yyyy-MM-dd")
    private LocalDate billDate;

    private String merchant;
    private String remark;
    private String source;
    private String sourceName;
    private String sourceTradeId;
    private Long importBatchId;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;

    public static BillResponse from(Bill bill) {
        BillResponse response = new BillResponse();
        response.id = bill.getId();
        response.type = bill.getType();
        BillType type = BillType.of(bill.getType());
        response.typeName = type == null ? "" : type.getLabel();
        response.amount = bill.getAmount() == null ? "0.00" : bill.getAmount().toPlainString();
        response.category = bill.getCategory();
        response.billDate = bill.getBillDate();
        response.merchant = bill.getMerchant();
        response.remark = bill.getRemark();
        response.source = bill.getSource();
        BillSource source = BillSource.parse(bill.getSource());
        response.sourceName = source == null ? "" : source.getLabel();
        response.sourceTradeId = bill.getSourceTradeId();
        response.importBatchId = bill.getImportBatchId();
        response.createdAt = bill.getCreatedAt();
        return response;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
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

    public String getAmount() {
        return amount;
    }

    public void setAmount(String amount) {
        this.amount = amount;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public LocalDate getBillDate() {
        return billDate;
    }

    public void setBillDate(LocalDate billDate) {
        this.billDate = billDate;
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

    public String getSourceTradeId() {
        return sourceTradeId;
    }

    public void setSourceTradeId(String sourceTradeId) {
        this.sourceTradeId = sourceTradeId;
    }

    public Long getImportBatchId() {
        return importBatchId;
    }

    public void setImportBatchId(Long importBatchId) {
        this.importBatchId = importBatchId;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
