import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/models/import_preview.dart';
import 'package:campus_ledger/pages/import_preview_page.dart';

ImportPreviewItem item({
  required int rowIndex,
  required String merchant,
  required String amount,
  required int type,
  required String category,
  bool duplicate = false,
  bool importable = true,
  bool defaultSelected = true,
  String? failReason,
  String? duplicateReason,
}) {
  final preview = ImportPreviewItem(
    rowIndex: rowIndex,
    billDate: '2026-08-03',
    sourceTradeTime: '2026-08-03 12:15:26',
    merchant: merchant,
    remark: '',
    amount: amount,
    type: type,
    typeName: type == 3 ? '不计收支' : '支出',
    category: category,
    categoryFrom: 'KEYWORD',
    sourceTradeId: '4200$rowIndex',
    duplicate: duplicate,
    duplicateReason: duplicateReason,
    importable: importable,
    defaultSelected: defaultSelected,
    failReason: failReason,
  );
  preview.initSelection();
  return preview;
}

void main() {
  testWidgets('预览页展示四类数量', (tester) async {
    final preview = ImportPreview(
      source: 'WECHAT',
      sourceName: '微信',
      fileName: 'wechat.csv',
      totalCount: 13,
      newCount: 11,
      duplicateCount: 1,
      neutralCount: 1,
      failedCount: 0,
      items: [
        item(rowIndex: 1, merchant: '星巴克', amount: '31.00', type: 1, category: '餐饮'),
        item(
          rowIndex: 2,
          merchant: '星巴克',
          amount: '31.00',
          type: 1,
          category: '餐饮',
          duplicate: true,
          defaultSelected: false,
          duplicateReason: '与已有记录重复',
        ),
        item(
          rowIndex: 3,
          merchant: '零钱提现',
          amount: '500.00',
          type: 3,
          category: '提现',
          defaultSelected: false,
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: ImportPreviewPage(preview: preview)));

    expect(find.text('本次发现 13 条交易'), findsOneWidget);
    expect(find.text('新增 11'), findsOneWidget);
    expect(find.text('重复 1'), findsOneWidget);
    expect(find.text('不计收支 1'), findsOneWidget);
    expect(find.text('解析失败 0'), findsOneWidget);
    // 默认只勾选新增那条
    expect(find.text('已选择 1 条'), findsOneWidget);
    expect(find.text('与已有记录重复'), findsOneWidget);
  });

  testWidgets('解析失败的行不能勾选', (tester) async {
    final preview = ImportPreview(
      source: 'WECHAT',
      sourceName: '微信',
      fileName: 'wechat.csv',
      totalCount: 1,
      newCount: 0,
      duplicateCount: 0,
      neutralCount: 0,
      failedCount: 1,
      items: [
        item(
          rowIndex: 1,
          merchant: '坏数据',
          amount: '',
          type: 1,
          category: '其他',
          importable: false,
          defaultSelected: false,
          failReason: '金额无法识别: --',
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp(home: ImportPreviewPage(preview: preview)));

    final checkbox = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(checkbox.onChanged, isNull);
    expect(find.text('金额无法识别: --'), findsOneWidget);
    expect(find.text('已选择 0 条'), findsOneWidget);
  });
}
