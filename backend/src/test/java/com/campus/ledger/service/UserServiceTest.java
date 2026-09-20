package com.campus.ledger.service;

import com.campus.ledger.auth.JwtUtil;
import com.campus.ledger.common.BizException;
import com.campus.ledger.dto.ChangePasswordRequest;
import com.campus.ledger.dto.LoginRequest;
import com.campus.ledger.dto.LoginResponse;
import com.campus.ledger.dto.RegisterRequest;
import com.campus.ledger.dto.UserInfoResponse;
import com.campus.ledger.entity.User;
import com.campus.ledger.mapper.UserMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    private static final String SECRET = "unit-test-secret-key-2026-must-be-long-enough";

    @Mock
    private UserMapper userMapper;

    private UserService userService;

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    @BeforeEach
    void setUp() {
        userService = new UserService(userMapper, new JwtUtil(SECRET, 7));
    }

    @Test
    void 用户名重复时注册失败() {
        RegisterRequest request = new RegisterRequest();
        request.setUsername("xiaoming");
        request.setPassword("123456");
        when(userMapper.findByUsername("xiaoming")).thenReturn(new User());

        BizException e = assertThrows(BizException.class, () -> userService.register(request));

        assertEquals(409, e.getCode());
        assertEquals("用户名已存在", e.getMessage());
    }

    @Test
    void 注册时密码以BCrypt哈希保存() {
        RegisterRequest request = new RegisterRequest();
        request.setUsername("newuser");
        request.setPassword("123456");
        request.setNickname("新同学");
        when(userMapper.findByUsername("newuser")).thenReturn(null);
        when(userMapper.insert(any(User.class))).thenAnswer(invocation -> {
            User inserted = invocation.getArgument(0);
            inserted.setId(9L);
            return 1;
        });
        when(userMapper.selectById(9L)).thenReturn(savedUser(9L, "newuser", "新同学"));

        UserInfoResponse response = userService.register(request);

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        org.mockito.Mockito.verify(userMapper).insert(captor.capture());
        String storedPassword = captor.getValue().getPassword();
        assertFalse(storedPassword.contains("123456"), "密码不能明文保存");
        assertEquals(60, storedPassword.length(), "BCrypt 哈希长度应为 60");
        assertEquals("newuser", response.getUsername());
    }

    @Test
    void 用户不存在时登录失败() {
        LoginRequest request = new LoginRequest();
        request.setUsername("nobody");
        request.setPassword("123456");
        when(userMapper.findByUsername("nobody")).thenReturn(null);

        BizException e = assertThrows(BizException.class, () -> userService.login(request));

        assertEquals(401, e.getCode());
    }

    @Test
    void 密码错误时登录失败() {
        LoginRequest request = new LoginRequest();
        request.setUsername("xiaoming");
        request.setPassword("wrong-password");
        when(userMapper.findByUsername("xiaoming")).thenReturn(savedUser());

        BizException e = assertThrows(BizException.class, () -> userService.login(request));

        assertEquals(401, e.getCode());
        assertEquals("用户名或密码错误", e.getMessage());
    }

    @Test
    void 登录成功返回可解析的token() {
        LoginRequest request = new LoginRequest();
        request.setUsername("xiaoming");
        request.setPassword("123456");
        when(userMapper.findByUsername("xiaoming")).thenReturn(savedUser());

        LoginResponse response = userService.login(request);

        assertNotNull(response.getToken());
        assertEquals(1L, new JwtUtil(SECRET, 7).parseUserId(response.getToken()));
        assertEquals("xiaoming", response.getUser().getUsername());
    }

    @Test
    void 修改密码时原密码错误则失败() {
        ChangePasswordRequest request = new ChangePasswordRequest();
        request.setOldPassword("wrong");
        request.setNewPassword("newpass123");
        when(userMapper.selectById(1L)).thenReturn(savedUser());

        BizException e = assertThrows(BizException.class, () -> userService.changePassword(1L, request));

        assertEquals(400, e.getCode());
        assertEquals("原密码不正确", e.getMessage());
    }

    @Test
    void 修改密码时新密码与原密码相同时失败() {
        ChangePasswordRequest request = new ChangePasswordRequest();
        request.setOldPassword("123456");
        request.setNewPassword("123456");
        when(userMapper.selectById(1L)).thenReturn(savedUser());

        BizException e = assertThrows(BizException.class, () -> userService.changePassword(1L, request));

        assertEquals(400, e.getCode());
        assertEquals("新密码不能与原密码相同", e.getMessage());
    }

    private User savedUser() {
        return savedUser(1L, "xiaoming", "小明");
    }

    private User savedUser(Long id, String username, String nickname) {
        User user = new User();
        user.setId(id);
        user.setUsername(username);
        user.setNickname(nickname);
        user.setPassword(encoder.encode("123456"));
        return user;
    }
}
