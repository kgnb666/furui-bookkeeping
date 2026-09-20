import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/widgets/month_selector.dart';

void main() {
  testWidgets('显示当前月份并可以前后切换', (tester) async {
    final months = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MonthSelector(month: '2026-09', onChanged: months.add),
      ),
    ));

    expect(find.text('2026年9月'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.tap(find.byIcon(Icons.chevron_left));

    expect(months, ['2026-10', '2026-08']);
  });

  testWidgets('跨年时月份计算正确', (tester) async {
    final months = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MonthSelector(month: '2026-01', onChanged: months.add),
      ),
    ));

    await tester.tap(find.byIcon(Icons.chevron_left));

    expect(months, ['2025-12']);
  });
}
