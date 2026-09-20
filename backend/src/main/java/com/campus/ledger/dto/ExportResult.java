package com.campus.ledger.dto;

/**
 * 账单导出结果：文件名、内容类型与文件字节。
 */
public class ExportResult {

    private final String fileName;
    private final String contentType;
    private final byte[] content;

    public ExportResult(String fileName, String contentType, byte[] content) {
        this.fileName = fileName;
        this.contentType = contentType;
        this.content = content;
    }

    public String getFileName() {
        return fileName;
    }

    public String getContentType() {
        return contentType;
    }

    public byte[] getContent() {
        return content;
    }
}
