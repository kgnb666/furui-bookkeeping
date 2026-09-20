import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/spending_forecast.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/widgets/anomaly_card.dart';
import 'package:campus_ledger/widgets/budget_prediction_card.dart';
import 'package:campus_ledger/widgets/forecast_card.dart';
import 'package:campus_ledger/widgets/recurring_bill_card.dart';

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

Map<String, dynamic> _payload({
  String month = '2026-09',
  String targetMonth = '2026-10',
  String status = 'OK',
  String message = '预计 2026-10 支出 ¥1238.33',
  String confidence = 'HIGH',
  String confidenceLabel = '高可信',
  String confidenceReason = '近 3 个月最高 ¥1320.00、最低 ¥1180.00，相差 11.31%',
  String predictedAmount = '1238.33',
  String previousMonthAmount = '1250.00',
  Object? predictedDifference = '-11.67',
  Object? predictedChangePercent = '-0.93',
  String currentMonthAmount = '5000.00',
  Object? elapsedDays = 18,
  Object? sampleMonths,
}) {
  return {
    'month': month,
    'targetMonth': targetMonth,
    'status': status,
    'message': message,
    'confidence': confidence,
    'confidenceLabel': confidenceLabel,
    'confidenceReason': confidenceReason,
    'predictedAmount': predictedAmount,
    'previousMonthAmount': previousMonthAmount,
    'predictedDifference': predictedDifference,
    'predictedChangePercent': predictedChangePercent,
    'currentMonthAmount': currentMonthAmount,
    'elapsedDays': elapsedDays,
    'sampleMonths': sampleMonths ??
        [
          {'month': '2026-08', 'amount': '1250.00', 'weight': 3},
          {'month': '2026-07', 'amount': '1180.00', 'weight': 2},
          {'month': '2026-06', 'amount': '1320.00', 'weight': 1},
        ],
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
    final response = SpendingForecastResponse.fromJson(_payload());

    expect(response.month, '2026-09');
    expect(response.targetMonth, '2026-10');
    expect(response.status, 'OK');
    expect(response.confidence, 'HIGH');
    expect(response.confidenceLabel, '高可信');
    expect(response.predictedAmount, '1238.33');
    expect(response.previousMonthAmount, '1250.00');
    expect(response.predictedDifference, '-11.67');
    expect(response.predictedChangePercent, '-0.93');
    expect(response.currentMonthAmount, '5000.00');
    expect(response.elapsedDays, 18);
    expect(response.sampleMonths.length, 3);
    expect(response.sampleMonths.first.month, '2026-08');
    expect(response.sampleMonths.first.amount, '1250.00');
    expect(response.sampleMonths.first.weight, 3);
  });

  test('sampleMonths 缺失时按空列表处理', () {
    final json = _payload()..remove('sampleMonths');

    final response = SpendingForecastResponse.fromJson(json);

    expect(response.sampleMonths, isEmpty);
  });

  test('sampleMonths 为 null 时按空列表处理', () {
    final json = _payload();
    json['sampleMonths'] = null;

    final response = SpendingForecastResponse.fromJson(json);

    expect(response.sampleMonths, isEmpty);
  });

  test('sampleMonths 含非对象元素时被忽略', () {
    final response = SpendingForecastResponse.fromJson(_payload(sampleMonths: [
      {'month': '2026-08', 'amount': '1250.00', 'weight': 3},
      'not-a-map',
      42,
    ]));

    expect(response.sampleMonths.length, 1);
    expect(response.sampleMonths.first.month, '2026-08');
  });

  test('缺少可选字段时使用安全默认值', () {
    final response = SpendingForecastResponse.fromJson(const {});

    expect(response.month, '');
    expect(response.status, '');
    expect(response.predictedAmount, '0');
    expect(response.previousMonthAmount, '0');
    expect(response.currentMonthAmount, '0');
    expect(response.predictedDifference, isNull);
    expect(response.predictedChangePercent, isNull);
    expect(response.elapsedDays, isNull);
    expect(response.sampleMonths, isEmpty);
  });

  test('后端新增未知字段时不会崩溃', () {
    final json = _payload();
    json['futureField'] = 'whatever';
    json['nested'] = {'a': 1};

    final response = SpendingForecastResponse.fromJson(json);

    expect(response.status, 'OK');
    expect(response.predictedAmount, '1238.33');
  });

  test('predictedDifference 为 null 时不生成对比文案', () {
    final response = SpendingForecastResponse.fromJson(_payload(predictedDifference: null));

    expect(response.differenceSign, isNull);
    expect(response.differenceAmountText, isNull);
    expect(response.differenceText, isNull);
  });

  test('predictedChangePercent 为 null 时不生成百分比', () {
    final response = SpendingForecastResponse.fromJson(_payload(predictedChangePercent: null));

    expect(response.changePercentText, isNull);
  });

  test('elapsedDays 缺失或类型不符时安全降级', () {
    expect(SpendingForecastResponse.fromJson(_payload(elapsedDays: null)).elapsedDays, isNull);
    expect(SpendingForecastResponse.fromJson(_payload(elapsedDays: 'abc')).elapsedDays, isNull);
    expect(SpendingForecastResponse.fromJson(_payload(elapsedDays: '18')).elapsedDays, 18);
  });

  test('差额以数字类型返回时也能安全解析', () {
    final response = SpendingForecastResponse.fromJson(_payload(predictedDifference: -11.67));

    expect(response.predictedDifference, '-11.67');
    expect(response.differenceSign, -1);
    expect(response.differenceText, '较上月减少 ¥11.67');
  });

  test('样本月份缺少字段时使用安全默认值', () {
    final response = SpendingForecastResponse.fromJson(
        _payload(sampleMonths: const [<String, dynamic>{}]));

    expect(response.sampleMonths.length, 1);
    expect(response.sampleMonths.first.month, '');
    expect(response.sampleMonths.first.amount, '0');
    expect(response.sampleMonths.first.weight, 0);
  });

  // ==================== 展示换算 ====================

  test('置信度 HIGH 展示为较稳定', () {
    final response = SpendingForecastResponse.fromJson(_payload(confidence: 'HIGH'));

    expect(response.confidenceText, '较稳定');
  });

  test('置信度 MEDIUM 展示为一般', () {
    final response = SpendingForecastResponse.fromJson(_payload(confidence: 'MEDIUM'));

    expect(response.confidenceText, '一般');
  });

  test('置信度 LOW 展示为波动较大', () {
    final response = SpendingForecastResponse.fromJson(_payload(confidence: 'LOW'));

    expect(response.confidenceText, '波动较大');
  });

  test('未知置信度回退到后端文案，仍为空时显示未知', () {
    expect(SpendingForecastResponse.fromJson(_payload(confidence: 'UNKNOWN', confidenceLabel: '后端文案')).confidenceText,
        '后端文案');
    expect(SpendingForecastResponse.fromJson(_payload(confidence: 'UNKNOWN', confidenceLabel: '')).confidenceText,
        '未知');
    expect(SpendingForecastResponse.fromJson(_payload(confidence: 'NONE', confidenceLabel: '')).confidenceText,
        '未知');
  });

  test('差额为负时生成较上月减少', () {
    final response = SpendingForecastResponse.fromJson(_payload(predictedDifference: '-11.67'));

    expect(response.differenceText, '较上月减少 ¥11.67');
    expect(response.isDecrease, isTrue);
  });

  test('差额为正时生成较上月增加', () {
    final response = SpendingForecastResponse.fromJson(
        _payload(predictedDifference: '166.67', predictedChangePercent: '16.67'));

    expect(response.differenceText, '较上月增加 ¥166.67');
    expect(response.isDecrease, isFalse);
  });

  test('差额为零时生成与上月持平', () {
    final response = SpendingForecastResponse.fromJson(
        _payload(predictedDifference: '0.00', predictedChangePercent: '0.00'));

    expect(response.differenceText, '与上月持平');
    expect(response.changePercentText, isNull, reason: '持平不显示百分比');
  });

  test('变化率文案带正负号', () {
    expect(
        SpendingForecastResponse.fromJson(_payload(predictedChangePercent: '-0.93'))
            .changePercentText,
        '（-0.93%）');
    expect(
        SpendingForecastResponse.fromJson(_payload(predictedChangePercent: '16.67'))
            .changePercentText,
        '（+16.67%）');
  });

  test('样本月份金额与权重文案', () {
    final sample = SpendingForecastResponse.fromJson(_payload()).sampleMonths.first;

    expect(sample.amountText, '¥1250.00');
    expect(sample.weightText, '×3');
  });

  test('状态 getter 正确区分四种状态', () {
    expect(SpendingForecastResponse.fromJson(_payload(status: 'OK')).isOk, isTrue);
    expect(
        SpendingForecastResponse.fromJson(_payload(status: 'INSUFFICIENT_DATA')).isInsufficient, isTrue);
    expect(SpendingForecastResponse.fromJson(_payload(status: 'NO_DATA')).isNoData, isTrue);
    expect(SpendingForecastResponse.fromJson(_payload(status: 'NOT_APPLICABLE')).isNotApplicable,
        isTrue);
  });

  // ==================== 区块渲染 ====================

  testWidgets('OK 显示金额、对比与置信度', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('下月支出预估'), findsOneWidget);
    expect(find.text('下月预计支出'), findsOneWidget);
    expect(find.text('2026-10'), findsOneWidget);
    expect(find.text('¥1238.33'), findsOneWidget);
    expect(find.text('较上月减少 ¥11.67'), findsOneWidget);
    expect(find.text('（-0.93%）'), findsOneWidget);
    expect(find.text('置信度：较稳定'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down), findsOneWidget);
  });

  testWidgets('OK 显示依据里的三条样本', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('依据'), findsOneWidget);
    expect(find.text('2026-08'), findsOneWidget);
    expect(find.text('¥1250.00'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('2026-07'), findsOneWidget);
    expect(find.text('¥1180.00'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('2026-06'), findsOneWidget);
    expect(find.text('¥1320.00'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
  });

  testWidgets('OK 显示置信度依据与免责说明', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.textContaining('近 3 个月最高'), findsOneWidget);
    expect(find.text('按你过去的记账节奏推算，仅供参考，不代表实际支出'), findsOneWidget);
  });

  testWidgets('预估增加时用暖红色与上升图标', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(
          _payload(predictedDifference: '166.67', predictedChangePercent: '16.67')),
      loading: false,
    )));

    expect(find.text('较上月增加 ¥166.67'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
  });

  testWidgets('INSUFFICIENT_DATA 显示历史数据不足与本月事实', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload(
        status: 'INSUFFICIENT_DATA',
        sampleMonths: const [],
        predictedDifference: null,
        predictedChangePercent: null,
      )),
      loading: false,
    )));

    expect(find.text('目前历史数据不足'), findsOneWidget);
    expect(find.text('继续记录几个月后可以预测'), findsOneWidget);
    expect(find.text('本月已过 18 天，已支出 ¥5000.00'), findsOneWidget);
    expect(find.byType(ForecastCard), findsNothing);
  });

  testWidgets('NO_DATA 显示本月暂无支出记录', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload(
        status: 'NO_DATA',
        sampleMonths: const [],
        predictedDifference: null,
        predictedChangePercent: null,
        currentMonthAmount: '0.00',
      )),
      loading: false,
    )));

    expect(find.text('本月暂无支出记录'), findsOneWidget);
    expect(find.text('记录几笔账单后即可预估下月支出'), findsOneWidget);
  });

  testWidgets('NOT_APPLICABLE 显示不支持预测且不用错误图标', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload(
        status: 'NOT_APPLICABLE',
        sampleMonths: const [],
        predictedDifference: null,
        predictedChangePercent: null,
      )),
      loading: false,
    )));

    expect(find.text('该月份不支持预测'), findsOneWidget);
    expect(find.text('下月支出预估只对当前月份有效'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byType(ForecastCard), findsNothing);
  });

  testWidgets('未知状态回退到后端说明', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(
          _payload(status: 'SOMETHING_NEW', message: '后端新增状态的说明')),
      loading: false,
    )));

    expect(find.text('后端新增状态的说明'), findsOneWidget);
    expect(find.byType(ForecastCard), findsNothing);
  });

  testWidgets('加载中显示计算提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ForecastSection(data: null, loading: true)),
    ));

    expect(find.text('正在计算下月预估…'), findsOneWidget);
  });

  testWidgets('网络错误显示统一中文提示与重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(ForecastSection(
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

  testWidgets('data 为空时不渲染卡片也不报错', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ForecastSection(data: null, loading: false)),
    ));

    expect(find.byType(ForecastCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长文案与长内容不溢出', (tester) async {
    await tester.pumpWidget(_host(ForecastSection(
      data: SpendingForecastResponse.fromJson(_payload(
        confidenceReason: '这是一个很长的置信度说明，用来验证卡片在极端文案下不会溢出布局边界',
        sampleMonths: const [
          {'month': '2026-08', 'amount': '1250.00', 'weight': 3},
        ],
      )),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
  });

  test('置信度配色：HIGH 品牌绿、MEDIUM 品牌橙、LOW 中性灰', () {
    expect(ForecastCard.confidenceColor('HIGH'), isNot(ForecastCard.confidenceColor('MEDIUM')));
    expect(ForecastCard.confidenceColor('LOW'), isNot(ForecastCard.confidenceColor('HIGH')));
    expect(ForecastCard.confidenceColor('UNKNOWN'), ForecastCard.confidenceColor('LOW'));
  });

  // ==================== 统计页接入 ====================

  testWidgets('统计页展示下月支出预估区块', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('下月支出预估'), 200);
    expect(find.text('下月支出预估'), findsOneWidget);
    expect(find.text('¥1238.33'), findsOneWidget);
    expect(find.text('置信度：较稳定'), findsOneWidget);
  });

  testWidgets('预估区块位于消费异常与消费洞察之间', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(find.byType(ListView));
    final delegate = listView.childrenDelegate as SliverChildListDelegate;
    final children = delegate.children;

    final prediction = children.indexWhere((widget) => widget is BudgetPredictionSection);
    final recurring = children.indexWhere((widget) => widget is RecurringBillSection);
    final anomaly = children.indexWhere((widget) => widget is AnomalyCardSection);
    final forecast = children.indexWhere((widget) => widget is ForecastSection);

    expect(prediction, greaterThanOrEqualTo(0));
    expect(prediction, lessThan(recurring));
    expect(recurring, lessThan(anomaly));
    expect(anomaly, lessThan(forecast), reason: '下月支出预估应在消费异常之后');
    expect(forecast, lessThan(children.length - 1), reason: '后面还应有消费洞察与统计');
  });

  testWidgets('预估接口失败时区块隐藏且其他区块仍正常', (tester) async {
    ApiClient.testClient = _pageClient(forecastFails: true);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1886.50'), findsWidgets);
    expect(find.text('下月支出预估'), findsNothing);
    // 统计页区块增加后需要先滚动到目标区块（ListView 只构建可见区域）
    await tester.scrollUntilVisible(find.text('消费异常提醒'), 200);
    expect(find.text('消费异常提醒'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('统计页切换月份会重新请求预估接口', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      if (request.url.path.endsWith('/insights/forecast')) {
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

  test('InsightService.forecast 复用 ApiClient 且只带 month 参数', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final response = await InsightService.forecast('2026-09');

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/insights/forecast'));
    expect(captured!.queryParameters['month'], '2026-09');
    expect(captured!.queryParameters.containsKey('userId'), isFalse);
    expect(response.predictedAmount, '1238.33');
  });

  test('预估接口错误转换为项目统一中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(400));

    expect(
      () => InsightService.forecast('2026-9'),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });

  test('非 Map 响应抛出统一业务异常', () async {
    ApiClient.testClient = MockClient((request) async => _ok(const []));

    expect(
      () => InsightService.forecast('2026-09'),
      throwsA(predicate((error) => error.toString().contains('数据格式不正确'))),
    );
  });
}

// ==================== 统计页接口桩 ====================

http.Client _pageClient({bool forecastFails = false}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/insights/forecast')) {
      return forecastFails
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
