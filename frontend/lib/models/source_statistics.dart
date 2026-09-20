/// 支付来源统计：金额与占比都由后端算好
class SourceStat {
  SourceStat({
    required this.source,
    required this.sourceName,
    required this.amount,
    required this.percentage,
  });

  /// MANUAL / WECHAT / ALIPAY
  final String source;

  /// 手动记录 / 微信 / 支付宝
  final String sourceName;

  final String amount;

  /// 占比只用于展示，不是金额
  final double percentage;

  factory SourceStat.fromJson(Map<String, dynamic> json) {
    return SourceStat(
      source: json['source'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      amount: json['amount'] as String? ?? '0.00',
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
    );
  }
}
