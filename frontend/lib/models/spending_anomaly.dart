import 'package:campus_ledger/utils/money.dart';

/// 消费异常检测的总览。
///
/// status 取值：
///   OK                    检测到至少 1 条异常
///   NO_DATA               目标月份没有支出记录
///   NOT_ENOUGH_BASELINE   有支出，但前几个月没有数据，无法建立基线
///   NO_ANOMALY            基线可用且未检测到异常
class AnomaliesResponse {
  const AnomaliesResponse({
    required this.month,
    required this.status,
    required this.message,
    required this.baselineMonths,
    required this.items,
  });

  final String month;
  final String status;
  final String message;

  /// 参与对比的前 3 个自然月
  final List<String> baselineMonths;
  final List<SpendingAnomaly> items;

  bool get isOk => status == 'OK';
  bool get isNoData => status == 'NO_DATA';
  bool get isNotEnoughBaseline => status == 'NOT_ENOUGH_BASELINE';
  bool get isNoAnomaly => status == 'NO_ANOMALY';

  factory AnomaliesResponse.fromJson(Map<String, dynamic> json) {
    // items 缺失、为 null 或含非对象元素时都按空列表处理，未知字段一律忽略
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(SpendingAnomaly.fromJson)
            .toList()
        : <SpendingAnomaly>[];
    final rawMonths = json['baselineMonths'];
    final months = rawMonths is List
        ? rawMonths.whereType<String>().toList()
        : <String>[];
    return AnomaliesResponse(
      month: json['month'] as String? ?? '',
      status: json['status'] as String? ?? 'NO_DATA',
      message: json['message'] as String? ?? '',
      baselineMonths: months,
      items: items,
    );
  }
}

/// 一条消费异常。字段与后端 AnomalyItem 一一对应，不做额外扩展。
class SpendingAnomaly {
  const SpendingAnomaly({
    required this.type,
    required this.severity,
    required this.severityLabel,
    required this.category,
    required this.title,
    required this.message,
    required this.currentAmount,
    required this.baselineAmount,
    required this.difference,
    required this.changePercent,
    required this.merchant,
    required this.billDate,
  });

  /// CATEGORY_SPIKE / LARGE_TRANSACTION / FREQUENCY_SPIKE
  final String type;

  /// HIGH / MEDIUM
  final String severity;
  final String severityLabel;

  final String category;
  final String title;
  final String message;

  /// 金额一律是字符串，前端不做浮点计算
  final String currentAmount;
  final String baselineAmount;
  final String difference;
  final String changePercent;

  /// 仅单笔异常有值
  final String? merchant;
  final String? billDate;

  bool get isHigh => severity == 'HIGH';
  bool get isMedium => severity == 'MEDIUM';
  bool get isCategorySpike => type == 'CATEGORY_SPIKE';
  bool get isLargeTransaction => type == 'LARGE_TRANSACTION';
  bool get isFrequencySpike => type == 'FREQUENCY_SPIKE';

  /// 严重度中文名；未知值安全降级为后端给的中文，再退回空
  String get severityText {
    switch (severity) {
      case 'HIGH':
        return '需注意';
      case 'MEDIUM':
        return '留意';
      default:
        return severityLabel;
    }
  }

  /// 异常类型图标，按类型区分：金额上涨、单笔、频次
  bool get isAmountBased => isCategorySpike || isLargeTransaction;

  /// 分类类异常的金额展示用两位小数；频次类的 current/baseline 是笔数，原样展示
  String get currentText => isAmountBased ? '¥${Money.format(currentAmount)}' : currentAmount;

  String get baselineText => isAmountBased ? '¥${Money.format(baselineAmount)}' : baselineAmount;

  String get differenceText => isAmountBased
      ? '¥${Money.format(difference)}'
      : '$difference 笔';

  /// 日期展示：2026-09-10 → 2026年09月10日；缺失返回 null
  String? get billDateText {
    final value = billDate;
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return '${parsed.year}年${parsed.month.toString().padLeft(2, '0')}月'
        '${parsed.day.toString().padLeft(2, '0')}日';
  }

  /// 定位文案：单笔异常优先用商户，商户为空时退回分类
  String get locationText {
    final name = (merchant == null || merchant!.isEmpty) ? category : merchant!;
    final date = billDateText;
    return date == null ? name : '$name · $date';
  }

  factory SpendingAnomaly.fromJson(Map<String, dynamic> json) {
    return SpendingAnomaly(
      type: json['type'] as String? ?? '',
      severity: json['severity'] as String? ?? 'MEDIUM',
      severityLabel: json['severityLabel'] as String? ?? '',
      category: json['category'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      currentAmount: json['currentAmount'] as String? ?? '0',
      baselineAmount: json['baselineAmount'] as String? ?? '0',
      difference: json['difference'] as String? ?? '0',
      changePercent: json['changePercent'] as String? ?? '0',
      merchant: json['merchant'] as String?,
      billDate: json['billDate'] as String?,
    );
  }
}
