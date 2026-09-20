import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/utils/categories.dart';

/// 账单日期分组：列表按天展示时使用。
class BillDateGroup {
  const BillDateGroup({required this.date, required this.bills, required this.income, required this.expense});

  /// 分组日期，格式 yyyy-MM-dd
  final String date;
  final List<Bill> bills;

  /// 当天的收入 / 支出合计（不计收支不参与），字符串保留两位小数
  final String income;
  final String expense;
}

/// 把账单列表按 bill_date 分组，分组内保持原有顺序，分组之间按日期倒序。
class BillGrouping {
  BillGrouping._();

  static List<BillDateGroup> group(List<Bill> bills) {
    final byDate = <String, List<Bill>>{};
    for (final bill in bills) {
      byDate.putIfAbsent(bill.billDate, () => <Bill>[]).add(bill);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final date in dates)
        BillDateGroup(
          date: date,
          bills: byDate[date]!,
          income: _sum(byDate[date]!, income: true),
          expense: _sum(byDate[date]!, income: false),
        ),
    ];
  }

  /// 金额按「分」累加，避免浮点误差
  static String _sum(List<Bill> bills, {required bool income}) {
    var cents = 0;
    for (final bill in bills) {
      final expected = income ? Categories.income : Categories.expense;
      if (bill.type != expected) {
        continue;
      }
      cents += _toCents(bill.amount);
    }
    return (cents / 100).toStringAsFixed(2);
  }

  /// 汇总一批账单的收入与支出，返回 [支出合计, 收入合计]
  static (String expense, String income) totals(List<Bill> bills) {
    var expenseCents = 0;
    var incomeCents = 0;
    for (final bill in bills) {
      if (bill.type == Categories.expense) {
        expenseCents += _toCents(bill.amount);
      } else if (bill.type == Categories.income) {
        incomeCents += _toCents(bill.amount);
      }
    }
    return (
      (expenseCents / 100).toStringAsFixed(2),
      (incomeCents / 100).toStringAsFixed(2),
    );
  }

  static int _toCents(String amount) {
    final text = amount.trim();
    if (text.isEmpty) {
      return 0;
    }
    final negative = text.startsWith('-');
    final parts = (negative ? text.substring(1) : text).split('.');
    final yuan = int.tryParse(parts[0]) ?? 0;
    var cents = 0;
    if (parts.length > 1) {
      final fraction = parts[1].padRight(2, '0').substring(0, 2);
      cents = int.tryParse(fraction) ?? 0;
    }
    final total = yuan * 100 + cents;
    return negative ? -total : total;
  }
}
