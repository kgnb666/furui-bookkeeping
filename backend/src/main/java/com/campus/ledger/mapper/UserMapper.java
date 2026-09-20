package com.campus.ledger.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.campus.ledger.entity.User;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;

@Mapper
public interface UserMapper extends BaseMapper<User> {

    @Select("SELECT * FROM `user` WHERE username = #{username} LIMIT 1")
    User findByUsername(@Param("username") String username);
}
