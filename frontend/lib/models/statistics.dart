/// 月度概览：收入、支出、结余（金额都是字符串）
class MonthlyStat {
  MonthlyStat({
    required this.month,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final String month;
  final String income;
  final String expense;
  final String balance;

  factory MonthlyStat.fromJson(Map<String, dynamic> json) {
    return MonthlyStat(
      month: json['month'] as String? ?? '',
      income: json['income'] as String? ?? '0.00',
      expense: json['expense'] as String? ?? '0.00',
      balance: json['balance'] as String? ?? '0.00',
    );
  }
}

/// 分类支出：金额与占比都由后端算好
class CategoryStat {
  CategoryStat({
    required this.category,
    required this.amount,
    required this.percentage,
  });

  final String category;
  final String amount;

  /// 占比只用于展示与画图，不是金额
  final double percentage;

  factory CategoryStat.fromJson(Map<String, dynamic> json) {
    return CategoryStat(
      category: json['category'] as String? ?? '',
      amount: json['amount'] as String? ?? '0.00',
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 每日趋势中的一天
class DailyStat {
  DailyStat({
    required this.date,
    required this.income,
    required this.expense,
  });

  final String date;
  final String income;
  final String expense;

  factory DailyStat.fromJson(Map<String, dynamic> json) {
    return DailyStat(
      date: json['date'] as String? ?? '',
      income: json['income'] as String? ?? '0.00',
      expense: json['expense'] as String? ?? '0.00',
    );
  }
}

/// 某一天的收支合计，首页「今日收入 / 今日支出」使用
class DailySummary {
  DailySummary({
    required this.date,
    required this.income,
    required this.expense,
  });

  final String date;
  final String income;
  final String expense;

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    return DailySummary(
      date: json['date'] as String? ?? '',
      income: json['income'] as String? ?? '0.00',
      expense: json['expense'] as String? ?? '0.00',
    );
  }
}

/// 消费趋势：本月与上月支出对比，首页用来提示"比上月多花还是少花"
class TrendStat {
  TrendStat({
    required this.month,
    required this.currentExpense,
    required this.currentIncome,
    required this.previousMonth,
    required this.previousExpense,
    required this.previousHasData,
    this.expenseChangePercent,
  });

  final String month;
  final String currentExpense;
  final String currentIncome;
  final String previousMonth;
  final String previousExpense;

  /// 上月完全没有账单时为 false，此时不做对比
  final bool previousHasData;

  /// 支出变化率（%），正数表示比上月多花；无法比较时为 null
  final String? expenseChangePercent;

  /// 能否展示对比结论
  bool get canCompare => previousHasData && expenseChangePercent != null;

  /// 支出是否比上月增加
  bool get isUp {
    final value = num.tryParse(expenseChangePercent ?? '');
    return value != null && value > 0;
  }

  /// 变化率的绝对值文本，例如 12.35
  String get changeText {
    final value = num.tryParse(expenseChangePercent ?? '');
    if (value == null) {
      return '';
    }
    return value.abs().toStringAsFixed(2);
  }

  factory TrendStat.fromJson(Map<String, dynamic> json) {
    return TrendStat(
      month: json['month'] as String? ?? '',
      currentExpense: json['currentExpense'] as String? ?? '0.00',
      currentIncome: json['currentIncome'] as String? ?? '0.00',
      previousMonth: json['previousMonth'] as String? ?? '',
      previousExpense: json['previousExpense'] as String? ?? '0.00',
      previousHasData: json['previousHasData'] as bool? ?? false,
      expenseChangePercent: json['expenseChangePercent'] as String?,
    );
  }
}
