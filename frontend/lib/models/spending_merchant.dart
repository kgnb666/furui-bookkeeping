import 'package:campus_ledger/utils/money.dart';

/// 消费对象分析（对应后端 SpendingMerchantResponse）。
///
/// status 取值：
///   OK                 消费数据充分，可以给出对象排行与集中度
///   INSUFFICIENT_DATA  有支出，但消费天数或交易对象信息不足
///   NO_DATA            当月没有任何支出
///   NOT_APPLICABLE     参考月不是当前月份，不做分析
class SpendingMerchantResponse {
  const SpendingMerchantResponse({
    required this.month,
    required this.status,
    required this.message,
    required this.totalAmount,
    required this.totalCount,
    required this.averageAmount,
    required this.merchantCount,
    required this.merchantCoverage,
    required this.unknownMerchantAmount,
    required this.unknownMerchantRate,
    required this.top3Concentration,
    required this.summary,
    required this.topMerchants,
  });

  final String month;
  final String status;
  final String message;

  /// 当月支出合计
  final String totalAmount;

  /// 当月支出笔数
  final int totalCount;

  /// 整体客单价
  final String averageAmount;

  /// 有效消费对象数量
  final int merchantCount;

  /// 交易对象覆盖率（%）
  final String merchantCoverage;

  /// 未填写交易对象的支出合计
  final String unknownMerchantAmount;

  /// 未填写交易对象的金额占比（%）
  final String unknownMerchantRate;

  /// Top3 消费对象的金额集中度（%）
  final String top3Concentration;

  /// 一句话结论，非 OK 时为空串
  final String summary;

  /// 消费对象排行（最多 5 项）
  final List<MerchantSpendingItem> topMerchants;

  bool get isOk => status == 'OK';
  bool get isInsufficient => status == 'INSUFFICIENT_DATA';
  bool get isNoData => status == 'NO_DATA';
  bool get isNotApplicable => status == 'NOT_APPLICABLE';

  /// 本月支出展示文案
  String get totalText => '¥${Money.format(totalAmount)}';

  /// 消费笔数展示文案
  String get totalCountText => '$totalCount 笔';

  /// 平均客单价展示文案
  String get averageText => '¥${Money.format(averageAmount)}';

  /// 商户覆盖展示文案：已有 xx% 支出记录填写消费对象
  String get coverageText => '已有 ${trimPercent(merchantCoverage)}% 支出记录填写消费对象';

  /// Top3 集中度展示文案
  String get concentrationText => 'Top3 消费对象占比 ${trimPercent(top3Concentration)}%';

  /// 未填写消费对象的提示文案；没有未填写记录时返回 null
  String? get unknownText {
    if (unknownRateValue <= 0) {
      return null;
    }
    return '还有 ${trimPercent(unknownMerchantRate)}% 支出未填写消费对象';
  }

  /// 未填写金额占比的数值（仅用于判断是否展示提示与条形宽度）
  double get unknownRateValue {
    final value = double.tryParse(unknownMerchantRate.trim());
    if (value == null || value.isNaN || value <= 0) {
      return 0;
    }
    return value;
  }

  factory SpendingMerchantResponse.fromJson(Map<String, dynamic> json) {
    // topMerchants 缺失、为 null 或含非对象元素时都按空列表处理，未知字段一律忽略
    final rawItems = json['topMerchants'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(MerchantSpendingItem.fromJson)
            .toList()
        : <MerchantSpendingItem>[];
    return SpendingMerchantResponse(
      month: _text(json['month']),
      status: _text(json['status']),
      message: _text(json['message']),
      totalAmount: _text(json['totalAmount'], fallback: '0'),
      totalCount: _intOrZero(json['totalCount']),
      averageAmount: _text(json['averageAmount'], fallback: '0'),
      merchantCount: _intOrZero(json['merchantCount']),
      merchantCoverage: _text(json['merchantCoverage'], fallback: '0.00'),
      unknownMerchantAmount: _text(json['unknownMerchantAmount'], fallback: '0'),
      unknownMerchantRate: _text(json['unknownMerchantRate'], fallback: '0.00'),
      top3Concentration: _text(json['top3Concentration'], fallback: '0.00'),
      summary: _text(json['summary']),
      topMerchants: items,
    );
  }
}

/// 消费对象排行里的一项。
class MerchantSpendingItem {
  const MerchantSpendingItem({
    required this.merchantName,
    required this.amount,
    required this.count,
    required this.percentage,
  });

  final String merchantName;
  final String amount;
  final int count;
  final String percentage;

  String get amountText => '¥${Money.format(amount)}';

  String get countText => '$count 笔';

  String get percentageText => '${trimPercent(percentage)}%';

  /// 条形长度用（0~1），仅用于渲染宽度，不参与金额计算
  double get ratio {
    final value = double.tryParse(percentage.trim());
    if (value == null || value.isNaN || value <= 0) {
      return 0;
    }
    return value > 100 ? 1 : value / 100;
  }

  factory MerchantSpendingItem.fromJson(Map<String, dynamic> json) {
    return MerchantSpendingItem(
      merchantName: _text(json['merchantName']),
      amount: _text(json['amount'], fallback: '0'),
      count: _intOrZero(json['count']),
      percentage: _text(json['percentage'], fallback: '0.00'),
    );
  }
}

/// 字段缺失或类型不符时给出安全的默认值，避免解析异常冒到界面上
String _text(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

int _intOrZero(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

/// 百分比展示：去掉无意义的小数零（70.00 → 70，12.50 → 12.5）
String trimPercent(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '0';
  }
  final number = double.tryParse(text);
  if (number == null) {
    return text;
  }
  if (number == number.roundToDouble()) {
    return number.toInt().toString();
  }
  // 非整数时去掉尾部多余的 0：12.50 → 12.5
  if (!text.contains('.')) {
    return text;
  }
  return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
