package com.campus.ledger.auth;

import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class JwtUtilTest {

    private static final String SECRET = "unit-test-secret-key-2026-must-be-long-enough";

    private final JwtUtil jwtUtil = new JwtUtil(SECRET, 7);

    @Test
    void 生成的token可以解析出userId() {
        String token = jwtUtil.generateToken(12L, "xiaoming");

        assertEquals(12L, jwtUtil.parseUserId(token));
    }

    @Test
    void 被篡改的token解析失败() {
        String token = jwtUtil.generateToken(12L, "xiaoming");
        // 只改签名段中前部的字符：base64url 末尾带填充位，
        // 改最后两个字符有极小概率不影响解码结果，会让这个用例偶发失败
        int index = token.length() - 10;
        char replaced = token.charAt(index) == 'a' ? 'b' : 'a';
        String tampered = token.substring(0, index) + replaced + token.substring(index + 1);

        assertThrows(JwtException.class, () -> jwtUtil.parseUserId(tampered));
    }

    @Test
    void 过期token解析抛出ExpiredJwtException() {
        // expire-days 传负数，签发出来的 token 立即过期
        JwtUtil expiredJwtUtil = new JwtUtil(SECRET, -1);
        String token = expiredJwtUtil.generateToken(12L, "xiaoming");

        assertThrows(ExpiredJwtException.class, () -> jwtUtil.parseUserId(token));
    }

    @Test
    void 使用其他密钥签发的token无法解析() {
        JwtUtil other = new JwtUtil("another-secret-key-2026-for-test-only-32bytes", 7);
        String token = other.generateToken(12L, "xiaoming");

        assertThrows(JwtException.class, () -> jwtUtil.parseUserId(token));
    }
}
