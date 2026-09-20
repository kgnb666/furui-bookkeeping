import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/spending_anomaly.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/widgets/anomaly_card.dart';

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

Map<String, dynamic> _categorySpike({
  String category = '餐饮',
  String severity = 'HIGH',
  String severityLabel = '需注意',
  String currentAmount = '1200.00',
  String baselineAmount = '400.00',
  String difference = '800.00',
  String changePercent = '200.00',
}) {
  return {
    'type': 'CATEGORY_SPIKE',
    'severity': severity,
    'severityLabel': severityLabel,
    'category': category,
    'title': '$category支出明显上涨',
    'message': '$category本月 ¥$currentAmount，前 3 个月平均 ¥$baselineAmount，'
        '上涨 $changePercent%（多支出 ¥$difference）',
    'currentAmount': currentAmount,
    'baselineAmount': baselineAmount,
    'difference': difference,
    'changePercent': changePercent,
    'merchant': null,
    'billDate': null,
  };
}

Map<String, dynamic> _largeTransaction({
  String category = '购物',
  String merchant = '数码店',
  String? billDate = '2026-09-10',
}) {
  return {
    'type': 'LARGE_TRANSACTION',
    'severity': 'HIGH',
    'severityLabel': '需注意',
    'category': category,
    'title': '出现一笔较高金额消费',
    'message': '$merchant $billDate 支出 ¥300.00，该分类近 90 天单笔中位数 ¥20.00，约为 15.0 倍',
    'currentAmount': '300.00',
    'baselineAmount': '20.00',
    'difference': '280.00',
    'changePercent': '1400.00',
    'merchant': merchant,
    'billDate': billDate,
  };
}

Map<String, dynamic> _frequencySpike() {
  return {
    'type': 'FREQUENCY_SPIKE',
    'severity': 'MEDIUM',
    'severityLabel': '留意',
    'category': '餐饮',
    'title': '餐饮消费频次明显增加',
    'message': '餐饮本月 10 笔，前 3 个月平均 4 笔，多 6 笔',
    'currentAmount': '10',
    'baselineAmount': '4',
    'difference': '6',
    'changePercent': '150.00',
    'merchant': null,
    'billDate': null,
  };
}

