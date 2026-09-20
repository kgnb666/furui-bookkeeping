package com.campus.ledger.common;

/**
 * 业务异常，code 取 HTTP 状态码（400 参数错误 / 401 未登录 / 404 不存在 / 409 冲突）。
 */
public class BizException extends RuntimeException {

    private final int code;

    public BizException(int code, String message) {
        super(message);
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
