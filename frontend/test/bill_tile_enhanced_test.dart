import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/utils/money.dart';
import 'package:campus_ledger/widgets/bill_tile.dart';
import 'package:campus_ledger/widgets/empty_view.dart';

Bill _bill({
  int type = 1,
  String amount = '35.00',
  String category = '餐饮',
  String merchant = '麦当劳',
  String remark = '',
  String sourceName = '手动记录',
  String date = '2026-09-16',
}) {
  return Bill(
    id: 1,
    type: type,
    typeName: type == 1 ? '支出' : '收入',
    amount: amount,
    category: category,
    billDate: date,
    merchant: merchant,
    remark: remark,
    source: 'MANUAL',
    sourceName: sourceName,
  );
}

void main() {
  testWidgets('账单行展示分类图标、商户、分类来源与两位小数金额', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: _bill())),
    ));

    expect(find.byIcon(Icons.restaurant), findsOneWidget);
    expect(find.text('麦当劳'), findsOneWidget);
    expect(find.text('餐饮 · 手动记录'), findsOneWidget);
    expect(find.text('- ¥35.00'), findsOneWidget);
    // 显示日期时右侧带月份日期
    expect(find.text('09月16日'), findsOneWidget);
  });

  testWidgets('列表已按天分组时不再重复显示日期', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: _bill(), showDate: false)),
    ));

    expect(find.text('09月16日'), findsNothing);
  });

  testWidgets('没有商户时标题退回备注，再退回分类', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: _bill(merchant: '', remark: '便利店'), showDate: false)),
    ));
    expect(find.text('便利店'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: _bill(merchant: '', remark: ''), showDate: false)),
    ));
    // 标题退回分类时同时出现分类图标与分类文本
    expect(find.text('餐饮'), findsWidgets);
  });

  testWidgets('收入显示绿色加号', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillTile(
          bill: _bill(type: 2, amount: '1500.00', category: '生活费', merchant: '家里'),
          showDate: false,
        ),
      ),
    ));

    expect(find.text('+ ¥1500.00'), findsOneWidget);
  });

  testWidgets('不同分类展示对应图标', (tester) async {
    expect(BillTile.categoryIcon('交通'), Icons.directions_bus);
    expect(BillTile.categoryIcon('购物'), Icons.shopping_bag_outlined);
    expect(BillTile.categoryIcon('学习'), Icons.menu_book_outlined);
    expect(BillTile.categoryIcon('不存在的分类'), Icons.more_horiz);
  });

  testWidgets('空状态支持两种文案', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyView(
          icon: Icons.search_off,
          title: '没有找到相关账单',
          subtitle: '换个关键词或调整筛选条件试试',
        ),
      ),
    ));

    expect(find.text('没有找到相关账单'), findsOneWidget);
    expect(find.text('换个关键词或调整筛选条件试试'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: EmptyView(
          icon: Icons.receipt_long_outlined,
          title: '还没有记账记录',
          subtitle: '点击右下角「记一笔」',
        ),
      ),
    ));

    expect(find.text('还没有记账记录'), findsOneWidget);
  });

  test('金额统一保留两位小数', () {
    expect(Money.format('15'), '15.00');
    expect(Money.format('15.0'), '15.00');
    expect(Money.format('0.01'), '0.01');
    expect(Money.format('214.5'), '214.50');
  });

  test('趋势模型能判断涨跌与幅度', () {
    final up = TrendStat.fromJson({
      'month': '2026-09',
      'currentExpense': '120.00',
      'currentIncome': '0.00',
      'previousMonth': '2026-08',
      'previousExpense': '100.00',
      'previousHasData': true,
      'expenseChangePercent': '20.00',
    });
    expect(up.canCompare, isTrue);
    expect(up.isUp, isTrue);
    expect(up.changeText, '20.00');

    final down = TrendStat.fromJson({
      'month': '2026-09',
      'currentExpense': '50.00',
      'currentIncome': '0.00',
      'previousMonth': '2026-08',
      'previousExpense': '200.00',
      'previousHasData': true,
      'expenseChangePercent': '-75.00',
    });
    expect(down.isUp, isFalse);
    expect(down.changeText, '75.00');

    final none = TrendStat.fromJson({
      'month': '2026-09',
      'currentExpense': '50.00',
      'currentIncome': '0.00',
      'previousMonth': '2026-08',
      'previousExpense': '0.00',
      'previousHasData': false,
    });
    expect(none.canCompare, isFalse, reason: '上月没有数据时不展示对比结论');
  });
}
