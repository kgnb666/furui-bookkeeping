import 'package:campus_ledger/utils/money.dart';

/// 周期性账单识别的总览。
///
/// status 取值：
///   OK                   识别到周期性支出
///   NO_DATA              记录太少
///   NOT_ENOUGH_HISTORY   账单时间跨度太短
///   NO_RECURRING         数据足够但没发现周期
class RecurringBills {
  const RecurringBills({
    required this.windowDays,
    required this.status,
    required this.message,
    required this.items,
  });

  final int windowDays;
  final String status;
  final String message;
  final List<RecurringBill> items;

  bool get isOk => status == 'OK';
  bool get isNoData => status == 'NO_DATA';
  bool get isNotEnoughHistory => status == 'NOT_ENOUGH_HISTORY';
  bool get isNoRecurring => status == 'NO_RECURRING';

  /// 有展示价值的结果：后端只返回 HIGH / MEDIUM，这里再挡一层防御
  List<RecurringBill> get displayable =>
      items.where((item) => item.isHigh || item.isMedium).toList();

  factory RecurringBills.fromJson(Map<String, dynamic> json) {
    // items 缺失或为 null 时按空列表处理，未知字段一律忽略
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(RecurringBill.fromJson)
            .toList()
        : <RecurringBill>[];
    return RecurringBills(
      windowDays: (json['windowDays'] as num?)?.toInt() ?? 180,
      status: json['status'] as String? ?? 'NO_DATA',
      message: json['message'] as String? ?? '',
      items: items,
    );
  }
}

/// 一条周期性支出。
class RecurringBill {
  const RecurringBill({
    required this.merchant,
    required this.category,
    required this.cycleType,
    required this.cycleLabel,
    required this.confidence,
    required this.confidenceLabel,
    required this.sampleCount,
    required this.averageAmount,
    required this.averageInterval,
    required this.intervalRange,
    required this.lastDate,
    required this.nextDate,
    required this.reason,
  });

  final String merchant;
  final String category;

  /// WEEKLY / BIWEEKLY / MONTHLY
  final String cycleType;
  final String cycleLabel;

  /// HIGH / MEDIUM / LOW
  final String confidence;
  final String confidenceLabel;

  final int sampleCount;

  /// 金额保持字符串，前端不做浮点计算
  final String averageAmount;
  final int averageInterval;
  final String intervalRange;

  /// yyyy-MM-dd，可能为空
  final String? lastDate;
  final String? nextDate;
  final String reason;

  bool get isHigh => confidence == 'HIGH';
  bool get isMedium => confidence == 'MEDIUM';
  bool get isLow => confidence == 'LOW';

  /// 周期中文名；未知周期类型安全降级，不抛异常
  String get cycleText {
    switch (cycleType) {
      case 'WEEKLY':
        return '每周一次';
      case 'BIWEEKLY':
        return '每两周一次';
      case 'MONTHLY':
        return '每月一次';
      default:
        // 后端已给出中文时优先用它，否则退回通用文案
        return cycleLabel.isNotEmpty ? cycleLabel : '周期性支出';
    }
  }

  /// 置信度中文名；未知值安全降级为空
  String get confidenceText {
    switch (confidence) {
      case 'HIGH':
        return '高可信';
      case 'MEDIUM':
        return '中可信';
      case 'LOW':
        return '低可信';
      default:
        return confidenceLabel;
    }
  }

  /// 展示用金额，统一两位小数
  String get amountText => Money.format(averageAmount);

  /// 排序权重：HIGH > MEDIUM > LOW
  int get confidenceRank {
    switch (confidence) {
      case 'HIGH':
        return 3;
      case 'MEDIUM':
        return 2;
      case 'LOW':
        return 1;
      default:
        return 0;
    }
  }

  factory RecurringBill.fromJson(Map<String, dynamic> json) {
    return RecurringBill(
      merchant: json['merchant'] as String? ?? '',
      category: json['category'] as String? ?? '',
      cycleType: json['cycleType'] as String? ?? '',
      cycleLabel: json['cycleLabel'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'LOW',
      confidenceLabel: json['confidenceLabel'] as String? ?? '',
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      averageAmount: json['averageAmount'] as String? ?? '0.00',
      averageInterval: (json['averageInterval'] as num?)?.toInt() ?? 0,
      intervalRange: json['intervalRange'] as String? ?? '',
      lastDate: json['lastDate'] as String?,
      nextDate: json['nextDate'] as String?,
      reason: json['reason'] as String? ?? '',
    );
  }
}

/// 前端稳定排序：
///   1. 置信度 HIGH > MEDIUM > LOW
///   2. 下一次日期越近越优先（无日期的排最后）
///   3. 平均金额越高越优先
///   4. 商户字典序，保证结果稳定
List<RecurringBill> sortRecurringBills(List<RecurringBill> items) {
  final sorted = List<RecurringBill>.from(items);
  sorted.sort((a, b) {
    final byConfidence = b.confidenceRank.compareTo(a.confidenceRank);
    if (byConfidence != 0) {
      return byConfidence;
    }
    final aNext = _parseDate(a.nextDate);
    final bNext = _parseDate(b.nextDate);
    if (aNext != null && bNext != null) {
      final byDate = aNext.compareTo(bNext);
      if (byDate != 0) {
        return byDate;
      }
    } else if (aNext != null || bNext != null) {
      return aNext != null ? -1 : 1;
    }
    final byAmount = Money.toCents(b.averageAmount).compareTo(Money.toCents(a.averageAmount));
    if (byAmount != 0) {
      return byAmount;
    }
    return a.merchant.compareTo(b.merchant);
  });
  return sorted;
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
