package com.campus.ledger.config;

import com.baomidou.mybatisplus.annotation.DbType;
import com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;

@Configuration
public class MybatisPlusConfig {

    /** 账单列表需要分页查询 */
    @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor() {
        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        interceptor.addInnerInterceptor(new PaginationInnerInterceptor(DbType.MYSQL));
        return interceptor;
    }

    /**
     * 统一的时钟来源。预算预测需要"今天是几号"，注入 Clock 后单元测试可以固定日期，
     * 不用依赖机器当前时间。
     */
    @Bean
    public Clock systemClock() {
        return Clock.systemDefaultZone();
    }
}
