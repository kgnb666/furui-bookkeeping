/// 一条预算及其执行情况，已使用金额由后端统计
class BudgetItem {
  BudgetItem({
    required this.id,
    required this.category,
    required this.categoryName,
    required this.amount,
    required this.used,
    required this.remaining,
    required this.usageRate,
    required this.status,
    required this.statusName,
  });

  final int id;

  /// 空串表示月度总预算
  final String category;
  final String categoryName;
  final String amount;
  final String used;
  final String remaining;
  final double usageRate;

  /// NORMAL / REACHED / OVER
  final String status;
  final String statusName;

  bool get isTotal => category.isEmpty;
  bool get isOver => status == 'OVER';
  bool get isReached => status == 'REACHED';

  factory BudgetItem.fromJson(Map<String, dynamic> json) {
    return BudgetItem(
      id: (json['id'] as num).toInt(),
      category: json['category'] as String? ?? '',
      categoryName: json['categoryName'] as String? ?? '',
      amount: json['amount'] as String? ?? '0.00',
      used: json['used'] as String? ?? '0.00',
      remaining: json['remaining'] as String? ?? '0.00',
      usageRate: (json['usageRate'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'NORMAL',
      statusName: json['statusName'] as String? ?? '正常',
    );
  }
}

/// 某个月的预算总览
class BudgetSummary {
  BudgetSummary({
    required this.month,
    required this.monthExpense,
    required this.total,
    required this.categories,
  });

  final String month;
  final String monthExpense;
  final BudgetItem? total;
  final List<BudgetItem> categories;

  factory BudgetSummary.fromJson(Map<String, dynamic> json) {
    final rawTotal = json['total'];
    return BudgetSummary(
      month: json['month'] as String? ?? '',
      monthExpense: json['monthExpense'] as String? ?? '0.00',
      total: rawTotal == null ? null : BudgetItem.fromJson(rawTotal as Map<String, dynamic>),
      categories: (json['categories'] as List<dynamic>? ?? [])
          .map((item) => BudgetItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
