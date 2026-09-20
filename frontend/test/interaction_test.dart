import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/pages/export_page.dart';
import 'package:campus_ledger/services/export_service.dart';

/// 左滑删除的交互契约：向左滑出删除背景并触发确认流程，
/// 用户取消时不删除、确认时才交给外层处理。
/// 这里用一个与 BillListPage 中相同的 Dismissible 配置来锁定行为，避免依赖后端。
class _SwipeDeleteHost extends StatelessWidget {
  const _SwipeDeleteHost({required this.onConfirm});

  final Future<bool> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          Dismissible(
            key: const ValueKey('bill-1'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.red,
              child: const Text('删除', style: TextStyle(color: Colors.white)),
            ),
            confirmDismiss: (_) => onConfirm(),
            child: const ListTile(title: Text('麦当劳'), subtitle: Text('餐饮 · 手动记录')),
          ),
        ],
      ),
    );
  }
}

void main() {
  /// 左滑到足够远的位置才会触发确认，按条目宽度算比例，避免写死像素
  Future<void> swipeLeft(WidgetTester tester, Finder target) async {
    final width = tester.getSize(find.byType(ListView)).width;
    await tester.drag(target, Offset(-width * 0.9, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('左滑出现删除按钮', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _SwipeDeleteHost(onConfirm: () async => false),
    ));

    expect(find.text('删除'), findsNothing);
    final width = tester.getSize(find.byType(ListView)).width;
    await tester.drag(find.text('麦当劳'), Offset(-width * 0.3, 0));
    await tester.pump();

    expect(find.text('删除'), findsOneWidget);
    // 手势中断后条目回到原位，不产生副作用
    await tester.pumpAndSettle();
  });

  testWidgets('取消确认时账单保留', (tester) async {
    var asked = false;
    await tester.pumpWidget(MaterialApp(
      home: _SwipeDeleteHost(onConfirm: () async {
        asked = true;
        return false;
      }),
    ));

    await swipeLeft(tester, find.text('麦当劳'));

    expect(asked, isTrue, reason: '左滑必须经过确认流程');
    expect(find.text('麦当劳'), findsOneWidget, reason: '取消后不能删除');
  });

  testWidgets('确认后条目被移除', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: _SwipeDeleteHost(onConfirm: () async => true),
    ));

    await swipeLeft(tester, find.text('麦当劳'));

    expect(find.text('麦当劳'), findsNothing);
  });

  testWidgets('导出页展示三种格式与上限说明', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExportPage()));

    expect(find.text('数据导出'), findsOneWidget);
    expect(find.text('CSV 表格（.csv）'), findsOneWidget);
    expect(find.text('Excel 表格（.xlsx）'), findsOneWidget);
    expect(find.text('JSON 备份（.json）'), findsOneWidget);
    expect(find.textContaining('单次最多导出 10000 条'), findsOneWidget);
    expect(find.textContaining('只导出当前登录账号自己的账单'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '导出账单'), findsOneWidget);
  });

  test('导出格式的文案与 MIME 类型对应正确', () {
    expect(ExportService.formats, ['csv', 'xlsx', 'json']);
    expect(ExportService.labelOf('csv'), contains('CSV'));
    expect(ExportService.mimeOf('csv'), startsWith('text/csv'));
    expect(ExportService.mimeOf('json'), 'application/json');
    expect(ExportService.mimeOf('xlsx'), contains('spreadsheetml'));
  });
}
