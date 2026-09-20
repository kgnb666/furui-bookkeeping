import 'package:intl/intl.dart';

/// 展示用的格式化方法
class Formatters {
  Formatters._();

  /// 2026-09-15 -> 09月15日
  static String billDate(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return date;
    }
    return DateFormat('MM月dd日').format(parsed);
  }

  static String fullDate(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return date;
    }
    return DateFormat('yyyy年MM月dd日').format(parsed);
  }

  /// 账单列表的分组标题：今天 / 昨天 / 2026年09月15日
  static String groupLabel(String date) {
    final parsed = DateTime.tryParse(date);
    if (parsed == null) {
      return date;
    }
    final now = DateTime.now();
    final target = DateTime(parsed.year, parsed.month, parsed.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) {
      return '今天';
    }
    if (diff == 1) {
      return '昨天';
    }
    final sameYear = parsed.year == now.year;
    return DateFormat(sameYear ? 'MM月dd日' : 'yyyy年MM月dd日').format(parsed);
  }

  /// 2026-09 -> 2026年9月
  static String monthLabel(String month) {
    final parts = month.split('-');
    if (parts.length != 2) {
      return month;
    }
    return '${parts[0]}年${int.tryParse(parts[1]) ?? parts[1]}月';
  }

  static String dateTime(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  static String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  static String currentMonth() => DateFormat('yyyy-MM').format(DateTime.now());

  static String apiDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// 最近 12 个月，用于月份筛选
  static List<String> recentMonths() {
    final result = <String>[];
    final now = DateTime.now();
    for (var i = 0; i < 12; i++) {
      final month = DateTime(now.year, now.month - i);
      result.add(DateFormat('yyyy-MM').format(month));
    }
    return result;
  }
}
