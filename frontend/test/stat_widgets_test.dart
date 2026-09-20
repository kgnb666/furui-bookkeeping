import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/models/budget.dart';
import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/widgets/stat_widgets.dart';

BudgetItem budgetItem({
  required String amount,
  required String used,
  required String remaining,
  required double usageRate,
  required String status,
  required String statusName,
}) {
  return BudgetItem(
    id: 1,
    category: '',
    categoryName: '月度总预算',
    amount: amount,
    used: used,
    remaining: remaining,
    usageRate: usageRate,
    status: status,
    statusName: statusName,
  );
}

void main() {
  testWidgets('统计概览卡片显示收入支出结余', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatOverviewCard(income: '500.00', expense: '214.00', balance: '286.00'),
      ),
    ));

    expect(find.text('本月收入'), findsOneWidget);
    expect(find.text('¥500.00'), findsOneWidget);
    expect(find.text('本月支出'), findsOneWidget);
    expect(find.text('¥214.00'), findsOneWidget);
    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('¥286.00'), findsOneWidget);
  });

  testWidgets('分类统计行显示金额与占比', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CategoryStatTile(
          stat: CategoryStat(category: '餐饮', amount: '86.50', percentage: 40.42),
        ),
      ),
    ));

    expect(find.text('餐饮'), findsOneWidget);
    expect(find.text('¥86.50'), findsOneWidget);
    expect(find.text('40.42%'), findsOneWidget);
  });

  testWidgets('预算正常时显示剩余金额', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BudgetProgressCard(
          item: budgetItem(
            amount: '2000.00',
            used: '856.50',
            remaining: '1143.50',
            usageRate: 42.83,
            status: 'NORMAL',
            statusName: '正常',
          ),
        ),
      ),
    ));

    expect(find.text('月度总预算'), findsOneWidget);
    expect(find.text('¥2000.00'), findsOneWidget);
    expect(find.text('已使用 ¥856.50'), findsOneWidget);
    expect(find.text('剩余 ¥1143.50'), findsOneWidget);
    expect(find.text('使用率 42.83%'), findsOneWidget);
  });

  testWidgets('预算超支时显示已超支金额', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BudgetProgressCard(
          item: budgetItem(
            amount: '200.00',
            used: '256.50',
            remaining: '-56.50',
            usageRate: 128.25,
            status: 'OVER',
            statusName: '已超支',
          ),
        ),
      ),
    ));

    expect(find.text('已超支 ¥56.50'), findsOneWidget);
    expect(find.textContaining('剩余'), findsNothing);
  });

  testWidgets('预算刚好用完时显示已达预算', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BudgetProgressCard(
          item: budgetItem(
            amount: '100.00',
            used: '100.00',
            remaining: '0.00',
            usageRate: 100,
            status: 'REACHED',
            statusName: '已达预算',
          ),
        ),
      ),
    ));

    expect(find.text('已达到预算'), findsOneWidget);
  });
}
