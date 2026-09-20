import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/spending_rhythm.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/widgets/anomaly_card.dart';
import 'package:campus_ledger/widgets/forecast_card.dart';
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

List<Map<String, dynamic>> _weekdays() => [
      {'weekday': 1, 'weekdayName': '周一', 'amount': '0.00', 'percentage': '0.00'},
      {'weekday': 2, 'weekdayName': '周二', 'amount': '300.00', 'percentage': '30.00'},
      {'weekday': 3, 'weekdayName': '周三', 'amount': '0.00', 'percentage': '0.00'},
      {'weekday': 4, 'weekdayName': '周四', 'amount': '0.00', 'percentage': '0.00'},
      {'weekday': 5, 'weekdayName': '周五', 'amount': '100.00', 'percentage': '10.00'},
      {'weekday': 6, 'weekdayName': '周六', 'amount': '600.00', 'percentage': '60.00'},
      {'weekday': 7, 'weekdayName': '周日', 'amount': '0.00', 'percentage': '0.00'},
    ];

List<Map<String, dynamic>> _periods() => [
      {'periodName': '1-10日', 'startDay': 1, 'endDay': 10, 'amount': '600.00', 'percentage': '60.00'},
      {'periodName': '11-20日', 'startDay': 11, 'endDay': 20, 'amount': '400.00', 'percentage': '40.00'},
      {'periodName': '21日-月底', 'startDay': 21, 'endDay': 30, 'amount': '0.00', 'percentage': '0.00'},
    ];

