import 'package:campus_ledger/utils/money.dart';

/// 收支结余分析（对应后端 IncomeBalanceResponse）。
///
/// status 取值：
///   OK                当月有收入记录，可以给出结余与收入结构
///   NO_INCOME_DATA    当月有支出但没有任何收入记录，无法计算结余率
///   NO_DATA           当月既没有收入也没有支出
///   NOT_APPLICABLE    参考月不是当前月份，不做分析
class IncomeBalanceResponse {
  const IncomeBalanceResponse({
    required this.month,
    required this.status,
    required this.message,
    required this.incomeAmount,
    required this.expenseAmount,
    required this.balance,
    required this.balanceRate,
    required this.incomeCount,
    required this.incomeItems,
    required this.previousBalance,
    required this.balanceChange,
    required this.hasPreviousData,
    required this.summary,
  });

  final String month;
  final String status;
  final String message;

  /// 当月收入合计
  final String incomeAmount;

  /// 当月支出合计
  final String expenseAmount;

  /// 当月结余（可能为负）
  final String balance;

  /// 结余率（%）
  final String balanceRate;

  /// 当月收入笔数
  final int incomeCount;

  /// 收入结构（最多 5 项，按金额降序）
  final List<IncomeCategoryItem> incomeItems;

  /// 上月结余
  final String previousBalance;

  /// 与上月结余的差额，上月无数据时为 null
  final String? balanceChange;

  /// 上月是否有收支记录
  final bool hasPreviousData;

  /// 一句话结论
  final String summary;

  bool get isOk => status == 'OK';
  bool get isNoIncomeData => status == 'NO_INCOME_DATA';
  bool get isNoData => status == 'NO_DATA';
  bool get isNotApplicable => status == 'NOT_APPLICABLE';

  /// 结余为负（超支）
  bool get isOverSpent => balance.trim().startsWith('-');

  String get incomeText => '¥${Money.format(incomeAmount)}';

  String get expenseText => '¥${Money.format(expenseAmount)}';

  /// 结余展示文案；负数显示为 -¥x.xx（避免直接对负数字符串做金额换算）
  String get balanceText {
    final raw = balance.trim();
    final negative = raw.startsWith('-');
    final magnitude = negative ? raw.substring(1) : raw;
    return negative ? '-¥${Money.format(magnitude)}' : '¥${Money.format(magnitude)}';
  }

  String get balanceRateText => '结余率 ${trimPercent(balanceRate)}%';

  /// 与上月的对比文案；没有上月数据时返回 null
  String? get comparisonText {
    final change = balanceChange;
    if (!hasPreviousData || change == null || change.trim().isEmpty) {
      return null;
    }
    final raw = change.trim();
    final negative = raw.startsWith('-');
    final magnitude = raw.startsWith('-') || raw.startsWith('+') ? raw.substring(1) : raw;
    final amount = Money.format(magnitude);
    if (negative) {
      return '比上月少存 ¥$amount';
    }
    if (Money.toCents(magnitude) == 0) {
      return '与上月持平';
    }
    return '比上月多存 ¥$amount';
  }

  factory IncomeBalanceResponse.fromJson(Map<String, dynamic> json) {
    // incomeItems 缺失、为 null 或含非对象元素时都按空列表处理，未知字段一律忽略
    final rawItems = json['incomeItems'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(IncomeCategoryItem.fromJson)
            .toList()
        : <IncomeCategoryItem>[];
    return IncomeBalanceResponse(
      month: _text(json['month']),
      status: _text(json['status']),
      message: _text(json['message']),
      incomeAmount: _text(json['incomeAmount'], fallback: '0'),
      expenseAmount: _text(json['expenseAmount'], fallback: '0'),
      balance: _text(json['balance'], fallback: '0'),
      balanceRate: _text(json['balanceRate'], fallback: '0.00'),
      incomeCount: _intOrZero(json['incomeCount']),
      incomeItems: items,
      previousBalance: _text(json['previousBalance'], fallback: '0'),
      balanceChange: _nullableText(json['balanceChange']),
      hasPreviousData: json['hasPreviousData'] == true,
      summary: _text(json['summary']),
    );
  }
}

/// 收入结构里的一项。
class IncomeCategoryItem {
  const IncomeCategoryItem({
    required this.category,
    required this.amount,
    required this.count,
    required this.percentage,
  });

  final String category;
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

  factory IncomeCategoryItem.fromJson(Map<String, dynamic> json) {
    return IncomeCategoryItem(
      category: _text(json['category']),
      amount: _text(json['amount'], fallback: '0'),
      count: _intOrZero(json['count']),
      percentage: _text(json['percentage'], fallback: '0.00'),
    );
  }
}

/// 字段缺失或类型不符时给出安全的默认值
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
  if (!text.contains('.')) {
    return text;
  }
  return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
