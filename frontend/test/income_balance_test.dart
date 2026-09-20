import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/income_balance.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/widgets/balance_card.dart';
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

List<Map<String, dynamic>> _items([int size = 2]) {
  final all = [
    {'category': '生活费', 'amount': '2400.00', 'count': 1, 'percentage': '80.00'},
    {'category': '兼职收入', 'amount': '600.00', 'count': 2, 'percentage': '20.00'},
    {'category': '奖助学金', 'amount': '300.00', 'count': 1, 'percentage': '10.00'},
    {'category': '红包', 'amount': '200.00', 'count': 1, 'percentage': '6.67'},
    {'category': '其他收入', 'amount': '100.00', 'count': 1, 'percentage': '3.33'},
    {'category': '第六类', 'amount': '50.00', 'count': 1, 'percentage': '1.67'},
  ];
  return all.take(size).toList();
}

Map<String, dynamic> _payload({
  String month = '2026-09',
  String status = 'OK',
  String message = '已分析 2026-09 的收支结余：收入 3000.00，支出 1000.00',
  Object? incomeAmount = '3000.00',
  Object? expenseAmount = '1000.00',
  Object? balance = '2000.00',
  Object? balanceRate = '66.67',
  Object? incomeCount = 3,
  Object? incomeItems,
  Object? previousBalance = '1000.00',
  Object? balanceChange = '1000.00',
  Object? hasPreviousData = true,
  String summary = '本月结余 ¥2000.00（结余率 66.67%），比上月多存 ¥1000.00',
}) {
  return {
    'month': month,
    'status': status,
    'message': message,
    'incomeAmount': incomeAmount,
    'expenseAmount': expenseAmount,
    'balance': balance,
    'balanceRate': balanceRate,
    'incomeCount': incomeCount,
    'incomeItems': incomeItems ?? _items(),
    'previousBalance': previousBalance,
    'balanceChange': balanceChange,
    'hasPreviousData': hasPreviousData,
    'summary': summary,
  };
}

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

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

  // ==================== 模型解析 ====================

  test('完整 JSON 解析出全部字段', () {
    final response = IncomeBalanceResponse.fromJson(_payload());

    expect(response.month, '2026-09');
    expect(response.status, 'OK');
    expect(response.incomeAmount, '3000.00');
    expect(response.expenseAmount, '1000.00');
    expect(response.balance, '2000.00');
    expect(response.balanceRate, '66.67');
    expect(response.incomeCount, 3);
    expect(response.previousBalance, '1000.00');
    expect(response.balanceChange, '1000.00');
    expect(response.hasPreviousData, isTrue);
    expect(response.incomeItems.length, 2);
    expect(response.incomeItems.first.category, '生活费');
    expect(response.incomeItems.first.amount, '2400.00');
    expect(response.incomeItems.first.count, 1);
    expect(response.incomeItems.first.percentage, '80.00');
  });

  test('incomeItems 缺失时按空列表处理', () {
    final json = _payload()..remove('incomeItems');

    expect(IncomeBalanceResponse.fromJson(json).incomeItems, isEmpty);
  });

  test('incomeItems 为 null 时按空列表处理', () {
    final json = _payload();
    json['incomeItems'] = null;

    expect(IncomeBalanceResponse.fromJson(json).incomeItems, isEmpty);
  });

  test('incomeItems 含非对象元素时被忽略', () {
    final json = _payload();
    json['incomeItems'] = [
      {'category': '生活费', 'amount': '2400.00', 'count': 1, 'percentage': '80.00'},
      'not-a-map',
      42,
    ];

    final response = IncomeBalanceResponse.fromJson(json);

    expect(response.incomeItems.length, 1);
    expect(response.incomeItems.first.category, '生活费');
  });

  test('incomeItems 为空数组时解析为空列表', () {
    expect(IncomeBalanceResponse.fromJson(_payload(incomeItems: const [])).incomeItems, isEmpty);
  });

  test('缺少字段时使用安全默认值', () {
    final response = IncomeBalanceResponse.fromJson(const {});

    expect(response.month, '');
    expect(response.status, '');
    expect(response.incomeAmount, '0');
    expect(response.expenseAmount, '0');
    expect(response.balance, '0');
    expect(response.balanceRate, '0.00');
    expect(response.incomeCount, 0);
    expect(response.previousBalance, '0');
    expect(response.balanceChange, isNull);
    expect(response.hasPreviousData, isFalse);
    expect(response.summary, '');
    expect(response.incomeItems, isEmpty);
  });

  test('未知字段被忽略', () {
    final json = _payload();
    json['futureField'] = 'whatever';

    expect(IncomeBalanceResponse.fromJson(json).status, 'OK');
  });

  test('字段类型不符时不崩溃', () {
    final response = IncomeBalanceResponse.fromJson(_payload(
      incomeAmount: 3000,
      expenseAmount: 1000.5,
      incomeCount: 'abc',
      balanceChange: -500.25,
      hasPreviousData: 'yes',
      incomeItems: [
        {'category': 123, 'amount': 2400, 'count': '2', 'percentage': 80},
      ],
    ));

    expect(response.incomeAmount, '3000');
    expect(response.expenseAmount, '1000.5');
    expect(response.incomeCount, 0);
    expect(response.balanceChange, '-500.25');
    expect(response.hasPreviousData, isFalse);
    expect(response.incomeItems.first.category, '123');
    expect(response.incomeItems.first.amountText, '¥2400.00');
    expect(response.incomeItems.first.count, 2);
  });

  test('状态 getter 正确区分四种状态', () {
    expect(IncomeBalanceResponse.fromJson(_payload()).isOk, isTrue);
    expect(IncomeBalanceResponse.fromJson(_payload(status: 'NO_INCOME_DATA')).isNoIncomeData, isTrue);
    expect(IncomeBalanceResponse.fromJson(_payload(status: 'NO_DATA')).isNoData, isTrue);
    expect(IncomeBalanceResponse.fromJson(_payload(status: 'NOT_APPLICABLE')).isNotApplicable, isTrue);
  });

  test('收入与支出展示文案换算正确', () {
    final response = IncomeBalanceResponse.fromJson(_payload());

    expect(response.incomeText, '¥3000.00');
    expect(response.expenseText, '¥1000.00');
  });

  test('结余为正时展示正常金额', () {
    final response = IncomeBalanceResponse.fromJson(_payload());

    expect(response.balanceText, '¥2000.00');
    expect(response.isOverSpent, isFalse);
  });

  test('结余为负时展示负号金额并标记超支', () {
    final response = IncomeBalanceResponse.fromJson(
        _payload(balance: '-500.00', balanceRate: '-50.00'));

    expect(response.balanceText, '-¥500.00');
    expect(response.isOverSpent, isTrue);
  });

  test('结余率文案去掉多余小数零', () {
    expect(IncomeBalanceResponse.fromJson(_payload(balanceRate: '66.67')).balanceRateText, '结余率 66.67%');
    expect(IncomeBalanceResponse.fromJson(_payload(balanceRate: '50.00')).balanceRateText, '结余率 50%');
  });

  test('与上月的对比文案正确', () {
    expect(IncomeBalanceResponse.fromJson(_payload()).comparisonText, '比上月多存 ¥1000.00');
    expect(
        IncomeBalanceResponse.fromJson(_payload(balanceChange: '-1800.00')).comparisonText,
        '比上月少存 ¥1800.00');
    expect(IncomeBalanceResponse.fromJson(_payload(balanceChange: '0.00')).comparisonText, '与上月持平');
  });

  test('没有上月数据时不生成对比文案', () {
    expect(
        IncomeBalanceResponse.fromJson(_payload(hasPreviousData: false)).comparisonText,
        isNull);
    expect(
        IncomeBalanceResponse.fromJson(_payload(balanceChange: null)).comparisonText,
        isNull);
  });

  test('收入项展示文案与条形映射正确', () {
    final item = IncomeBalanceResponse.fromJson(_payload()).incomeItems.first;

    expect(item.amountText, '¥2400.00');
    expect(item.countText, '1 笔');
    expect(item.percentageText, '80%');
    expect(item.ratio, closeTo(0.8, 0.0001));
  });

  test('百分比去零工具正确处理', () {
    expect(trimPercent('80.00'), '80');
    expect(trimPercent('6.67'), '6.67');
    expect(trimPercent('12.50'), '12.5');
    expect(trimPercent(''), '0');
  });

  // ==================== 区块渲染 ====================

  testWidgets('OK 渲染标题、副标题与总览', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('收支结余分析'), findsOneWidget);
    expect(find.text('看看这个月存下了多少'), findsOneWidget);
    expect(find.text('本月收入'), findsOneWidget);
    expect(find.text('¥3000.00'), findsOneWidget);
    expect(find.text('本月支出'), findsOneWidget);
    expect(find.text('¥1000.00'), findsOneWidget);
    expect(find.text('本月结余'), findsOneWidget);
    expect(find.text('¥2000.00'), findsOneWidget);
  });

  testWidgets('OK 渲染结余率与上月对比', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('结余率 66.67%'), findsOneWidget);
    expect(find.text('比上月多存 ¥1000.00'), findsOneWidget);
  });

  testWidgets('OK 渲染收入结构', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('收入结构'), findsOneWidget);
    expect(find.text('生活费'), findsOneWidget);
    expect(find.text('¥2400.00'), findsOneWidget);
    expect(find.text('1 笔 · 80%'), findsOneWidget);
    expect(find.text('兼职收入'), findsOneWidget);
  });

  testWidgets('收入结构为空时不渲染该区域', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload(incomeItems: const [], summary: '')),
      loading: false,
    )));

    expect(find.text('收入结构'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('展示后端一句话总结', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.textContaining('本月结余 ¥2000.00'), findsWidgets);
  });

  testWidgets('超支时结余用暖红展示', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload(
        balance: '-500.00',
        balanceRate: '-50.00',
        summary: '本月支出超过收入 ¥500.00（结余率 -50.00%）',
      )),
      loading: false,
    )));

    expect(find.text('-¥500.00'), findsOneWidget);
    expect(find.textContaining('支出超过收入'), findsOneWidget);
  });

  testWidgets('loading 显示分析提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BalanceSection(data: null, loading: true)),
    ));

    expect(find.text('正在分析收支结余…'), findsOneWidget);
  });

  testWidgets('error 显示中文提示与重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(BalanceSection(
      data: null,
      loading: false,
      errorText: '无法连接服务器，请确认后端已启动',
      onRetry: () => retried = true,
    )));

    expect(find.text('无法连接服务器，请确认后端已启动'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(retried, isTrue);
  });

  testWidgets('data 为空时不渲染卡片', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: BalanceSection(data: null, loading: false)),
    ));

    expect(find.byType(BalanceCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NO_DATA 显示本月暂无收支记录', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(
          _payload(status: 'NO_DATA', incomeItems: const [], summary: '')),
      loading: false,
    )));

    expect(find.text('本月暂无收支记录'), findsOneWidget);
    expect(find.byType(BalanceCard), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('NO_INCOME_DATA 显示没有收入记录与支出事实', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload(
        status: 'NO_INCOME_DATA',
        incomeAmount: '0.00',
        expenseAmount: '900.00',
        balance: '-900.00',
        balanceRate: '0.00',
        incomeCount: 0,
        incomeItems: const [],
        summary: '',
      )),
      loading: false,
    )));

    expect(find.text('本月没有收入记录'), findsOneWidget);
    expect(find.text('补记收入后即可计算结余率'), findsOneWidget);
    expect(find.text('本月已支出 ¥900.00'), findsOneWidget);
    expect(find.byType(BalanceCard), findsNothing);
  });

  testWidgets('NOT_APPLICABLE 显示不支持分析且不用错误图标', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(
          _payload(status: 'NOT_APPLICABLE', incomeItems: const [], summary: '')),
      loading: false,
    )));

    expect(find.text('该月份不支持收支结余分析'), findsOneWidget);
    expect(find.text('统计分析仅针对当前月份'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('未知状态回退到后端说明', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(
          _payload(status: 'SOMETHING_NEW', message: '后端新增状态的说明', incomeItems: const [])),
      loading: false,
    )));

    expect(find.text('后端新增状态的说明'), findsOneWidget);
  });

  testWidgets('长文案不溢出', (tester) async {
    await tester.pumpWidget(_host(BalanceSection(
      data: IncomeBalanceResponse.fromJson(_payload(
        summary: '这是一段很长的收支结余总结，用来验证卡片在极端文案下不会溢出布局边界，也不应抛异常',
        incomeItems: [
          {'category': '某某某某某某某某某某超级长的收入分类名称', 'amount': '99999999.99', 'count': 999, 'percentage': '100.00'},
        ],
      )),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
  });

  // ==================== 统计页接入 ====================

  testWidgets('统计页展示收支结余区块', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.text('收支结余分析'), findsOneWidget);
    expect(find.text('¥3000.00'), findsWidgets);
  });

  testWidgets('收支结余区块紧跟本月概览且位于预算预测之前', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final children = (listView.childrenDelegate as SliverChildListDelegate).children;

    final balance = children.indexWhere((widget) => widget is BalanceSection);
    final prediction = children.indexWhere((widget) => widget is BudgetPredictionSection);

    expect(balance, greaterThanOrEqualTo(0));
    expect(balance, lessThan(prediction), reason: '收支结余应在预算预测之前');
    expect(balance, lessThanOrEqualTo(2), reason: '应紧跟本月概览卡片');
  });

  testWidgets('收支结余接口失败时区块隐藏且其他区块正常', (tester) async {
    ApiClient.testClient = _pageClient(balanceFails: true);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1886.50'), findsWidgets);
    expect(find.text('收支结余分析'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换月份会重新请求收支结余接口', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      if (request.url.path.endsWith('/insights/balance')) {
        requested.add(request.url.queryParameters['month'] ?? '');
        return _ok(_payload(month: request.url.queryParameters['month'] ?? ''));
      }
      return _pageStub(request);
    });

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();
    expect(requested.length, 1);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(requested.length, 2);
    expect(requested.first, isNot(requested.last));
  });

  // ==================== Service ====================

  test('InsightService.balance 复用 ApiClient 且只带 month 参数', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final response = await InsightService.balance('2026-09');

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/insights/balance'));
    expect(captured!.queryParameters['month'], '2026-09');
    expect(captured!.queryParameters.containsKey('userId'), isFalse);
    expect(response.incomeAmount, '3000.00');
  });

  test('收支结余接口错误转换为项目统一中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(400));

    expect(
      () => InsightService.balance('2026-9'),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });

  test('非 Map 响应抛出统一业务异常', () async {
    ApiClient.testClient = MockClient((request) async => _ok(const []));

    expect(
      () => InsightService.balance('2026-09'),
      throwsA(predicate((error) => error.toString().contains('数据格式不正确'))),
    );
  });
}

