package com.campus.ledger.service;

import com.campus.ledger.auth.JwtUtil;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.ChangePasswordRequest;
import com.campus.ledger.dto.LoginRequest;
import com.campus.ledger.dto.LoginResponse;
import com.campus.ledger.dto.RegisterRequest;
import com.campus.ledger.dto.UpdateProfileRequest;
import com.campus.ledger.dto.UserInfoResponse;
import com.campus.ledger.entity.User;
import com.campus.ledger.mapper.UserMapper;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

@Service
public class UserService {

    private final UserMapper userMapper;
    private final JwtUtil jwtUtil;
    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

    public UserService(UserMapper userMapper, JwtUtil jwtUtil) {
        this.userMapper = userMapper;
        this.jwtUtil = jwtUtil;
    }

    public UserInfoResponse register(RegisterRequest request) {
        String username = request.getUsername().trim();
        if (userMapper.findByUsername(username) != null) {
            throw new BizException(409, "用户名已存在");
        }

        User user = new User();
        user.setUsername(username);
        user.setPassword(passwordEncoder.encode(request.getPassword()));
        user.setNickname(StringUtils.hasText(request.getNickname()) ? request.getNickname().trim() : username);
        try {
            userMapper.insert(user);
        } catch (DuplicateKeyException e) {
            // 并发注册同名用户时由数据库唯一索引兜底
            throw new BizException(409, "用户名已存在");
        }
        return UserInfoResponse.from(userMapper.selectById(user.getId()));
    }

    public LoginResponse login(LoginRequest request) {
        User user = userMapper.findByUsername(request.getUsername().trim());
        // 用户不存在与密码错误返回同一提示，避免暴露账号是否存在
        if (user == null || !passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            throw new BizException(401, "用户名或密码错误");
        }
        String token = jwtUtil.generateToken(user.getId(), user.getUsername());
        return new LoginResponse(token, UserInfoResponse.from(user));
    }

    public UserInfoResponse getProfile(Long userId) {
        return UserInfoResponse.from(requireUser(userId));
    }

    public UserInfoResponse updateProfile(Long userId, UpdateProfileRequest request) {
        User user = requireUser(userId);
        if (StringUtils.hasText(request.getNickname())) {
            user.setNickname(request.getNickname().trim());
        }
        if (request.getEmail() != null) {
            user.setEmail(request.getEmail().trim());
        }
        userMapper.updateById(user);
        return UserInfoResponse.from(userMapper.selectById(userId));
    }

    public void changePassword(Long userId, ChangePasswordRequest request) {
        User user = requireUser(userId);
        if (!passwordEncoder.matches(request.getOldPassword(), user.getPassword())) {
            throw new BizException(400, "原密码不正确");
        }
        if (request.getOldPassword().equals(request.getNewPassword())) {
            throw new BizException(400, "新密码不能与原密码相同");
        }

        User update = new User();
        update.setId(userId);
        update.setPassword(passwordEncoder.encode(request.getNewPassword()));
        userMapper.updateById(update);
    }

    private User requireUser(Long userId) {
        User user = userMapper.selectById(userId);
        if (user == null) {
            throw new BizException(404, "用户不存在");
        }
        return user;
    }
}
