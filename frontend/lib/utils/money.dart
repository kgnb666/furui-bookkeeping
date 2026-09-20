/// 金额处理：只做字符串校验和整数分相加，不使用 double。
class Money {
  Money._();

  static final RegExp _pattern = RegExp(r'^\d{1,8}(\.\d{1,2})?$');

  /// 校验用户输入的金额，合法时返回 null，否则返回错误提示
  static String? validate(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return '请输入金额';
    }
    if (!_pattern.hasMatch(text)) {
      return '金额格式不正确（最多两位小数）';
    }
    if (toCents(text) <= 0) {
      return '金额必须大于 0';
    }
    return null;
  }

  /// 转成整数分，避免浮点误差
  static int toCents(String amount) {
    final text = amount.trim();
    if (text.isEmpty) {
      return 0;
    }
    final parts = text.split('.');
    final yuan = int.tryParse(parts[0]) ?? 0;
    var cents = 0;
    if (parts.length > 1) {
      final fraction = parts[1].padRight(2, '0').substring(0, 2);
      cents = int.tryParse(fraction) ?? 0;
    }
    return yuan * 100 + cents;
  }

  static String fromCents(int cents) {
    final negative = cents < 0;
    final abs = negative ? -cents : cents;
    final text = '${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
    return negative ? '-$text' : text;
  }

  /// 展示用格式化：统一保留两位小数，避免出现 ¥15 或 ¥15.0
  static String format(String amount) => fromCents(toCents(amount));

  /// 把展示用的金额字符串相加，结果保留两位小数
  static String sum(Iterable<String> amounts) {
    var total = 0;
    for (final amount in amounts) {
      total += toCents(amount);
    }
    return fromCents(total);
  }
}
