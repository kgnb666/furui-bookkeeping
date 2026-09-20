package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import com.campus.ledger.common.Category;
import com.campus.ledger.importer.BillFields;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 自动分类：支付宝自带交易分类映射 + 关键词匹配，匹配不到用兜底分类。
 * 结果只是推荐值，用户可以在导入预览里修改。
 */
@Component
public class CategoryMatcher {

    /** 支付宝“交易分类”到系统分类的映射 */
    private static final Map<String, String> ALIPAY_CATEGORY = new LinkedHashMap<>();

    static {
        ALIPAY_CATEGORY.put("餐饮美食", "餐饮");
        ALIPAY_CATEGORY.put("交通出行", "交通");
        ALIPAY_CATEGORY.put("日用百货", "生活");
        ALIPAY_CATEGORY.put("生活服务", "生活");
        ALIPAY_CATEGORY.put("服饰装扮", "购物");
        ALIPAY_CATEGORY.put("数码电器", "购物");
        ALIPAY_CATEGORY.put("文化休闲", "娱乐");
        ALIPAY_CATEGORY.put("教育培训", "学习");
        ALIPAY_CATEGORY.put("住房物业", "住宿");
        ALIPAY_CATEGORY.put("医疗健康", "医疗");
        ALIPAY_CATEGORY.put("通讯物流", "通讯");
        ALIPAY_CATEGORY.put("投资理财", "其他");
        ALIPAY_CATEGORY.put("转账红包", "其他");
        ALIPAY_CATEGORY.put("亲友代付", "其他");
        ALIPAY_CATEGORY.put("退款", "其他");
    }

    private final List<Rule> rules = new ArrayList<>();

    public CategoryMatcher() {
        loadRules();
    }

    private void loadRules() {
        ClassPathResource resource = new ClassPathResource("category-rules.txt");
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(resource.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String text = line.trim();
                if (text.isEmpty() || text.startsWith("#")) {
                    continue;
                }
                String[] parts = text.split("\\|");
                if (parts.length == 2) {
                    rules.add(new Rule(parts[0].trim(), parts[1].trim()));
                }
            }
        } catch (IOException e) {
            throw new IllegalStateException("分类规则文件 category-rules.txt 读取失败", e);
        }
    }

    public Matched match(BillType type, String merchant, String remark, String categoryHint) {
        String hintCategory = ALIPAY_CATEGORY.get(BillFields.clean(categoryHint));
        if (hintCategory != null && Category.isValid(type, hintCategory)) {
            return new Matched(hintCategory, "ALIPAY_CATEGORY");
        }
        String byMerchant = matchByKeyword(type, BillFields.clean(merchant));
        if (byMerchant != null) {
            return new Matched(byMerchant, "KEYWORD");
        }
        String byRemark = matchByKeyword(type, BillFields.clean(remark));
        if (byRemark != null) {
            return new Matched(byRemark, "KEYWORD");
        }
        return new Matched(Category.defaultOf(type), "DEFAULT");
    }

    private String matchByKeyword(BillType type, String text) {
        if (text.isEmpty()) {
            return null;
        }
        for (Rule rule : rules) {
            if (text.contains(rule.keyword()) && Category.isValid(type, rule.category())) {
                return rule.category();
            }
        }
        return null;
    }

    private record Rule(String keyword, String category) {
    }

    /** 推荐分类以及它来自哪一步匹配 */
    public record Matched(String category, String from) {
    }
}
