import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/budget_prediction.dart';
import 'package:campus_ledger/pages/home_page.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/widgets/budget_prediction_card.dart';

http.Response _ok(Object data) => http.Response(
      jsonEncode({'code': 0, 'message': 'success', 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _fail(int status) => http.Response(
      jsonEncode({'code': status, 'message': '服务器开小差了，请稍后重试', 'data': null}),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 构造一条预测条目，字段与后端返回保持一致
Map<String, dynamic> _item({
  int id = 1,
  String category = '',
  String categoryName = '月度总预算',
  bool total = true,
  String budgetAmount = '3000.00',
  String spent = '650.00',
  int spentDays = 5,
  String dailyAverage = '38.24',
  String projected = '1147.20',
  String projectedOver = '0.00',
  String projectedUsageRate = '38.24',
  String? overDate,
  String riskLevel = 'SAFE',
  String message = '本月已过 17 天，已支出 ¥650.00，日均 ¥38.24；按此推算月末约支出 ¥1147.20',
}) {
  return {
    'budgetId': id,
    'category': category,
    'categoryName': categoryName,
    'total': total,
    'budgetAmount': budgetAmount,
    'spent': spent,
    'spentDays': spentDays,
    'elapsedDays': 17,
    'dailyAverage': dailyAverage,
    'projected': projected,
    'projectedOver': projectedOver,
    'projectedUsageRate': projectedUsageRate,
    'overDate': overDate,
    'daysLeft': 13,
    'riskLevel': riskLevel,
    'message': message,
  };
}

Map<String, dynamic> _payload({
  String status = 'OK',
  String message = '本月总预算预计不会超支，本月还剩 13 天',
  List<Map<String, dynamic>>? items,
}) {
  return {
    'month': '2026-09',
    'status': status,
    'message': message,
    'elapsedDays': 17,
    'daysInMonth': 30,
    'daysLeft': 13,
    'items': items ?? [_item()],
  };
}

Widget _card(BudgetPredictionItem item, {bool compact = false}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetPredictionCard(item: item, compact: compact),
        ),
      ),
    );

BudgetPredictionItem _parse(Map<String, dynamic> json) => BudgetPredictionItem.fromJson(json);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'fake-token',
      'user': '{"id":1,"username":"demo","nickname":"小明","email":null,"createdAt":null}',
    });
  });

  tearDown(() {
    ApiClient.testClient = null;
    ApiClient.token = null;
  });

  // ==================== 1~5：风险等级渲染 ====================

  testWidgets('1. OK 正常预测展示预计月底与不会超支', (tester) async {
    await tester.pumpWidget(_card(_parse(_item())));

    expect(find.text('本月预算'), findsOneWidget);
    expect(find.text('安全'), findsOneWidget);
    expect(find.text('预计月底'), findsOneWidget);
    expect(find.text('¥1147.20'), findsOneWidget);
    expect(find.text('已使用 ¥650.00 / ¥3000.00'), findsOneWidget);
    // 不会超支时不显示预计超支行
    expect(find.text('预计超支'), findsNothing);
  });

  testWidgets('2. OVER 严重超支展示超支金额与触顶日期', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(
      id: 17,
      category: '餐饮',
      categoryName: '餐饮',
      total: false,
      budgetAmount: '600.00',
      spent: '500.00',
      dailyAverage: '29.41',
      projected: '882.30',
      projectedOver: '282.30',
      projectedUsageRate: '147.05',
      overDate: '2026-09-21',
      riskLevel: 'OVER',
      message: '餐饮预计超出 ¥282.30',
    ))));

    expect(find.text('餐饮预算'), findsOneWidget);
    expect(find.text('严重超支'), findsOneWidget);
    expect(find.text('¥882.30'), findsOneWidget);
    expect(find.text('¥282.30'), findsOneWidget);
    expect(find.text('预计达到预算'), findsOneWidget);
    expect(find.text('9月21日'), findsOneWidget);
  });

  testWidgets('3. HIGH 显示预计超支', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(
      category: '餐饮',
      categoryName: '餐饮',
      total: false,
      budgetAmount: '1000.00',
      spent: '544.00',
      projected: '1020.00',
      projectedOver: '20.00',
      projectedUsageRate: '102.00',
      riskLevel: 'HIGH',
    ))));

    expect(find.text('预计超支'), findsWidgets);
    expect(find.text('¥20.00'), findsOneWidget);
  });

  testWidgets('4. MEDIUM 显示接近预算', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(
      budgetAmount: '1000.00',
      spent: '480.00',
      projected: '900.00',
      projectedUsageRate: '90.00',
      riskLevel: 'MEDIUM',
    ))));

    expect(find.text('接近预算'), findsOneWidget);
  });

  testWidgets('5. SAFE 显示安全且不显示超支行', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(riskLevel: 'SAFE'))));

    expect(find.text('安全'), findsOneWidget);
    expect(find.text('预计超支'), findsNothing);
  });

  // ==================== 6~8：特殊状态 ====================

  testWidgets('6. INSUFFICIENT_DATA 只显示事实不显示预测结论', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(
      budgetAmount: '100.00',
      spent: '999.00',
      spentDays: 1,
      dailyAverage: '0.00',
      projected: '0.00',
      projectedOver: '0.00',
      projectedUsageRate: '0.00',
      riskLevel: 'INSUFFICIENT_DATA',
      message: '已使用 999.00 / 预算 100.00',
    ))));

    expect(find.text('数据不足'), findsOneWidget);
    expect(find.text('已使用 ¥999.00 / ¥100.00'), findsOneWidget);
    expect(find.text('消费数据不足，记录更多账单后生成预测'), findsOneWidget);
    // 预测结论一律不出现
    expect(find.text('预计月底'), findsNothing);
    expect(find.text('预计超支'), findsNothing);
    expect(find.text('预计使用率'), findsNothing);
    expect(find.text('预计达到预算'), findsNothing);
  });

  testWidgets('6b. 数据不足时主页紧凑卡片同样不显示预测', (tester) async {
    await tester.pumpWidget(_card(
      _parse(_item(
        budgetAmount: '100.00',
        spent: '999.00',
        riskLevel: 'INSUFFICIENT_DATA',
        message: '已使用 999.00 / 预算 100.00',
      )),
      compact: true,
    ));

    expect(find.text('已使用 ¥999.00 / ¥100.00'), findsOneWidget);
    expect(find.text('预计月底'), findsNothing);
  });

  testWidgets('7. NO_BUDGET 显示引导与去设置按钮', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetPredictionSection(
            prediction: BudgetPredictionResponse.fromJson(
                _payload(status: 'NO_BUDGET', message: '本月还没有设置预算，设置后可以预测月末支出', items: [])),
            loading: false,
            onSetupBudget: () => tapped = true,
          ),
        ),
      ),
    ));

    expect(find.text('还没有设置预算'), findsOneWidget);
    expect(find.text('设置预算后，系统可以预测你的消费趋势'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('8. NOT_APPLICABLE 显示仅支持本月', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetPredictionSection(
            prediction: BudgetPredictionResponse.fromJson(
                _payload(status: 'NOT_APPLICABLE', message: '仅支持预测本月支出', items: [])),
            loading: false,
          ),
        ),
      ),
    ));

    expect(find.text('预算预测仅支持当前月份'), findsOneWidget);
    // 不显示预测卡片
    expect(find.byType(BudgetPredictionCard), findsNothing);
  });

  // ==================== 9：网络错误与加载 ====================

  testWidgets('9. 加载中显示提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetPredictionSection(prediction: null, loading: true),
        ),
      ),
    ));

    expect(find.text('正在计算预算预测…'), findsOneWidget);
  });

  testWidgets('9b. 网络错误展示项目统一错误文案', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BudgetPredictionSection(
            prediction: null,
            loading: false,
            errorText: '无法连接服务器，请确认后端已启动',
          ),
        ),
      ),
    ));

    expect(find.text('无法连接服务器，请确认后端已启动'), findsOneWidget);
  });

  testWidgets('9c. 预测接口失败时统计页主体仍然展示', (tester) async {
    ApiClient.testClient = _statisticsClient(predictionFails: true);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1886.50'), findsWidgets);
    expect(find.text('智能预算预测'), findsOneWidget);
    expect(find.text('正在计算预算预测…'), findsNothing);
  });

  // ==================== 10：JSON 解析 ====================

  test('10. JSON 解析完整覆盖所有字段', () {
    final response = BudgetPredictionResponse.fromJson(_payload(items: [
      _item(
        id: 17,
        category: '餐饮',
        categoryName: '餐饮',
        total: false,
        budgetAmount: '600.00',
        spent: '500.00',
        spentDays: 5,
        dailyAverage: '29.41',
        projected: '882.30',
        projectedOver: '282.30',
        projectedUsageRate: '147.05',
        overDate: '2026-09-21',
        riskLevel: 'OVER',
        message: '餐饮预计超出 ¥282.30',
      ),
    ]));

    expect(response.month, '2026-09');
    expect(response.status, 'OK');
    expect(response.isOk, isTrue);
    expect(response.elapsedDays, 17);
    expect(response.daysInMonth, 30);
    expect(response.daysLeft, 13);

    final item = response.items.single;
    expect(item.budgetId, 17);
    expect(item.category, '餐饮');
    expect(item.categoryName, '餐饮');
    expect(item.total, isFalse);
    expect(item.budgetAmount, '600.00');
    expect(item.spent, '500.00');
    expect(item.spentDays, 5);
    expect(item.dailyAverage, '29.41');
    expect(item.projected, '882.30');
    expect(item.projectedOver, '282.30');
    expect(item.projectedUsageRate, '147.05');
    expect(item.overDate, '2026-09-21');
    expect(item.riskLevel, 'OVER');
    expect(item.message, '餐饮预计超出 ¥282.30');
    // 金额保持字符串，不经过 double
    expect(item.budgetAmount, isA<String>());
    expect(item.projected, isA<String>());
  });

  test('10b. 字段缺失时使用安全默认值不抛异常', () {
    final response = BudgetPredictionResponse.fromJson(const {});

    expect(response.status, 'NO_BUDGET');
    expect(response.items, isEmpty);
    expect(response.elapsedDays, 0);
    expect(response.isOk, isFalse);
  });

  // ==================== 11：首页预测卡片 ====================

  testWidgets('11. 首页展示智能预算预测与查看预算分析', (tester) async {
    ApiClient.testClient = _homeClient(items: [
      _item(
        id: 17,
        category: '餐饮',
        categoryName: '餐饮',
        total: false,
        budgetAmount: '600.00',
        spent: '500.00',
        projected: '882.30',
        projectedOver: '282.30',
        projectedUsageRate: '147.05',
        overDate: '2026-09-21',
        riskLevel: 'OVER',
      ),
      _item(),
    ]);

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('智能预算预测'), findsOneWidget);
    expect(find.text('餐饮预算'), findsOneWidget);
    expect(find.text('严重超支'), findsOneWidget);
    expect(find.text('查看预算分析'), findsOneWidget);
  });

  testWidgets('11b. 首页最多展示 2 条预测', (tester) async {
    ApiClient.testClient = _homeClient(items: [
      _item(id: 1, category: '餐饮', categoryName: '餐饮', total: false, riskLevel: 'OVER'),
      _item(id: 2, category: '交通', categoryName: '交通', total: false, riskLevel: 'HIGH'),
      _item(id: 3, category: '购物', categoryName: '购物', total: false, riskLevel: 'MEDIUM'),
    ]);

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(BudgetPredictionCard), findsNWidgets(2));
  });

  testWidgets('11c. 无预算时首页提示去设置', (tester) async {
    ApiClient.testClient = _homeClient(
        items: [], status: 'NO_BUDGET', message: '本月还没有设置预算，设置后可以预测月末支出');

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有设置预算'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });

  // ==================== 12：统计页预测区域 ====================

  testWidgets('12. 统计页展示全部预测条目', (tester) async {
    ApiClient.testClient = _statisticsClient(items: [
      _item(id: 1, category: '餐饮', categoryName: '餐饮', total: false, riskLevel: 'OVER'),
      _item(id: 2, category: '交通', categoryName: '交通', total: false, riskLevel: 'MEDIUM'),
      _item(),
    ]);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.text('智能预算预测'), findsOneWidget);
    expect(find.byType(BudgetPredictionCard), findsNWidgets(3));
  });

  // ==================== 13：进度条不越界 ====================

  testWidgets('13. 使用率超过 100% 时进度条被 clamp 且不抛异常', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(
      budgetAmount: '600.00',
      spent: '500.00',
      projected: '882.30',
      projectedOver: '282.30',
      projectedUsageRate: '147.05',
      riskLevel: 'OVER',
      overDate: '2026-09-21',
    ))));

    expect(tester.takeException(), isNull);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, isNotNull);
    expect(bar.value!, lessThanOrEqualTo(1.0));
    expect(bar.value!, greaterThan(0.0));
    // 百分比文字仍然按真实比例展示
    expect(find.text('83.3%'), findsOneWidget);
    expect(find.text('147.1%'), findsOneWidget);
  });

  testWidgets('13b. 已使用远超预算时进度条取 1.0', (tester) async {
    await tester.pumpWidget(_card(_parse(_item(
      budgetAmount: '100.00',
      spent: '999.00',
      projected: '1200.00',
      projectedOver: '1100.00',
      projectedUsageRate: '1200.00',
      riskLevel: 'OVER',
    ))));

    expect(tester.takeException(), isNull);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 1.0);
  });

  test('13c. 预算为 0 时进度与百分比都不越界', () {
    final item = _parse(_item(budgetAmount: '0.00', spent: '100.00'));

    expect(item.currentProgress, 0.0);
    expect(item.currentProgressText, '0.0');
    expect(item.projectedUsageText, '0.0');
  });

  // ==================== 14：风险排序 ====================

  test('14. 按风险等级降序，同级按预计超支金额降序', () {
    final items = [
      _parse(_item(id: 1, riskLevel: 'SAFE')),
      _parse(_item(id: 2, riskLevel: 'OVER', projectedOver: '100.00')),
      _parse(_item(id: 3, riskLevel: 'MEDIUM')),
      _parse(_item(id: 4, riskLevel: 'OVER', projectedOver: '500.00')),
      _parse(_item(id: 5, riskLevel: 'HIGH')),
      _parse(_item(id: 6, riskLevel: 'LOW')),
    ];

    final sorted = sortBudgetPredictions(items);

    expect(sorted.map((item) => item.budgetId).toList(), [4, 2, 5, 3, 6, 1]);
    expect(sorted.first.riskLevel, 'OVER');
    expect(sorted.last.riskLevel, 'SAFE');
  });

  test('14b. 全部无风险时按预算金额降序', () {
    final items = [
      _parse(_item(id: 1, riskLevel: 'SAFE', budgetAmount: '100.00')),
      _parse(_item(id: 2, riskLevel: 'SAFE', budgetAmount: '3000.00')),
      _parse(_item(id: 3, riskLevel: 'SAFE', budgetAmount: '600.00')),
    ];

    final sorted = sortBudgetPredictions(items);

    expect(sorted.map((item) => item.budgetId).toList(), [2, 3, 1]);
  });

  test('14c. 风险文案与等级一一对应', () {
    expect(_parse(_item(riskLevel: 'SAFE')).riskLabel, '安全');
    expect(_parse(_item(riskLevel: 'LOW')).riskLabel, '留意');
    expect(_parse(_item(riskLevel: 'MEDIUM')).riskLabel, '接近预算');
    expect(_parse(_item(riskLevel: 'HIGH')).riskLabel, '预计超支');
    expect(_parse(_item(riskLevel: 'OVER')).riskLabel, '严重超支');
    expect(_parse(_item(riskLevel: 'INSUFFICIENT_DATA')).riskLabel, '数据不足');
  });

  // ==================== 15~16：月份处理 ====================

  testWidgets('15. 首页固定请求当前月份', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/budgets/predictions')) {
        requested.add(request.url.queryParameters['month'] ?? '');
        return _ok(_payload());
      }
      return _homeStub(request);
    });

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expected =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    expect(requested, [expected]);
  });

  testWidgets('16. 历史月份显示仅支持本月提示', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/budgets/predictions')) {
        requested.add(request.url.queryParameters['month'] ?? '');
        return _ok(_payload(status: 'NOT_APPLICABLE', message: '仅支持预测本月支出', items: []));
      }
      return _statisticsStub(request);
    });

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    // 切到上一个月
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(requested.length, 2, reason: '切换月份要重新请求预测');
    expect(requested.first, isNot(requested.last), reason: '切换月份后请求的月份应当不同');
    expect(find.text('预算预测仅支持当前月份'), findsOneWidget);
    expect(find.byType(BudgetPredictionCard), findsNothing);
  });

  testWidgets('16b. 统计页当前月份正常请求预测', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/budgets/predictions')) {
        requested.add(request.url.queryParameters['month'] ?? '');
        return _ok(_payload());
      }
      return _statisticsStub(request);
    });

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expected =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    expect(requested, [expected]);
    expect(find.byType(BudgetPredictionCard), findsOneWidget);
  });

  // ==================== 17：Service 调用 ====================

  test('17. BudgetService.predictions 复用 ApiClient 并带 month 参数', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final response = await BudgetService.predictions('2026-09');

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/budgets/predictions'));
    expect(captured!.queryParameters['month'], '2026-09');
    expect(response.status, 'OK');
    expect(response.items.single.projected, '1147.20');
  });

  test('17b. 预测接口错误转换为项目统一的中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(500));

    expect(
      () => BudgetService.predictions('2026-09'),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });
}

