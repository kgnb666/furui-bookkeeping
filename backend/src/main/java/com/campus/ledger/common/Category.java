package com.campus.ledger.common;

import java.util.LinkedHashSet;
import java.util.Set;

/**
 * 固定分类集合，后端负责校验，不允许用户随便输入不存在的分类。
 */
public class Category {

    public static final String OTHER = "其他";

    private static final Set<String> EXPENSE = new LinkedHashSet<>(Set.of(
            "餐饮", "交通", "购物", "娱乐", "学习", "住宿", "生活", "医疗", "通讯", OTHER));

    private static final Set<String> INCOME = new LinkedHashSet<>(Set.of(
            "生活费", "奖助学金", "兼职收入", "红包", "其他收入"));

    private static final Set<String> NEUTRAL = new LinkedHashSet<>(Set.of(
            "转账", "红包", "提现", "还款", OTHER));

    private Category() {
    }

    public static Set<String> of(BillType type) {
        if (type == null) {
            return Set.of();
        }
        return switch (type) {
            case EXPENSE -> EXPENSE;
            case INCOME -> INCOME;
            case NEUTRAL -> NEUTRAL;
        };
    }

    public static boolean isValid(BillType type, String category) {
        return type != null && category != null && of(type).contains(category.trim());
    }

    /** 关键词匹配不到时使用的兜底分类 */
    public static String defaultOf(BillType type) {
        return type == BillType.INCOME ? "其他收入" : OTHER;
    }
}
