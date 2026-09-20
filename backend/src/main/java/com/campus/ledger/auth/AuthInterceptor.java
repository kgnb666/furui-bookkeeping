package com.campus.ledger.auth;

import com.campus.ledger.common.BizException;
import io.jsonwebtoken.JwtException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

/**
 * 校验请求头中的 JWT，并把用户 id 放入 CurrentUser。
 * 当前用户身份只来自这里，任何接口都不接受前端传入的 userId。
 */
@Component
public class AuthInterceptor implements HandlerInterceptor {

    private static final String HEADER = "Authorization";
    private static final String PREFIX = "Bearer ";

    private final JwtUtil jwtUtil;

    public AuthInterceptor(JwtUtil jwtUtil) {
        this.jwtUtil = jwtUtil;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // 浏览器的 CORS 预检请求（OPTIONS）不带 token，直接放行；
        // 真正的业务请求仍然必须带 token。
        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) {
            return true;
        }
        String header = request.getHeader(HEADER);
        if (header == null || !header.startsWith(PREFIX)) {
            throw new BizException(401, "未登录，请先登录");
        }

        String token = header.substring(PREFIX.length()).trim();
        try {
            CurrentUser.set(jwtUtil.parseUserId(token));
        } catch (JwtException | IllegalArgumentException e) {
            throw new BizException(401, "登录已过期或凭证无效，请重新登录");
        }
        return true;
    }

    @Override
    public void afterCompletion(HttpServletRequest request, HttpServletResponse response, Object handler, Exception ex) {
        CurrentUser.clear();
    }
}
