package com.campus.ledger.controller;

import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.LoginRequest;
import com.campus.ledger.dto.LoginResponse;
import com.campus.ledger.dto.RegisterRequest;
import com.campus.ledger.dto.UserInfoResponse;
import com.campus.ledger.service.UserService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final UserService userService;

    public AuthController(UserService userService) {
        this.userService = userService;
    }

    @PostMapping("/register")
    public ApiResponse<UserInfoResponse> register(@Valid @RequestBody RegisterRequest request) {
        return ApiResponse.ok("注册成功", userService.register(request));
    }

    @PostMapping("/login")
    public ApiResponse<LoginResponse> login(@Valid @RequestBody LoginRequest request) {
        return ApiResponse.ok("登录成功", userService.login(request));
    }
}