// ==================== 统计页接口桩 ====================

http.Client _pageClient({bool balanceFails = false}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/insights/balance')) {
      return balanceFails
          ? _fail(500)
          : _ok(_payload(month: request.url.queryParameters['month'] ?? '2026-09'));
    }
    return _pageStub(request);
  });
}

Future<http.Response> _pageStub(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/statistics/monthly')) {
    return _ok({
      'month': '2026-09',
      'income': '2000.00',
      'expense': '1886.50',
      'balance': '113.50',
    });
  }
  if (path.endsWith('/statistics/category')) {
    return _ok([
      {'category': '餐饮', 'amount': '792.00', 'percentage': 42.0},
    ]);
  }
  if (path.endsWith('/statistics/source')) {
    return _ok([
      {'source': 'WECHAT', 'sourceName': '微信', 'amount': '1000.00', 'percentage': 53.0},
    ]);
  }
  if (path.endsWith('/statistics/daily')) {
    return _ok([
      {'date': '2026-09-17', 'income': '0.00', 'expense': '15.00'},
    ]);
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
  if (path.endsWith('/insights/recurring')) {
    return _ok({
      'windowDays': 180,
      'status': 'NO_RECURRING',
      'message': '最近 180 天没有发现明显的周期性支出',
      'items': const [],
    });
  }
  if (path.endsWith('/insights/anomalies')) {
    return _ok({
      'month': '2026-09',
      'status': 'NO_ANOMALY',
      'message': '本月消费节奏正常',
      'baselineMonths': const ['2026-06', '2026-07', '2026-08'],
      'items': const [],
    });
  }
  if (path.endsWith('/insights/forecast')) {
    return _ok({
      'month': '2026-09',
      'targetMonth': '2026-10',
      'status': 'NO_DATA',
      'message': '还没有支出记录，暂时无法预估下月支出',
      'confidence': 'NONE',
      'confidenceLabel': '',
      'confidenceReason': '',
      'predictedAmount': '0.00',
      'previousMonthAmount': '0.00',
      'predictedDifference': null,
      'predictedChangePercent': null,
      'currentMonthAmount': '0.00',
      'elapsedDays': 18,
      'sampleMonths': const [],
    });
  }
  if (path.endsWith('/insights/rhythm')) {
    return _ok({
      'month': '2026-09',
      'status': 'NO_DATA',
      'message': '当月还没有支出记录',
      'totalAmount': '0.00',
      'coveredDays': 0,
      'coveredRate': '0.00',
      'peakWeekday': '',
      'peakPeriod': '',
      'concentration': '0.00',
      'summary': '',
      'weekdayItems': const [],
      'periodItems': const [],
    });
  }
  if (path.endsWith('/insights/merchants')) {
    return _ok({
      'month': '2026-09',
      'status': 'NO_DATA',
      'message': '当月还没有支出记录',
      'totalAmount': '0.00',
      'totalCount': 0,
      'averageAmount': '0.00',
      'merchantCount': 0,
      'merchantCoverage': '0.00',
      'unknownMerchantAmount': '0.00',
      'unknownMerchantRate': '0.00',
      'top3Concentration': '0.00',
      'summary': '',
      'topMerchants': const [],
    });
  }
  if (path.endsWith('/budgets/predictions')) {
    return _ok({
      'month': '2026-09',
      'status': 'NO_BUDGET',
      'message': '本月还没有设置预算，设置后可以预测月末支出',
      'elapsedDays': 17,
      'daysInMonth': 30,
      'daysLeft': 13,
      'items': const [],
    });
  }
  if (path.endsWith('/budgets')) {
    return _ok({
      'month': '2026-09',
      'monthExpense': '1886.50',
      'total': null,
      'categories': const [],
    });
  }
  return _ok(const {});
}
