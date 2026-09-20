import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/utils/bill_grouping.dart';
import 'package:campus_ledger/utils/formatters.dart';

Bill _bill({
  required int id,
  required int type,
  required String amount,
  required String date,
  String category = '餐饮',
}) {
  return Bill(
    id: id,
    type: type,
    typeName: '支出',
    amount: amount,
    category: category,
    billDate: date,
    merchant: '',
    remark: '',
    source: 'MANUAL',
    sourceName: '手动记录',
  );
}

void main() {
  test('按日期分组并保持倒序', () {
    final groups = BillGrouping.group([
      _bill(id: 1, type: 1, amount: '20.00', date: '2026-09-16'),
      _bill(id: 2, type: 1, amount: '2.00', date: '2026-09-15'),
      _bill(id: 3, type: 2, amount: '100.00', date: '2026-09-15'),
      _bill(id: 4, type: 1, amount: '5.00', date: '2026-09-16'),
    ]);

    expect(groups.length, 2);
    expect(groups.first.date, '2026-09-16');
    expect(groups.first.bills.length, 2);
    expect(groups.last.date, '2026-09-15');
    expect(groups.last.bills.length, 2);
  });

  test('分组内的收支合计正确且不计收支不参与', () {
    final groups = BillGrouping.group([
      _bill(id: 1, type: 1, amount: '20.00', date: '2026-09-16'),
      _bill(id: 2, type: 1, amount: '0.10', date: '2026-09-16'),
      _bill(id: 3, type: 2, amount: '100.00', date: '2026-09-16'),
      _bill(id: 4, type: 3, amount: '200.00', date: '2026-09-16'),
    ]);

    final today = groups.single;
    expect(today.expense, '20.10');
    expect(today.income, '100.00');
  });

  test('金额合计不出现浮点误差', () {
    final groups = BillGrouping.group([
      _bill(id: 1, type: 1, amount: '0.10', date: '2026-09-16'),
      _bill(id: 2, type: 1, amount: '0.20', date: '2026-09-16'),
    ]);

    expect(groups.single.expense, '0.30');
  });

  test('总数汇总返回支出与收入', () {
    final totals = BillGrouping.totals([
      _bill(id: 1, type: 1, amount: '15.50', date: '2026-09-16'),
      _bill(id: 2, type: 2, amount: '8.25', date: '2026-09-16'),
      _bill(id: 3, type: 3, amount: '99.99', date: '2026-09-16'),
    ]);

    expect(totals.$1, '15.50');
    expect(totals.$2, '8.25');
  });

  test('日期分组标题区分今天、昨天与更早日期', () {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    String api(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    expect(Formatters.groupLabel(api(today)), '今天');
    expect(Formatters.groupLabel(api(yesterday)), '昨天');
    expect(Formatters.groupLabel('2020-03-05'), '2020年03月05日');
  });
}