Map<String, dynamic> _payload({
  String month = '2026-09',
  String status = 'OK',
  String message = '已分析 2026-09 的消费节奏：当月共 3 天有消费记录',
  Object? totalAmount = '1000.00',
  Object? coveredDays = 3,
  Object? coveredRate = '10.00',
  String peakWeekday = '周六',
  String peakPeriod = '1-10日',
  String concentration = '60.00',
  String summary = '支出主要集中在周六（占 60.00%），月内以 1-10日 最多（占 60.00%）',
  Object? weekdayItems,
  Object? periodItems,
}) {
  return {
    'month': month,
    'status': status,
    'message': message,
    'totalAmount': totalAmount,
    'coveredDays': coveredDays,
    'coveredRate': coveredRate,
    'peakWeekday': peakWeekday,
    'peakPeriod': peakPeriod,
    'concentration': concentration,
    'summary': summary,
    'weekdayItems': weekdayItems ?? _weekdays(),
    'periodItems': periodItems ?? _periods(),
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
    final response = SpendingRhythmResponse.fromJson(_payload());

    expect(response.month, '2026-09');
    expect(response.status, 'OK');
    expect(response.totalAmount, '1000.00');
    expect(response.coveredDays, 3);
    expect(response.coveredRate, '10.00');
    expect(response.peakWeekday, '周六');
    expect(response.peakPeriod, '1-10日');
    expect(response.concentration, '60.00');
    expect(response.summary, contains('周六'));
    expect(response.weekdayItems.length, 7);
    expect(response.periodItems.length, 3);

    final saturday = response.weekdayItems[5];
    expect(saturday.weekday, 6);
    expect(saturday.weekdayName, '周六');
    expect(saturday.amount, '600.00');
    expect(saturday.percentage, '60.00');

    final firstPeriod = response.periodItems.first;
    expect(firstPeriod.periodName, '1-10日');
    expect(firstPeriod.startDay, 1);
    expect(firstPeriod.endDay, 10);
  });

  test('缺少字段时使用安全默认值', () {
    final response = SpendingRhythmResponse.fromJson(const {});

    expect(response.month, '');
    expect(response.status, '');
    expect(response.totalAmount, '0');
    expect(response.coveredDays, 0);
    expect(response.coveredRate, '0.00');
    expect(response.peakWeekday, '');
    expect(response.peakPeriod, '');
    expect(response.concentration, '0.00');
    expect(response.weekdayItems, isEmpty);
    expect(response.periodItems, isEmpty);
  });

  test('空数组解析为空列表', () {
    final response = SpendingRhythmResponse.fromJson(
        _payload(status: 'NO_DATA', weekdayItems: const [], periodItems: const []));

    expect(response.weekdayItems, isEmpty);
    expect(response.periodItems, isEmpty);
  });

  test('列表为 null 或含非对象元素时安全降级', () {
    final nullJson = _payload();
    nullJson['weekdayItems'] = null;
    nullJson['periodItems'] = null;
    final nullLists = SpendingRhythmResponse.fromJson(nullJson);
    expect(nullLists.weekdayItems, isEmpty);
    expect(nullLists.periodItems, isEmpty);

    final broken = _payload();
    broken['weekdayItems'] = [
      {'weekday': 6, 'weekdayName': '周六', 'amount': '600.00', 'percentage': '60.00'},
      'not-a-map',
      42,
    ];
    final response = SpendingRhythmResponse.fromJson(broken);
    expect(response.weekdayItems.length, 1);
    expect(response.weekdayItems.first.weekdayName, '周六');
  });

  test('未知字段被忽略', () {
    final json = _payload();
    json['futureField'] = 'whatever';
    json['nested'] = {'a': 1};

    final response = SpendingRhythmResponse.fromJson(json);

    expect(response.status, 'OK');
    expect(response.totalAmount, '1000.00');
  });

  test('字段类型不符时不崩溃', () {
    final response = SpendingRhythmResponse.fromJson(_payload(
      coveredDays: 'abc',
      coveredRate: 10.5,
      totalAmount: 1000,
      weekdayItems: [
        {'weekday': '6', 'weekdayName': 123, 'amount': 600, 'percentage': 60},
      ],
      periodItems: [
        {'periodName': null, 'startDay': null, 'endDay': null, 'amount': null, 'percentage': null},
      ],
    ));

    expect(response.coveredDays, 0);
    expect(response.coveredRate, '10.5');
    expect(response.totalAmount, '1000');
    expect(response.weekdayItems.first.weekday, 6);
    expect(response.weekdayItems.first.weekdayName, '123');
    expect(response.weekdayItems.first.amountText, '¥600.00');
    expect(response.periodItems.first.periodName, '');
    expect(response.periodItems.first.startDay, 0);
  });

  test('状态 getter 正确区分四种状态', () {
    expect(SpendingRhythmResponse.fromJson(_payload()).isOk, isTrue);
    expect(SpendingRhythmResponse.fromJson(_payload(status: 'INSUFFICIENT_DATA')).isInsufficient, isTrue);
    expect(SpendingRhythmResponse.fromJson(_payload(status: 'NO_DATA')).isNoData, isTrue);
    expect(SpendingRhythmResponse.fromJson(_payload(status: 'NOT_APPLICABLE')).isNotApplicable, isTrue);
  });

  test('展示文案换算正确', () {
    final response = SpendingRhythmResponse.fromJson(_payload());

    expect(response.totalText, '¥1000.00');
    expect(response.coveredDaysText, '已有 3 天消费');
    expect(response.coveredRateText, '覆盖率 10%');
    expect(response.concentrationText, '60%');
    expect(response.weekdayItems[5].amountText, '¥600.00');
    expect(response.weekdayItems[5].percentageText, '60%');
    expect(response.periodItems[1].percentageText, '40%');
  });

  test('条形占比映射在 0~1 之间', () {
    final response = SpendingRhythmResponse.fromJson(_payload());

    expect(response.weekdayItems[5].ratio, closeTo(0.6, 0.0001));
    expect(response.weekdayItems[0].ratio, 0);
    expect(response.periodItems.first.ratio, closeTo(0.6, 0.0001));
  });

  test('阶段范围文案包含起止日', () {
    final response = SpendingRhythmResponse.fromJson(_payload());

    expect(response.periodItems[2].rangeText, '21日-月底（第 21-30 天）');
  });

  // ==================== 区块渲染 ====================

  testWidgets('OK 渲染标题、总支出、覆盖与峰值', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('消费节奏分析'), findsOneWidget);
    expect(find.text('¥1000.00'), findsOneWidget);
    expect(find.textContaining('记账覆盖'), findsOneWidget);
    expect(find.textContaining('已有 3 天消费'), findsOneWidget);
    expect(find.textContaining('覆盖率 10%'), findsOneWidget);
    expect(find.text('最高消费星期'), findsOneWidget);
    expect(find.text('周六'), findsWidgets);
    expect(find.text('最高消费阶段'), findsOneWidget);
    expect(find.text('1-10日'), findsWidgets);
  });

  testWidgets('OK 渲染星期分布七行与月内阶段三行', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('星期分布'), findsOneWidget);
    expect(find.text('月内阶段'), findsOneWidget);
    for (final name in ['周一', '周二', '周三', '周四', '周五', '周日']) {
      expect(find.text(name), findsOneWidget, reason: '$name 应出现一次');
    }
    expect(find.text('11-20日'), findsOneWidget);
    expect(find.text('21日-月底'), findsOneWidget);
    expect(find.text('×'), findsNothing);
  });

  testWidgets('OK 展示金额与百分比', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload()),
      loading: false,
    )));

    // 周六 600 与 1-10 日 600 都是这个金额，因此会有两处
    expect(find.text('¥600.00'), findsNWidgets(2));
    expect(find.text('¥300.00'), findsOneWidget);
    expect(find.text('¥100.00'), findsOneWidget);
    expect(find.text('60%'), findsWidgets);
    expect(find.text('30%'), findsOneWidget);
  });

  testWidgets('OK 展示一句话总结', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.textContaining('支出主要集中在周六'), findsOneWidget);
  });

  testWidgets('分布列表为空时卡片仍能渲染', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(
          _payload(weekdayItems: const [], periodItems: const [], summary: '')),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
    expect(find.text('¥1000.00'), findsOneWidget);
    expect(find.byType(RhythmCard), findsOneWidget);
  });

  testWidgets('NO_DATA 显示本月暂无支出记录', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload(
        status: 'NO_DATA',
        totalAmount: '0.00',
        coveredDays: 0,
        coveredRate: '0.00',
        peakWeekday: '',
        peakPeriod: '',
        concentration: '0.00',
        summary: '',
        weekdayItems: const [],
        periodItems: const [],
      )),
      loading: false,
    )));

    expect(find.text('本月暂无支出记录'), findsOneWidget);
    expect(find.byType(RhythmCard), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('INSUFFICIENT_DATA 显示消费记录不足与已有事实', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload(
        status: 'INSUFFICIENT_DATA',
        totalAmount: '200.00',
        coveredDays: 2,
        coveredRate: '6.67',
        weekdayItems: const [],
        periodItems: const [],
        summary: '',
      )),
      loading: false,
    )));

    expect(find.text('消费记录不足'), findsOneWidget);
    expect(find.text('需要更多消费日期后分析节奏'), findsOneWidget);
    expect(find.text('本月已有 2 天消费，共支出 ¥200.00'), findsOneWidget);
    expect(find.byType(RhythmCard), findsNothing);
  });

  testWidgets('NOT_APPLICABLE 显示仅针对当前月份且不用错误图标', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload(
        status: 'NOT_APPLICABLE',
        weekdayItems: const [],
        periodItems: const [],
        summary: '',
        peakWeekday: '',
        peakPeriod: '',
      )),
      loading: false,
    )));

    expect(find.text('该月份不支持消费节奏分析'), findsOneWidget);
    expect(find.text('统计分析仅针对当前月份'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byType(RhythmCard), findsNothing);
  });

  testWidgets('未知状态回退到后端说明', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(
          _payload(status: 'SOMETHING_NEW', message: '后端新增状态的说明', weekdayItems: const [])),
      loading: false,
    )));

    expect(find.text('后端新增状态的说明'), findsOneWidget);
  });

  testWidgets('加载中显示分析提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RhythmSection(data: null, loading: true)),
    ));

    expect(find.text('正在分析你的消费节奏…'), findsOneWidget);
  });

  testWidgets('网络错误显示统一中文提示与重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(RhythmSection(
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
      home: Scaffold(body: RhythmSection(data: null, loading: false)),
    ));

    expect(find.byType(RhythmCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长文案不溢出', (tester) async {
    await tester.pumpWidget(_host(RhythmSection(
      data: SpendingRhythmResponse.fromJson(_payload(
        summary: '这是一段很长的消费节奏总结，用来验证卡片在极端文案下不会溢出布局边界，也不应该抛出渲染异常',
      )),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
  });

  // ==================== 统计页接入 ====================

  testWidgets('统计页展示消费节奏区块', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('消费节奏分析'), 200);
    expect(find.text('消费节奏分析'), findsOneWidget);
    expect(find.text('¥1000.00'), findsWidgets);
    expect(find.text('星期分布'), findsOneWidget);
  });

  testWidgets('消费节奏区块位于来源统计之后趋势图之前', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final children = (listView.childrenDelegate as SliverChildListDelegate).children;

    final source = children.indexWhere((widget) => widget is Card);
    final rhythm = children.indexWhere((widget) => widget is RhythmSection);
    final forecast = children.indexWhere((widget) => widget is ForecastSection);
    final anomaly = children.indexWhere((widget) => widget is AnomalyCardSection);

    expect(anomaly, greaterThanOrEqualTo(0));
    expect(forecast, greaterThan(anomaly));
    expect(rhythm, greaterThan(source), reason: '消费节奏应在来源统计之后');
    expect(rhythm, greaterThan(forecast));
  });

  testWidgets('节奏接口失败时区块隐藏且其他区块正常', (tester) async {
    ApiClient.testClient = _pageClient(rhythmFails: true);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1886.50'), findsWidgets);
    expect(find.text('消费节奏分析'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计页切换月份会重新请求节奏接口', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      if (request.url.path.endsWith('/insights/rhythm')) {
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

  test('InsightService.rhythm 复用 ApiClient 且只带 month 参数', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final response = await InsightService.rhythm('2026-09');

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/insights/rhythm'));
    expect(captured!.queryParameters['month'], '2026-09');
    expect(captured!.queryParameters.containsKey('userId'), isFalse);
    expect(response.coveredDays, 3);
  });

  test('节奏接口错误转换为项目统一中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(400));

    expect(
      () => InsightService.rhythm('2026-9'),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });

  test('非 Map 响应抛出统一业务异常', () async {
    ApiClient.testClient = MockClient((request) async => _ok(const []));

    expect(
      () => InsightService.rhythm('2026-09'),
      throwsA(predicate((error) => error.toString().contains('数据格式不正确'))),
    );
  });
}

// ==================== 统计页接口桩 ====================

http.Client _pageClient({bool rhythmFails = false}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/insights/rhythm')) {
      return rhythmFails
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