/// 首页其余接口的桩数据（预测接口单独处理）
Future<http.Response> _homeStub(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/statistics/daily-summary')) {
    return _ok({'date': '2026-09-17', 'income': '0.00', 'expense': '15.00'});
  }
  if (path.endsWith('/statistics/monthly')) {
    return _ok({
      'month': '2026-09',
      'income': '2000.00',
      'expense': '1886.50',
      'balance': '113.50',
    });
  }
  if (path.endsWith('/statistics/trends')) {
    return _ok({
      'month': '2026-09',
      'currentExpense': '1886.50',
      'currentIncome': '2000.00',
      'previousMonth': '2026-08',
      'previousExpense': '1680.00',
      'previousHasData': true,
      'expenseChangePercent': '12.30',
    });
  }
  if (path.endsWith('/insights/monthly')) {
    return _ok({
      'month': '2026-09',
      'expense': '1886.50',
      'income': '2000.00',
      'balance': '113.50',
      'expenseChangePercent': '12.30',
      'topCategory': '餐饮',
      'topCategoryPercent': '42.00',
      'summary': '本月支出 ¥1886.50，餐饮是主要支出类别。',
      'insights': const [],
    });
  }
  if (path.endsWith('/bills')) {
    return _ok({'total': 0, 'page': 1, 'size': 5, 'list': const []});
  }
  return _ok(const {});
}

