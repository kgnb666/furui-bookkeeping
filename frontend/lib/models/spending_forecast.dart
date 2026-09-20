import 'package:campus_ledger/utils/money.dart';

/// 下月支出预估（对应后端 SpendingForecastResponse）。
///
/// status 取值：
///   OK                  至少 3 个有支出的完整自然月，可以给出预估
///   INSUFFICIENT_DATA   有支出历史，但完整月份不足 3 个
///   NO_DATA             没有任何支出记录
///   NOT_APPLICABLE      参考月不是当前月份，不做预估
class SpendingForecastResponse {
  const SpendingForecastResponse({
    required this.month,
    required this.targetMonth,
    required this.status,
    required this.message,
    required this.confidence,
    required this.confidenceLabel,
    required this.confidenceReason,
    required this.predictedAmount,
    required this.previousMonthAmount,
    required this.predictedDifference,
    required this.predictedChangePercent,
    required this.currentMonthAmount,
    required this.elapsedDays,
    required this.sampleMonths,
  });

  /// 参考月（前端当前选中的月份）
  final String month;

  /// 被预估的月份（参考月的下一个月）
  final String targetMonth;

  final String status;
  final String message;

  /// HIGH / MEDIUM / LOW，非 OK 时为 NONE
  final String confidence;

  /// 后端给的置信度文案，仅在 confidence 未知时作为回退
  final String confidenceLabel;
  final String confidenceReason;

  final String predictedAmount;
  final String previousMonthAmount;

  /// 与最近有效月份的差额，非 OK 时为 null
  final String? predictedDifference;

  /// 变化率（%），无法比较时为 null
  final String? predictedChangePercent;

  /// 参考月至今的实际支出，只做事实陈述
  final String currentMonthAmount;

  /// 参考月已过天数
  final int? elapsedDays;

  /// 参与预估的历史月份（最多 3 条，按时间倒序）
  final List<ForecastSampleMonth> sampleMonths;

  bool get isOk => status == 'OK';
  bool get isInsufficient => status == 'INSUFFICIENT_DATA';
  bool get isNoData => status == 'NO_DATA';
  bool get isNotApplicable => status == 'NOT_APPLICABLE';

  /// 置信度的展示文案：以后端返回的 confidence 为依据，
  /// 未知取值时回退到后端给的中文（仍为空则显示"未知"）。
  String get confidenceText {
    switch (confidence) {
      case 'HIGH':
        return '较稳定';
      case 'MEDIUM':
        return '一般';
      case 'LOW':
        return '波动较大';
      default:
        return confidenceLabel.isEmpty ? '未知' : confidenceLabel;
    }
  }

  /// 差额方向：-1 减少 / 0 持平 / 1 增加 / null 无法比较
  int? get differenceSign {
    final text = _signedText(predictedDifference);
    if (text == null) {
      return null;
    }
    if (text.startsWith('-')) {
      return -1;
    }
    if (text.startsWith('+')) {
      return 1;
    }
    return Money.toCents(text) == 0 ? 0 : 1;
  }

  /// 差额的绝对金额文案（两位小数），无法比较时为 null
  String? get differenceAmountText {
    final text = _signedText(predictedDifference);
    if (text == null) {
      return null;
    }
    return Money.format(text.replaceFirst(RegExp(r'^[+-]'), ''));
  }

  /// 与上月的对比文案，无法比较时为 null
  String? get differenceText {
    final sign = differenceSign;
    final amount = differenceAmountText;
    if (sign == null || amount == null) {
      return null;
    }
    if (sign > 0) {
      return '较上月增加 ¥$amount';
    }
    if (sign < 0) {
      return '较上月减少 ¥$amount';
    }
    return '与上月持平';
  }

  /// 变化率文案：正数补 +，持平或不显示；无法比较时为 null
  String? get changePercentText {
    final text = _signedText(predictedChangePercent);
    if (text == null) {
      return null;
    }
    final body = text.replaceFirst(RegExp(r'^[+-]'), '');
    if (Money.toCents(body) == 0) {
      return null;
    }
    return text.startsWith('-') ? '（-$body%）' : '（+$body%）';
  }

  /// 预估方向用于配色：减少用绿色（少花是好事），增加用暖红
  bool get isDecrease => differenceSign != null && differenceSign! < 0;

  factory SpendingForecastResponse.fromJson(Map<String, dynamic> json) {
    // sampleMonths 缺失、为 null 或含非对象元素时都按空列表处理，未知字段一律忽略
    final rawSamples = json['sampleMonths'];
    final samples = rawSamples is List
        ? rawSamples
            .whereType<Map<String, dynamic>>()
            .map(ForecastSampleMonth.fromJson)
            .toList()
        : <ForecastSampleMonth>[];
    return SpendingForecastResponse(
      month: _text(json['month']),
      targetMonth: _text(json['targetMonth']),
      status: _text(json['status']),
      message: _text(json['message']),
      confidence: _text(json['confidence']),
      confidenceLabel: _text(json['confidenceLabel']),
      confidenceReason: _text(json['confidenceReason']),
      predictedAmount: _text(json['predictedAmount'], fallback: '0'),
      previousMonthAmount: _text(json['previousMonthAmount'], fallback: '0'),
      predictedDifference: _nullableText(json['predictedDifference']),
      predictedChangePercent: _nullableText(json['predictedChangePercent']),
      currentMonthAmount: _text(json['currentMonthAmount'], fallback: '0'),
      elapsedDays: _intOrNull(json['elapsedDays']),
      sampleMonths: samples,
    );
  }
}

/// 一个参与预估的历史月份样本。
class ForecastSampleMonth {
  const ForecastSampleMonth({
    required this.month,
    required this.amount,
    required this.weight,
  });

  /// 格式 yyyy-MM
  final String month;
  final String amount;

  /// 参与加权的权重（正常 3 / 2 / 1，异常月降为 1）
  final int weight;

  String get amountText => '¥${Money.format(amount)}';

  String get weightText => '×$weight';

  factory ForecastSampleMonth.fromJson(Map<String, dynamic> json) {
    return ForecastSampleMonth(
      month: _text(json['month']),
      amount: _text(json['amount'], fallback: '0'),
      weight: _intOrNull(json['weight']) ?? 0,
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

String? _nullableText(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// 去掉空串与纯空白，供差额 / 变化率这类可空文本使用
String? _signedText(String? value) {
  if (value == null) {
    return null;
  }
  final text = value.trim();
  return text.isEmpty ? null : text;
}
