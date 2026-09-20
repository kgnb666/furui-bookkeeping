package com.campus.ledger.dto;

/**
 * 分类推荐结果。
 *
 * 每个结果都必须能回答"为什么推荐这个"，因此 reason 不允许为空：
 * 没有足够依据时返回 confidence=NONE 与固定的说明文案。
 */
public class CategoryRecommendResponse {

    /** 推荐分类，没有推荐时为 null */
    private final String category;

    /** HIGH / MEDIUM / LOW / NONE */
    private final String confidence;

    /** 推荐分数，0 表示没有依据 */
    private final int score;

    /** 推荐原因（中文，直接展示给用户） */
    private final String reason;

    /** 依据的历史记录条数，用于前端展示"根据你过去 N 次记录" */
    private final int sampleCount;

    public CategoryRecommendResponse(String category, String confidence, int score,
                                     String reason, int sampleCount) {
        this.category = category;
        this.confidence = confidence;
        this.score = score;
        this.reason = reason;
        this.sampleCount = sampleCount;
    }

    /** 没有推荐时的统一返回 */
    public static CategoryRecommendResponse none() {
        return new CategoryRecommendResponse(null, "NONE", 0, "暂无足够历史记录", 0);
    }

    public String getCategory() {
        return category;
    }

    public String getConfidence() {
        return confidence;
    }

    public int getScore() {
        return score;
    }

    public String getReason() {
        return reason;
    }

    public int getSampleCount() {
        return sampleCount;
    }
}