/// 统计页其余接口的桩数据（预测接口单独处理）
Future<http.Response> _statisticsStub(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/statistics/monthly')) {
    return _ok({
      'month': '2026-09',
      'income': '2000.00',
      'expense': '1886.50',
      'balance': '113.50',
    });
  }
  if (path.endsWith('/insights/monthly')) {
    return _ok({
      'month': '2026-09',
      'expense': '1886.50',
      'income': '2000.00',
      'balance': '113.50',
      'summary': '本月支出 ¥1886.50。',
      'insights': const [],
    });
  }
  if (path.endsWith('/budgets')) {
    return _ok({'month': '2026-09', 'monthExpense': '1886.50', 'total': null, 'categories': const []});
  }
  return _ok(const []);
}

http.Client _homeClient({
  List<Map<String, dynamic>>? items,
  String status = 'OK',
  String message = '本月总预算预计不会超支，本月还剩 13 天',
}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/budgets/predictions')) {
      return _ok(_payload(status: status, message: message, items: items));
    }
    return _homeStub(request);
  });
}

http.Client _statisticsClient({
  List<Map<String, dynamic>>? items,
  bool predictionFails = false,
}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/budgets/predictions')) {
      return predictionFails ? _fail(500) : _ok(_payload(items: items));
    }
    return _statisticsStub(request);
  });
}
