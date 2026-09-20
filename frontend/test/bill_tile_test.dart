import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/widgets/bill_tile.dart';

Bill buildBill({required int type, required String amount, required String source, required String sourceName}) {
  return Bill(
    id: 1,
    type: type,
    typeName: type == 1 ? '支出' : type == 2 ? '收入' : '不计收支',
    amount: amount,
    category: type == 2 ? '生活费' : '餐饮',
    billDate: '2026-09-15',
    merchant: '星巴克',
    remark: '',
    source: source,
    sourceName: sourceName,
  );
}

void main() {
  testWidgets('支出显示减号与来源', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: buildBill(type: 1, amount: '31.00', source: 'WECHAT', sourceName: '微信'))),
    ));

    expect(find.text('- ¥31.00'), findsOneWidget);
    expect(find.textContaining('餐饮 · 微信'), findsOneWidget);
    expect(find.text('09月15日'), findsOneWidget);
  });

  testWidgets('收入显示加号', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: buildBill(type: 2, amount: '500.00', source: 'MANUAL', sourceName: '手动记录'))),
    ));

    expect(find.text('+ ¥500.00'), findsOneWidget);
    expect(find.textContaining('生活费 · 手动记录'), findsOneWidget);
  });

  testWidgets('不计收支不带符号', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BillTile(bill: buildBill(type: 3, amount: '200.00', source: 'ALIPAY', sourceName: '支付宝'))),
    ));

    expect(find.text('¥200.00'), findsOneWidget);
  });
}
