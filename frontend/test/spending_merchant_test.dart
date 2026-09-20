import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/spending_merchant.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/widgets/merchant_card.dart';
import 'package:campus_ledger/widgets/rhythm_card.dart';

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
    {'merchantName': '食堂', 'amount': '700.00', 'count': 2, 'percentage': '70.00'},
    {'merchantName': '超市', 'amount': '300.00', 'count': 2, 'percentage': '30.00'},
    {'merchantName': '奶茶店', 'amount': '200.00', 'count': 1, 'percentage': '20.00'},
    {'merchantName': '书店', 'amount': '150.00', 'count': 1, 'percentage': '15.00'},
    {'merchantName': '水果摊', 'amount': '100.00', 'count': 1, 'percentage': '10.00'},
    {'merchantName': '第六家', 'amount': '50.00', 'count': 1, 'percentage': '5.00'},
  ];
  return all.take(size).toList();
}

Map<String, dynamic> _payload({
  String month = '2026-09',
  String status = 'OK',
  String message = '已分析 2026-09 的消费对象：2 个交易对象，共 4 笔支出',
  Object? totalAmount = '1000.00',
  Object? totalCount = 4,
  Object? averageAmount = '250.00',
  Object? merchantCount = 2,
  Object? merchantCoverage = '100.00',
  Object? unknownMerchantAmount = '0.00',
  Object? unknownMerchantRate = '0.00',
  Object? top3Concentration = '100.00',
  String summary = '支出主要集中在 2 个消费对象，合计占 100.00%',
  Object? topMerchants,
}) {
  return {
    'month': month,
    'status': status,
    'message': message,
    'totalAmount': totalAmount,
    'totalCount': totalCount,
    'averageAmount': averageAmount,
    'merchantCount': merchantCount,
    'merchantCoverage': merchantCoverage,
    'unknownMerchantAmount': unknownMerchantAmount,
    'unknownMerchantRate': unknownMerchantRate,
    'top3Concentration': top3Concentration,
    'summary': summary,
    'topMerchants': topMerchants ?? _items(),
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
    final response = SpendingMerchantResponse.fromJson(_payload());

    expect(response.month, '2026-09');
    expect(response.status, 'OK');
    expect(response.totalAmount, '1000.00');
    expect(response.totalCount, 4);
    expect(response.averageAmount, '250.00');
    expect(response.merchantCount, 2);
    expect(response.merchantCoverage, '100.00');
    expect(response.unknownMerchantAmount, '0.00');
    expect(response.unknownMerchantRate, '0.00');
    expect(response.top3Concentration, '100.00');
    expect(response.summary, contains('支出主要集中在'));
    expect(response.topMerchants.length, 2);
    expect(response.topMerchants.first.merchantName, '食堂');
    expect(response.topMerchants.first.amount, '700.00');
    expect(response.topMerchants.first.count, 2);
    expect(response.topMerchants.first.percentage, '70.00');
  });

  test('topMerchants 缺失时按空列表处理', () {
    final json = _payload()..remove('topMerchants');

    expect(SpendingMerchantResponse.fromJson(json).topMerchants, isEmpty);
  });

  test('topMerchants 为 null 时按空列表处理', () {
    final json = _payload();
    json['topMerchants'] = null;

    expect(SpendingMerchantResponse.fromJson(json).topMerchants, isEmpty);
  });

  test('topMerchants 含非对象元素时被忽略', () {
    final json = _payload();
    json['topMerchants'] = [
      {'merchantName': '食堂', 'amount': '700.00', 'count': 2, 'percentage': '70.00'},
      'not-a-map',
      42,
    ];

    final response = SpendingMerchantResponse.fromJson(json);

    expect(response.topMerchants.length, 1);
    expect(response.topMerchants.first.merchantName, '食堂');
  });

  test('topMerchants 为空数组时解析为空列表', () {
    expect(SpendingMerchantResponse.fromJson(_payload(topMerchants: const [])).topMerchants, isEmpty);
  });

  test('缺少字段时使用安全默认值', () {
    final response = SpendingMerchantResponse.fromJson(const {});

    expect(response.month, '');
    expect(response.status, '');
    expect(response.totalAmount, '0');
    expect(response.totalCount, 0);
    expect(response.averageAmount, '0');
    expect(response.merchantCount, 0);
    expect(response.merchantCoverage, '0.00');
    expect(response.unknownMerchantAmount, '0');
    expect(response.top3Concentration, '0.00');
    expect(response.summary, '');
    expect(response.topMerchants, isEmpty);
  });

  test('未知字段被忽略', () {
    final json = _payload();
    json['futureField'] = 'whatever';
    json['nested'] = {'a': 1};

    final response = SpendingMerchantResponse.fromJson(json);

    expect(response.status, 'OK');
    expect(response.totalAmount, '1000.00');
  });

  test('字段类型不符时不崩溃', () {
    final response = SpendingMerchantResponse.fromJson(_payload(
      totalAmount: 1000,
      totalCount: 'abc',
      averageAmount: 250.5,
      merchantCount: '2',
      merchantCoverage: 100.0,
      unknownMerchantRate: null,
      topMerchants: [
        {'merchantName': 123, 'amount': 700, 'count': '2', 'percentage': 70},
      ],
    ));

    expect(response.totalAmount, '1000');
    expect(response.totalCount, 0);
    expect(response.averageAmount, '250.5');
    expect(response.merchantCount, 2);
    expect(response.merchantCoverage, '100.0');
    expect(response.unknownMerchantRate, '0.00');
    expect(response.topMerchants.first.merchantName, '123');
    expect(response.topMerchants.first.amountText, '¥700.00');
    expect(response.topMerchants.first.count, 2);
  });

  test('状态 getter 正确区分四种状态', () {
    expect(SpendingMerchantResponse.fromJson(_payload()).isOk, isTrue);
    expect(SpendingMerchantResponse.fromJson(_payload(status: 'INSUFFICIENT_DATA')).isInsufficient, isTrue);
    expect(SpendingMerchantResponse.fromJson(_payload(status: 'NO_DATA')).isNoData, isTrue);
    expect(SpendingMerchantResponse.fromJson(_payload(status: 'NOT_APPLICABLE')).isNotApplicable, isTrue);
  });

  test('总览展示文案换算正确', () {
    final response = SpendingMerchantResponse.fromJson(_payload());

    expect(response.totalText, '¥1000.00');
    expect(response.totalCountText, '4 笔');
    expect(response.averageText, '¥250.00');
  });

  test('覆盖率与集中度文案换算正确', () {
    final response = SpendingMerchantResponse.fromJson(
        _payload(merchantCoverage: '66.67', top3Concentration: '90.00'));

    expect(response.coverageText, '已有 66.67% 支出记录填写消费对象');
    expect(response.concentrationText, 'Top3 消费对象占比 90%');
  });

  test('未填写提示仅在占比大于零时出现', () {
    final withUnknown = SpendingMerchantResponse.fromJson(
        _payload(unknownMerchantRate: '80.00', unknownMerchantAmount: '800.00'));
    expect(withUnknown.unknownText, '还有 80% 支出未填写消费对象');
    expect(withUnknown.unknownRateValue, 80);

    final noUnknown = SpendingMerchantResponse.fromJson(_payload(unknownMerchantRate: '0.00'));
    expect(noUnknown.unknownText, isNull);
    expect(noUnknown.unknownRateValue, 0);

    final broken = SpendingMerchantResponse.fromJson(_payload(unknownMerchantRate: 'abc'));
    expect(broken.unknownText, isNull);
  });

  test('商户项的金额、笔数与占比文案', () {
    final item = SpendingMerchantResponse.fromJson(_payload()).topMerchants.first;

    expect(item.amountText, '¥700.00');
    expect(item.countText, '2 笔');
    expect(item.percentageText, '70%');
  });

  test('条形占比映射在 0~1 之间', () {
    final item = SpendingMerchantResponse.fromJson(_payload()).topMerchants.first;
    expect(item.ratio, closeTo(0.7, 0.0001));

    final zero = MerchantSpendingItem.fromJson(
        const {'merchantName': 'A', 'amount': '0', 'count': 0, 'percentage': '0.00'});
    expect(zero.ratio, 0);

    final over = MerchantSpendingItem.fromJson(
        const {'merchantName': 'A', 'amount': '0', 'count': 0, 'percentage': '150'});
    expect(over.ratio, 1);
  });

  test('百分比去零工具正确处理', () {
    expect(trimPercent('70.00'), '70');
    expect(trimPercent('12.50'), '12.5');
    expect(trimPercent(''), '0');
    expect(trimPercent('abc'), 'abc');
  });

  test('商户项字段缺失时安全降级', () {
    final item = MerchantSpendingItem.fromJson(const {});

    expect(item.merchantName, '');
    expect(item.amount, '0');
    expect(item.count, 0);
    expect(item.percentage, '0.00');
  });

  // ==================== 区块渲染 ====================

  testWidgets('OK 渲染标题、副标题与总览', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('消费对象分析'), findsOneWidget);
    expect(find.text('看看你的钱主要花给谁'), findsOneWidget);
    expect(find.text('本月支出'), findsOneWidget);
    expect(find.text('¥1000.00'), findsOneWidget);
    expect(find.text('消费笔数'), findsOneWidget);
    expect(find.text('4 笔'), findsOneWidget);
    expect(find.text('平均客单价'), findsOneWidget);
    expect(find.text('¥250.00'), findsOneWidget);
  });

  testWidgets('OK 渲染覆盖情况与集中度', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('已有 100% 支出记录填写消费对象'), findsOneWidget);
    expect(find.text('Top3 消费对象占比 100%'), findsOneWidget);
  });

  testWidgets('OK 渲染消费对象排行与名次', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('消费对象排行'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('食堂'), findsOneWidget);
    expect(find.text('¥700.00'), findsOneWidget);
    expect(find.text('2 笔 · 70%'), findsOneWidget);
    expect(find.text('超市'), findsOneWidget);
    expect(find.text('¥300.00'), findsOneWidget);
    expect(find.text('2 笔 · 30%'), findsOneWidget);
  });

  testWidgets('最多展示五项排行', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload(topMerchants: _items(6))),
      loading: false,
    )));

    expect(find.byType(MerchantCard), findsOneWidget);
    // 即使后端返回更多，页面也只展示前五项
    expect(tester.takeException(), isNull);
    expect(find.text('水果摊'), findsOneWidget, reason: '第 5 项应展示');
    expect(find.text('第六家'), findsNothing, reason: '第 6 项不展示');
  });

  testWidgets('未填写消费对象时展示提示', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(
          _payload(unknownMerchantRate: '80.00', unknownMerchantAmount: '800.00')),
      loading: false,
    )));

    expect(find.text('还有 80% 支出未填写消费对象'), findsOneWidget);
  });

  testWidgets('未填写为零时不展示提示', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.textContaining('未填写消费对象'), findsNothing);
  });

  testWidgets('展示后端一句话总结', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('支出主要集中在 2 个消费对象，合计占 100.00%'), findsOneWidget);
  });

  testWidgets('排行列表为空时仍能渲染', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload(topMerchants: const [])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
    expect(find.byType(MerchantCard), findsOneWidget);
    expect(find.text('消费对象排行'), findsNothing);
  });

  testWidgets('长商户名不溢出', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload(topMerchants: [
        {
          'merchantName': '某某某某某某某某某某超级长的消费对象名称应该被省略号截断',
          'amount': '99999999.99',
          'count': 999,
          'percentage': '100.00',
        },
      ])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
  });

  testWidgets('loading 显示分析提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MerchantSection(data: null, loading: true)),
    ));

    expect(find.text('正在分析消费对象…'), findsOneWidget);
  });

  testWidgets('error 显示中文提示与重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(MerchantSection(
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
      home: Scaffold(body: MerchantSection(data: null, loading: false)),
    ));

    expect(find.byType(MerchantCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NO_DATA 显示本月暂无支出记录', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(
          _payload(status: 'NO_DATA', totalAmount: '0.00', totalCount: 0, topMerchants: const [])),
      loading: false,
    )));

    expect(find.text('本月暂无支出记录'), findsOneWidget);
    expect(find.byType(MerchantCard), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('INSUFFICIENT_DATA 显示消费记录不足与事实数据', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(_payload(
        status: 'INSUFFICIENT_DATA',
        totalAmount: '200.00',
        totalCount: 2,
        topMerchants: const [],
      )),
      loading: false,
    )));

    expect(find.text('消费记录不足'), findsOneWidget);
    expect(find.text('记录更多消费对象后即可分析'), findsOneWidget);
    expect(find.text('本月支出 ¥200.00，共 2 笔'), findsOneWidget);
    expect(find.byType(MerchantCard), findsNothing);
  });

  testWidgets('NOT_APPLICABLE 显示不支持分析且不用错误图标', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(
          _payload(status: 'NOT_APPLICABLE', topMerchants: const [])),
      loading: false,
    )));

    expect(find.text('该月份不支持消费对象分析'), findsOneWidget);
    expect(find.text('统计分析仅针对当前月份'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byType(MerchantCard), findsNothing);
  });

  testWidgets('未知状态回退到后端说明', (tester) async {
    await tester.pumpWidget(_host(MerchantSection(
      data: SpendingMerchantResponse.fromJson(
          _payload(status: 'SOMETHING_NEW', message: '后端新增状态的说明', topMerchants: const [])),
      loading: false,
    )));

    expect(find.text('后端新增状态的说明'), findsOneWidget);
  });

  // ==================== 统计页接入 ====================

  testWidgets('统计页展示消费对象区块', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('消费对象分析'), 200);
    expect(find.text('消费对象分析'), findsOneWidget);
    expect(find.text('消费对象排行'), findsOneWidget);
    expect(find.text('食堂'), findsOneWidget);
  });

  testWidgets('消费对象区块位于来源统计之后消费节奏之前', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final children = (listView.childrenDelegate as SliverChildListDelegate).children;

    final merchant = children.indexWhere((widget) => widget is MerchantSection);
    final rhythm = children.indexWhere((widget) => widget is RhythmSection);

    expect(merchant, greaterThanOrEqualTo(0));
    expect(rhythm, greaterThan(merchant), reason: '消费对象分析应在消费节奏分析之前');
    expect(merchant, greaterThanOrEqualTo(2), reason: '前面还有分类统计与来源统计');
  });

  testWidgets('消费对象接口失败时区块隐藏且其他区块正常', (tester) async {
    ApiClient.testClient = _pageClient(merchantFails: true);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1886.50'), findsWidgets);
    expect(find.text('消费对象分析'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换月份会重新请求消费对象接口', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      if (request.url.path.endsWith('/insights/merchants')) {
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

  test('InsightService.merchants 复用 ApiClient 且只带 month 参数', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final response = await InsightService.merchants('2026-09');

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/insights/merchants'));
    expect(captured!.queryParameters['month'], '2026-09');
    expect(captured!.queryParameters.containsKey('userId'), isFalse);
    expect(response.totalAmount, '1000.00');
    expect(ApiClient.token, 'fake-token', reason: 'JWT 仍由 ApiClient 携带');
  });

  test('消费对象接口错误转换为项目统一中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(400));

    expect(
      () => InsightService.merchants('2026-9'),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });

  test('非 Map 响应抛出统一业务异常', () async {
    ApiClient.testClient = MockClient((request) async => _ok(const []));

    expect(
      () => InsightService.merchants('2026-09'),
      throwsA(predicate((error) => error.toString().contains('数据格式不正确'))),
    );
  });
}

// ==================== 统计页接口桩 ====================

http.Client _pageClient({bool merchantFails = false}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/insights/merchants')) {
      return merchantFails
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
