package com.campus.ledger.dto;

import com.campus.ledger.entity.User;
import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.LocalDateTime;

/**
 * 返回给前端的用户信息，不包含密码字段。
 */
public class UserInfoResponse {

    private Long id;
    private String username;
    private String nickname;
    private String email;

    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;

    public static UserInfoResponse from(User user) {
        UserInfoResponse info = new UserInfoResponse();
        info.id = user.getId();
        info.username = user.getUsername();
        info.nickname = user.getNickname();
        info.email = user.getEmail();
        info.createdAt = user.getCreatedAt();
        return info;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getNickname() {
        return nickname;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
