import 'package:campus_ledger/utils/money.dart';

/// 预算预测的总览。
///
/// status 取值：
///   OK                预测可用
///   INSUFFICIENT_DATA 消费数据不足，只显示事实不显示预测结论
///   NO_BUDGET         本月没有设置预算
///   NOT_APPLICABLE    不是当前月份，不做预测
class BudgetPredictionResponse {
  const BudgetPredictionResponse({
    required this.month,
    required this.status,
    required this.message,
    required this.elapsedDays,
    required this.daysInMonth,
    required this.daysLeft,
    required this.items,
  });

  final String month;
  final String status;
  final String message;
  final int elapsedDays;
  final int daysInMonth;
  final int daysLeft;
  final List<BudgetPredictionItem> items;

  bool get isOk => status == 'OK';
  bool get isInsufficient => status == 'INSUFFICIENT_DATA';
  bool get hasNoBudget => status == 'NO_BUDGET';
  bool get isNotApplicable => status == 'NOT_APPLICABLE';

  /// 有预测结论的条目（数据不足的条目不算）
  List<BudgetPredictionItem> get predictedItems =>
      items.where((item) => item.hasPrediction).toList();

  factory BudgetPredictionResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return BudgetPredictionResponse(
      month: json['month'] as String? ?? '',
      status: json['status'] as String? ?? 'NO_BUDGET',
      message: json['message'] as String? ?? '',
      elapsedDays: (json['elapsedDays'] as num?)?.toInt() ?? 0,
      daysInMonth: (json['daysInMonth'] as num?)?.toInt() ?? 0,
      daysLeft: (json['daysLeft'] as num?)?.toInt() ?? 0,
      items: rawItems
          .map((item) => BudgetPredictionItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 单条预算的预测结果。金额一律用字符串解析，保持与项目其余部分一致。
class BudgetPredictionItem {
  const BudgetPredictionItem({
    required this.budgetId,
    required this.category,
    required this.categoryName,
    required this.total,
    required this.budgetAmount,
    required this.spent,
    required this.spentDays,
    required this.elapsedDays,
    required this.dailyAverage,
    required this.projected,
    required this.projectedOver,
    required this.projectedUsageRate,
    required this.overDate,
    required this.daysLeft,
    required this.riskLevel,
    required this.message,
  });

  final int budgetId;

  /// 空串表示月度总预算
  final String category;
  final String categoryName;
  final bool total;

  final String budgetAmount;
  final String spent;

  /// 当月有支出记录的天数
  final int spentDays;
  final int elapsedDays;
  final String dailyAverage;
  final String projected;
  final String projectedOver;
  final String projectedUsageRate;

  /// 预计触顶日期 yyyy-MM-dd，无法预测时为 null
  final String? overDate;
  final int daysLeft;

  /// SAFE / LOW / MEDIUM / HIGH / OVER / INSUFFICIENT_DATA
  final String riskLevel;
  final String message;

  /// 是否有预测结论：数据不足时后端也会返回条目，但不应展示预测
  bool get hasPrediction => riskLevel != 'INSUFFICIENT_DATA' && riskLevel.isNotEmpty;

  /// 根据当前进度决定不可展示预测的操作：数据不足时不显示预测金额
  bool get isInsufficient => riskLevel == 'INSUFFICIENT_DATA';

  /// 风险等级排序权重，越严重越大
  int get riskRank {
    switch (riskLevel) {
      case 'OVER':
        return 5;
      case 'HIGH':
        return 4;
      case 'MEDIUM':
        return 3;
      case 'LOW':
        return 2;
      case 'SAFE':
        return 1;
      default:
        return 0;
    }
  }

  /// 风险中文文案，颜色与图标属于 UI 层，不放在模型里
  String get riskLabel {
    switch (riskLevel) {
      case 'SAFE':
        return '安全';
      case 'LOW':
        return '留意';
      case 'MEDIUM':
        return '接近预算';
      case 'HIGH':
        return '预计超支';
      case 'OVER':
        return '严重超支';
      case 'INSUFFICIENT_DATA':
        return '数据不足';
      default:
        return '';
    }
  }

  /// 当前已用比例（0~1），用于进度条。
  /// 超过 100% 时 clamp 到 1.0，避免进度条取值越界。
  double get currentProgress {
    final budgetCents = Money.toCents(budgetAmount);
    if (budgetCents <= 0) {
      return 0;
    }
    final ratio = Money.toCents(spent) / budgetCents;
    if (ratio.isNaN || ratio < 0) {
      return 0;
    }
    return ratio > 1 ? 1 : ratio;
  }

  /// 当前已用百分比文本，例如 83.3
  String get currentProgressText => _percentText(Money.toCents(spent), Money.toCents(budgetAmount));

  /// 预测使用率百分比文本，例如 147.1
  String get projectedUsageText => _percentText(Money.toCents(projected), Money.toCents(budgetAmount));

  /// 是否预计会超支
  bool get willOverBudget => Money.toCents(projectedOver) > 0;

  /// 触顶日期的展示文本：2026-09-21 → 9月21日
  String? get overDateText {
    final value = overDate;
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 3) {
      return value;
    }
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (month == null || day == null) {
      return value;
    }
    return '$month月$day日';
  }

  static String _percentText(int partCents, int totalCents) {
    if (totalCents <= 0) {
      return '0.0';
    }
    // 只用于展示：整数分相除取一位小数，避免比例误差累积
    return (partCents * 100 / totalCents).toStringAsFixed(1);
  }

  factory BudgetPredictionItem.fromJson(Map<String, dynamic> json) {
    return BudgetPredictionItem(
      budgetId: (json['budgetId'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? '',
      categoryName: json['categoryName'] as String? ?? '',
      total: json['total'] as bool? ?? false,
      budgetAmount: json['budgetAmount'] as String? ?? '0.00',
      spent: json['spent'] as String? ?? '0.00',
      spentDays: (json['spentDays'] as num?)?.toInt() ?? 0,
      elapsedDays: (json['elapsedDays'] as num?)?.toInt() ?? 0,
      dailyAverage: json['dailyAverage'] as String? ?? '0.00',
      projected: json['projected'] as String? ?? '0.00',
      projectedOver: json['projectedOver'] as String? ?? '0.00',
      projectedUsageRate: json['projectedUsageRate'] as String? ?? '0.00',
      overDate: json['overDate'] as String?,
      daysLeft: (json['daysLeft'] as num?)?.toInt() ?? 0,
      riskLevel: json['riskLevel'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}

/// 统计页展示顺序：先按风险等级降序，同等级按预计超支金额降序，再按预算金额降序。
/// 只影响展示，不改变后端返回顺序。
List<BudgetPredictionItem> sortBudgetPredictions(List<BudgetPredictionItem> items) {
  final sorted = List<BudgetPredictionItem>.from(items);
  sorted.sort((a, b) {
    final byRisk = b.riskRank.compareTo(a.riskRank);
    if (byRisk != 0) {
      return byRisk;
    }
    final byOver = Money.toCents(b.projectedOver).compareTo(Money.toCents(a.projectedOver));
    if (byOver != 0) {
      return byOver;
    }
    return Money.toCents(b.budgetAmount).compareTo(Money.toCents(a.budgetAmount));
  });
  return sorted;
}
