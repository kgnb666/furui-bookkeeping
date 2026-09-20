package com.campus.ledger.service;

import com.campus.ledger.common.BillType;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class CategoryMatcherTest {

    private final CategoryMatcher matcher = new CategoryMatcher();

    @Test
    void 支付宝交易分类优先作为推荐分类() {
        CategoryMatcher.Matched matched = matcher.match(BillType.EXPENSE, "未知商户", "", "餐饮美食");

        assertEquals("餐饮", matched.category());
        assertEquals("ALIPAY_CATEGORY", matched.from());
    }

    @Test
    void 按交易对象关键词匹配分类() {
        assertEquals("餐饮", matcher.match(BillType.EXPENSE, "星巴克(武汉光谷店)", "", null).category());
        assertEquals("交通", matcher.match(BillType.EXPENSE, "滴滴出行", "", null).category());
        assertEquals("购物", matcher.match(BillType.EXPENSE, "京东", "", null).category());
        assertEquals("娱乐", matcher.match(BillType.EXPENSE, "腾讯视频", "", null).category());
        assertEquals("KEYWORD", matcher.match(BillType.EXPENSE, "星巴克", "", null).from());
    }

    @Test
    void 交易对象匹配不到时用备注匹配() {
        CategoryMatcher.Matched matched = matcher.match(BillType.EXPENSE, "某小店", "打车费 18 元", null);

        assertEquals("交通", matched.category());
    }

    @Test
    void 匹配不到时使用兜底分类() {
        assertEquals("其他", matcher.match(BillType.EXPENSE, "不知名小店", "", null).category());
        assertEquals("其他收入", matcher.match(BillType.INCOME, "某人", "", null).category());
        assertEquals("DEFAULT", matcher.match(BillType.EXPENSE, "不知名小店", "", null).from());
    }

    @Test
    void 收入类关键词归到收入分类() {
        assertEquals("生活费", matcher.match(BillType.INCOME, "妈妈", "", null).category());
        assertEquals("奖助学金", matcher.match(BillType.INCOME, "国家奖学金", "", null).category());
    }

    @Test
    void 推荐分类必须符合当前收支类型() {
        // 餐饮属于支出分类，出现在收入账单上时不能直接采用
        assertEquals("其他收入", matcher.match(BillType.INCOME, "星巴克", "", null).category());
    }

    @Test
    void 不计收支有独立的分类集合() {
        assertEquals("提现", matcher.match(BillType.NEUTRAL, "招商银行", "零钱提现", null).category());
    }
}
