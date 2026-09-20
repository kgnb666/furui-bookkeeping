import 'package:campus_ledger/utils/money.dart';

/// 消费节奏与时间分布分析（对应后端 SpendingRhythmResponse）。
///
/// status 取值：
///   OK                 可以给出节奏分析
///   INSUFFICIENT_DATA  当月有支出，但有消费记录的天数不足，无法判断节奏
///   NO_DATA            当月没有任何支出
///   NOT_APPLICABLE     参考月不是当前月份，不做分析
class SpendingRhythmResponse {
  const SpendingRhythmResponse({
    required this.month,
    required this.status,
    required this.message,
    required this.totalAmount,
    required this.coveredDays,
    required this.coveredRate,
    required this.peakWeekday,
    required this.peakPeriod,
    required this.concentration,
    required this.summary,
    required this.weekdayItems,
    required this.periodItems,
  });

  final String month;
  final String status;
  final String message;

  /// 当月支出合计
  final String totalAmount;

  /// 当月有支出记录的天数
  final int coveredDays;

  /// 记账覆盖率（%），字符串两位小数
  final String coveredRate;

  /// 支出最高的星期名称，非 OK 时为空串
  final String peakWeekday;

  /// 支出最高的月内阶段名称，非 OK 时为空串
  final String peakPeriod;

  /// 消费集中度：最高星期金额 ÷ 总支出 × 100
  final String concentration;

  /// 一句话结论，非 OK 时为空串
  final String summary;

  /// 固定 7 项：周一 ~ 周日
  final List<WeekdaySpendingItem> weekdayItems;

  /// 固定 3 项：1-10 日 / 11-20 日 / 21 日-月底
  final List<PeriodSpendingItem> periodItems;

  bool get isOk => status == 'OK';
  bool get isInsufficient => status == 'INSUFFICIENT_DATA';
  bool get isNoData => status == 'NO_DATA';
  bool get isNotApplicable => status == 'NOT_APPLICABLE';

  /// 总支出展示文案
  String get totalText => '¥${Money.format(totalAmount)}';

  /// 记账覆盖展示文案：已有 N 天消费
  String get coveredDaysText => '已有 $coveredDays 天消费';

  /// 覆盖率展示文案：覆盖率 xx%
  String get coveredRateText => '覆盖率 ${_trimPercent(coveredRate)}%';

  /// 消费集中度展示文案
  String get concentrationText => '${_trimPercent(concentration)}%';

  factory SpendingRhythmResponse.fromJson(Map<String, dynamic> json) {
    // weekdayItems / periodItems 缺失、为 null 或含非对象元素时都按空列表处理，未知字段一律忽略
    final rawWeekdays = json['weekdayItems'];
    final weekdays = rawWeekdays is List
        ? rawWeekdays
            .whereType<Map<String, dynamic>>()
            .map(WeekdaySpendingItem.fromJson)
            .toList()
        : <WeekdaySpendingItem>[];
    final rawPeriods = json['periodItems'];
    final periods = rawPeriods is List
        ? rawPeriods
            .whereType<Map<String, dynamic>>()
            .map(PeriodSpendingItem.fromJson)
            .toList()
        : <PeriodSpendingItem>[];
    return SpendingRhythmResponse(
      month: _text(json['month']),
      status: _text(json['status']),
      message: _text(json['message']),
      totalAmount: _text(json['totalAmount'], fallback: '0'),
      coveredDays: _intOrZero(json['coveredDays']),
      coveredRate: _text(json['coveredRate'], fallback: '0.00'),
      peakWeekday: _text(json['peakWeekday']),
      peakPeriod: _text(json['peakPeriod']),
      concentration: _text(json['concentration'], fallback: '0.00'),
      summary: _text(json['summary']),
      weekdayItems: weekdays,
      periodItems: periods,
    );
  }
}

/// 星期维度的支出分布。
class WeekdaySpendingItem {
  const WeekdaySpendingItem({
    required this.weekday,
    required this.weekdayName,
    required this.amount,
    required this.percentage,
  });

  /// 1 = 周一 … 7 = 周日
  final int weekday;
  final String weekdayName;
  final String amount;
  final String percentage;

  String get amountText => '¥${Money.format(amount)}';

  String get percentageText => '${_trimPercent(percentage)}%';

  /// 条形长度用（0~1），仅用于展示宽度，不参与金额计算
  double get ratio {
    final value = double.tryParse(percentage.trim()) ?? 0;
    if (value.isNaN || value <= 0) {
      return 0;
    }
    return value > 100 ? 1 : value / 100;
  }

  factory WeekdaySpendingItem.fromJson(Map<String, dynamic> json) {
    return WeekdaySpendingItem(
      weekday: _intOrZero(json['weekday']),
      weekdayName: _text(json['weekdayName']),
      amount: _text(json['amount'], fallback: '0'),
      percentage: _text(json['percentage'], fallback: '0.00'),
    );
  }
}

/// 月内阶段的支出分布。
class PeriodSpendingItem {
  const PeriodSpendingItem({
    required this.periodName,
    required this.startDay,
    required this.endDay,
    required this.amount,
    required this.percentage,
  });

  final String periodName;
  final int startDay;
  final int endDay;
  final String amount;
  final String percentage;

  String get amountText => '¥${Money.format(amount)}';

  String get percentageText => '${_trimPercent(percentage)}%';

  /// 形如「1-10日（第 1-10 天）」，用起止日把阶段说清楚
  String get rangeText => '$periodName（第 $startDay-$endDay 天）';

  double get ratio {
    final value = double.tryParse(percentage.trim()) ?? 0;
    if (value.isNaN || value <= 0) {
      return 0;
    }
    return value > 100 ? 1 : value / 100;
  }

  factory PeriodSpendingItem.fromJson(Map<String, dynamic> json) {
    return PeriodSpendingItem(
      periodName: _text(json['periodName']),
      startDay: _intOrZero(json['startDay']),
      endDay: _intOrZero(json['endDay']),
      amount: _text(json['amount'], fallback: '0'),
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

/// 百分比展示：去掉无意义的小数零（60.00 → 60，12.50 → 12.5）
String _trimPercent(String value) {
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
  return text;
}