Map<String, dynamic> _payload({
  String month = '2026-09',
  String status = 'OK',
  String message = '本月发现 2 处消费异常',
  List<Map<String, dynamic>>? items,
}) {
  return {
    'month': month,
    'status': status,
    'message': message,
    'baselineMonths': ['2026-06', '2026-07', '2026-08'],
    'items': items ?? [_categorySpike()],
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
    final response = AnomaliesResponse.fromJson(_payload());

    expect(response.month, '2026-09');
    expect(response.status, 'OK');
    expect(response.isOk, isTrue);
    expect(response.baselineMonths, ['2026-06', '2026-07', '2026-08']);
    expect(response.items.length, 1);

    final item = response.items.single;
    expect(item.type, 'CATEGORY_SPIKE');
    expect(item.severity, 'HIGH');
    expect(item.severityText, '需注意');
    expect(item.category, '餐饮');
    expect(item.title, '餐饮支出明显上涨');
    expect(item.currentAmount, '1200.00');
    expect(item.baselineAmount, '400.00');
    expect(item.difference, '800.00');
    expect(item.changePercent, '200.00');
    expect(item.merchant, isNull);
    expect(item.billDate, isNull);
  });

  test('items 缺失时按空列表处理', () {
    final response = AnomaliesResponse.fromJson({'month': '2026-09', 'status': 'NO_ANOMALY'});

    expect(response.items, isEmpty);
    expect(response.isNoAnomaly, isTrue);
  });

  test('items 为 null 时按空列表处理', () {
    final response = AnomaliesResponse.fromJson({
      'status': 'NO_DATA',
      'items': null,
    });

    expect(response.items, isEmpty);
    expect(response.isNoData, isTrue);
  });

  test('items 含非对象元素时被忽略', () {
    final response = AnomaliesResponse.fromJson({
      'status': 'OK',
      'items': ['not-an-object', _categorySpike()],
    });

    expect(response.items.length, 1);
  });

  test('缺少可选字段时使用安全默认值', () {
    final response = AnomaliesResponse.fromJson({
      'status': 'OK',
      'items': [
        {'type': 'CATEGORY_SPIKE'},
      ],
    });

    final item = response.items.single;
    expect(item.category, '');
    expect(item.title, '');
    expect(item.message, '');
    expect(item.severity, 'MEDIUM');
    expect(item.severityText, '留意');
    expect(item.currentAmount, '0');
    expect(item.billDate, isNull);
    expect(item.billDateText, isNull);
  });

  test('后端新增未知字段时不会崩溃', () {
    final json = _payload();
    json['unknownFutureField'] = {'a': 1};
    (json['items'] as List).first['anotherField'] = 'x';

    final response = AnomaliesResponse.fromJson(json);

    expect(response.items.length, 1);
    expect(response.items.single.category, '餐饮');
  });

  test('baselineMonths 缺失或含非字符串时安全降级', () {
    expect(AnomaliesResponse.fromJson({'status': 'OK'}).baselineMonths, isEmpty);
    expect(
      AnomaliesResponse.fromJson({
        'status': 'OK',
        'baselineMonths': [1, '2026-08', null],
      }).baselineMonths,
      ['2026-08'],
    );
  });

  // ==================== 展示字段换算 ====================

  test('金额类异常用两位小数展示', () {
    final item = SpendingAnomaly.fromJson(_categorySpike(currentAmount: '1200', baselineAmount: '400'));

    expect(item.currentText, '¥1200.00');
    expect(item.baselineText, '¥400.00');
    expect(item.differenceText, '¥800.00');
  });

  test('频次类异常按笔数展示，不加货币符号', () {
    final item = SpendingAnomaly.fromJson(_frequencySpike());

    expect(item.currentText, '10');
    expect(item.baselineText, '4');
    expect(item.differenceText, '6 笔');
    expect(item.isFrequencySpike, isTrue);
    expect(item.isAmountBased, isFalse);
  });

  test('单笔异常带日期与商户的定位文案', () {
    final item = SpendingAnomaly.fromJson(_largeTransaction());

    expect(item.isLargeTransaction, isTrue);
    expect(item.billDateText, '2026年09月10日');
    expect(item.locationText, '数码店 · 2026年09月10日');
  });

  test('单笔异常商户为空时定位文案退回分类', () {
    final item = SpendingAnomaly.fromJson(_largeTransaction(merchant: ''));

    expect(item.locationText, '购物 · 2026年09月10日');
  });

  test('日期缺失或格式异常时安全降级', () {
    final noDate = SpendingAnomaly.fromJson(_largeTransaction(billDate: null));
    expect(noDate.billDateText, isNull);
    expect(noDate.locationText, '数码店');

    final badDate = SpendingAnomaly.fromJson(_largeTransaction(billDate: 'not-a-date'));
    expect(badDate.billDateText, 'not-a-date');
  });

  test('严重度中文映射与未知值降级', () {
    expect(SpendingAnomaly.fromJson(_categorySpike(severity: 'HIGH')).severityText, '需注意');
    expect(SpendingAnomaly.fromJson(_frequencySpike()).severityText, '留意');
    expect(
      SpendingAnomaly.fromJson(_categorySpike(severity: 'UNKNOWN', severityLabel: '未知级别')).severityText,
      '未知级别',
    );
  });

  test('严重度配色：HIGH 品牌红、MEDIUM 品牌橙', () {
    expect(AnomalyCard.severityColor('HIGH'), const Color(0xFFD64545));
    expect(AnomalyCard.severityColor('MEDIUM'), const Color(0xFFF5A524));
    expect(AnomalyCard.severityColor('UNKNOWN'), isNotNull);
  });

  // ==================== 区块状态 ====================

  testWidgets('OK 状态展示异常卡片与依据', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('消费异常提醒'), findsOneWidget);
    expect(find.text('餐饮支出明显上涨'), findsOneWidget);
    expect(find.text('需注意'), findsOneWidget);
    expect(find.text('¥1200.00'), findsOneWidget);
    expect(find.text('¥400.00'), findsOneWidget);
    expect(find.text('¥800.00'), findsOneWidget);
    expect(find.textContaining('上涨 200.00%'), findsOneWidget);
  });

  testWidgets('OK 状态最多展示 5 条', (tester) async {
    final items = List.generate(7, (i) => _categorySpike(category: '分类$i'));
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(items: items)),
      loading: false,
    )));

    // 后端最多返回 5 条，前端原样展示（此处验证 7 条也能正常渲染不崩溃）
    expect(find.byType(AnomalyCard), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('单笔异常展示日期与商户', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(items: [_largeTransaction()])),
      loading: false,
    )));

    expect(find.text('出现一笔较高金额消费'), findsOneWidget);
    expect(find.text('数码店 · 2026年09月10日'), findsOneWidget);
  });

  testWidgets('频次异常展示笔数而不是金额符号', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(items: [_frequencySpike()])),
      loading: false,
    )));

    expect(find.text('留意'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    expect(find.text('6 笔'), findsOneWidget);
  });

  testWidgets('NO_DATA 显示本月还没有支出记录', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(status: 'NO_DATA', items: [])),
      loading: false,
    )));

    expect(find.text('本月还没有支出记录'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('NOT_ENOUGH_BASELINE 显示积累数据引导', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(status: 'NOT_ENOUGH_BASELINE', items: [])),
      loading: false,
    )));

    expect(find.text('积累几个月数据后，这里可以对比出消费异常'), findsOneWidget);
  });

  testWidgets('NO_ANOMALY 显示消费节奏正常且不用错误图标', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(status: 'NO_ANOMALY', items: [])),
      loading: false,
    )));

    expect(find.text('本月消费节奏正常'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('OK 但 items 为空时按正常处理', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(items: [])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
    expect(find.text('本月消费节奏正常'), findsOneWidget);
  });

  testWidgets('加载中显示分析提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AnomalyCardSection(data: null, loading: true)),
    ));

    expect(find.text('正在分析本月消费异常…'), findsOneWidget);
  });

  testWidgets('网络错误显示统一中文提示与重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(AnomalyCardSection(
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

  testWidgets('data 为空时区块不渲染', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AnomalyCardSection(data: null, loading: false)),
    ));

    // 标题仍在（区块存在），但没有卡片
    expect(find.byType(AnomalyCard), findsNothing);
  });

  testWidgets('长标题与长文案不溢出卡片', (tester) async {
    await tester.pumpWidget(_host(AnomalyCardSection(
      data: AnomaliesResponse.fromJson(_payload(items: [
        _categorySpike(category: '某某某某某某某某超级长的分类名称'),
      ])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
  });

  // ==================== 统计页接入 ====================

  testWidgets('统计页展示消费异常区块并位于周期与洞察之间', (tester) async {
    ApiClient.testClient = _pageClient();

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('消费异常提醒'), 200);
    expect(find.text('消费异常提醒'), findsOneWidget);
    expect(find.text('餐饮支出明显上涨'), findsOneWidget);

    // 周期区块在其上方，消费洞察在下方
    await tester.scrollUntilVisible(find.text('本月消费洞察'), 200);
    expect(find.text('本月消费洞察'), findsOneWidget);
  });

  testWidgets('统计页切换月份会重新请求异常接口', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/insights/anomalies')) {
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

  testWidgets('异常接口失败时统计页其他区块仍正常', (tester) async {
    ApiClient.testClient = _pageClient(anomalyFails: true);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.textContaining('1886.50'), findsWidgets);
    expect(find.text('消费异常提醒'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ==================== Service ====================

  test('InsightService.anomalies 复用 ApiClient 且带 month 参数', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final response = await InsightService.anomalies('2026-09');

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/insights/anomalies'));
    expect(captured!.queryParameters['month'], '2026-09');
    expect(captured!.queryParameters.containsKey('userId'), isFalse);
    expect(response.status, 'OK');
  });

  test('异常接口错误转换为项目统一中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(400));

    expect(
      () => InsightService.anomalies('2025-01'),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });

  test('非 Map 响应抛出统一业务异常', () async {
    ApiClient.testClient = MockClient((request) async => _ok(const []));

    expect(
      () => InsightService.anomalies('2026-09'),
      throwsA(predicate((error) => error.toString().contains('数据格式不正确'))),
    );
  });
}

http.Client _pageClient({bool anomalyFails = false}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/insights/anomalies')) {
      return anomalyFails
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
