import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/pages/quick_add_page.dart';
import 'package:campus_ledger/widgets/bill_form.dart';

Bill _bill() {
  return Bill(
    id: 1,
    type: 1,
    typeName: '支出',
    amount: '35.00',
    category: '餐饮',
    billDate: '2026-09-16',
    merchant: '麦当劳',
    remark: '午餐',
    source: 'MANUAL',
    sourceName: '手动记录',
  );
}

void main() {
  testWidgets('快速记账页展示金额、分类与保存按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickAddPage()));

    expect(find.text('快速记账'), findsOneWidget);
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
    // 快速模式下商户与备注默认收起
    expect(find.text('更多选项（商户 / 备注）'), findsOneWidget);
    expect(find.text('备注'), findsNothing);
  });

  testWidgets('快速记账页金额为空时提示并阻止提交', (tester) async {
    var submitted = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillForm(
          quickMode: true,
          submitLabel: '保存',
          onSubmit: (_) async => submitted = true,
        ),
      ),
    ));

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('请输入金额'), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('金额非法时提示且不提交', (tester) async {
    var submitted = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillForm(
          quickMode: true,
          submitLabel: '保存',
          onSubmit: (_) async => submitted = true,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextFormField).first, '0');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('金额必须大于 0'), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('校验通过后回调带出表单数据', (tester) async {
    BillFormData? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillForm(
          quickMode: true,
          submitLabel: '保存',
          onSubmit: (data) async => captured = data,
        ),
      ),
    ));

    await tester.enterText(find.byType(TextFormField).first, '12.50');
    await tester.tap(find.widgetWithText(ChoiceChip, '交通'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured!.amount, '12.50');
    expect(captured!.category, '交通');
    expect(captured!.type, 1);
    expect(captured!.billDate, isNotEmpty);
  });

  testWidgets('编辑模式会带出原账单内容且直接展开更多选项', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillForm(
          bill: _bill(),
          submitLabel: '保存',
          onSubmit: (_) async {},
        ),
      ),
    ));

    expect(find.text('35.00'), findsOneWidget);
    expect(find.text('麦当劳'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
  });

  testWidgets('切换收支类型后分类自动跟随', (tester) async {
    BillFormData? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BillForm(
          quickMode: true,
          submitLabel: '保存',
          onSubmit: (data) async => captured = data,
        ),
      ),
    ));

    await tester.tap(find.text('收入'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, '500.00');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(captured!.type, 2);
    // 支出分类不能用在收入上，表单必须把分类切到收入分类
    expect(['生活费', '奖助学金', '兼职收入', '红包', '其他收入'], contains(captured!.category));
  });
}
