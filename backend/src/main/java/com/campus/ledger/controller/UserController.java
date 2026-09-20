package com.campus.ledger.controller;

import com.campus.ledger.auth.CurrentUser;
import com.campus.ledger.common.ApiResponse;
import com.campus.ledger.dto.ChangePasswordRequest;
import com.campus.ledger.dto.UpdateProfileRequest;
import com.campus.ledger.dto.UserInfoResponse;
import com.campus.ledger.service.UserService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 当前用户身份一律取自 JWT（CurrentUser），不接受前端传入的 userId。
 */
@RestController
@RequestMapping("/api/user")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/profile")
    public ApiResponse<UserInfoResponse> profile() {
        return ApiResponse.ok(userService.getProfile(CurrentUser.get()));
    }

    @PutMapping("/profile")
    public ApiResponse<UserInfoResponse> updateProfile(@Valid @RequestBody UpdateProfileRequest request) {
        return ApiResponse.ok("资料修改成功", userService.updateProfile(CurrentUser.get(), request));
    }

    @PutMapping("/password")
    public ApiResponse<Void> changePassword(@Valid @RequestBody ChangePasswordRequest request) {
        userService.changePassword(CurrentUser.get(), request);
        return ApiResponse.ok("密码修改成功，请重新登录", null);
    }
}
