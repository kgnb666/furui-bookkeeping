package com.campus.ledger.auth;

/**
 * 保存当前请求的登录用户 id，由 AuthInterceptor 写入，请求结束后清理。
 */
public class CurrentUser {

    private static final ThreadLocal<Long> HOLDER = new ThreadLocal<>();

    private CurrentUser() {
    }

    public static void set(Long userId) {
        HOLDER.set(userId);
    }

    public static Long get() {
        return HOLDER.get();
    }

    public static void clear() {
        HOLDER.remove();
    }
}
