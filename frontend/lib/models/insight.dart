/// 分类推荐结果。没有推荐时 category 为 null、confidence 为 NONE。
class CategoryRecommend {
  const CategoryRecommend({
    required this.category,
    required this.confidence,
    required this.score,
    required this.reason,
    required this.sampleCount,
  });

  final String? category;

  /// HIGH / MEDIUM / LOW / NONE
  final String confidence;
  final int score;
  final String reason;
  final int sampleCount;

  /// 是否有可用推荐
  bool get hasSuggestion => category != null && category!.isNotEmpty && confidence != 'NONE';

  /// 置信度中文说明，用于前端展示
  String get confidenceLabel {
    switch (confidence) {
      case 'HIGH':
        return '高可信';
      case 'MEDIUM':
        return '中等可信';
      case 'LOW':
        return '仅供参考';
      default:
        return '';
    }
  }

  factory CategoryRecommend.fromJson(Map<String, dynamic> json) {
    return CategoryRecommend(
      category: json['category'] as String?,
      confidence: json['confidence'] as String? ?? 'NONE',
      score: (json['score'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一条消费洞察
class Insight {
  const Insight({
    required this.type,
    required this.priority,
    required this.level,
    required this.title,
    required this.message,
    required this.amount,
  });

  final String type;
  final int priority;

  /// WARNING / INFO
  final String level;
  final String title;
  final String message;
  final String amount;

  bool get isWarning => level == 'WARNING';

  factory Insight.fromJson(Map<String, dynamic> json) {
    return Insight(
      type: json['type'] as String? ?? '',
      priority: (json['priority'] as num?)?.toInt() ?? 99,
      level: json['level'] as String? ?? 'INFO',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      amount: json['amount'] as String? ?? '0.00',
    );
  }
}

/// 某个月的消费洞察
class MonthlyInsights {
  const MonthlyInsights({
    required this.month,
    required this.expense,
    required this.income,
    required this.balance,
    required this.expenseChangePercent,
    required this.topCategory,
    required this.topCategoryPercent,
    required this.summary,
    required this.insights,
  });

  final String month;
  final String expense;
  final String income;
  final String balance;
  final String? expenseChangePercent;
  final String? topCategory;
  final String? topCategoryPercent;

  /// 一句话摘要，首页直接展示
  final String summary;
  final List<Insight> insights;

  bool get hasInsights => insights.isNotEmpty;

  factory MonthlyInsights.fromJson(Map<String, dynamic> json) {
    final list = json['insights'] as List<dynamic>? ?? const [];
    return MonthlyInsights(
      month: json['month'] as String? ?? '',
      expense: json['expense'] as String? ?? '0.00',
      income: json['income'] as String? ?? '0.00',
      balance: json['balance'] as String? ?? '0.00',
      expenseChangePercent: json['expenseChangePercent'] as String?,
      topCategory: json['topCategory'] as String?,
      topCategoryPercent: json['topCategoryPercent'] as String?,
      summary: json['summary'] as String? ?? '',
      insights: list
          .map((item) => Insight.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
