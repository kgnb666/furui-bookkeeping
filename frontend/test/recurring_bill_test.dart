import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/recurring_bill.dart';
import 'package:campus_ledger/pages/home_page.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/insight_service.dart';
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

/// 构造一条周期结果，字段与后端返回保持一致
Map<String, dynamic> _item({
  String merchant = '腾讯视频VIP',
  String category = '娱乐',
  String cycleType = 'MONTHLY',
  String cycleLabel = '每月一次',
  String confidence = 'HIGH',
  String confidenceLabel = '高',
  int sampleCount = 5,
  String averageAmount = '25.00',
  int averageInterval = 30,
  String intervalRange = '30~30 天',
  String? lastDate = '2026-09-17',
  String? nextDate = '2026-10-17',
  String reason = '近180天 5 次消费，金额稳定，约每 30 天发生一次（间隔 30~30 天，平均 ¥25.00）',
}) {
  return {
    'merchant': merchant,
    'category': category,
    'cycleType': cycleType,
    'cycleLabel': cycleLabel,
    'confidence': confidence,
    'confidenceLabel': confidenceLabel,
    'sampleCount': sampleCount,
    'averageAmount': averageAmount,
    'averageInterval': averageInterval,
    'intervalRange': intervalRange,
    'amountCv': '0.00',
    'categoryRatio': '100.00',
    'lastDate': lastDate,
    'nextDate': nextDate,
    'reason': reason,
  };
}

Map<String, dynamic> _payload({
  String status = 'OK',
  String message = '在最近 180 天的账单中识别到 2 项周期性支出',
  List<Map<String, dynamic>>? items,
}) {
  return {
    'windowDays': 180,
    'status': status,
    'message': message,
    'items': items ?? [_item()],
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

  // ==================== Model ====================

  test('完整 JSON 解析出全部展示字段', () {
    final bills = RecurringBills.fromJson(_payload());

    expect(bills.windowDays, 180);
    expect(bills.status, 'OK');
    expect(bills.isOk, isTrue);
    expect(bills.items.length, 1);

    final item = bills.items.single;
    expect(item.merchant, '腾讯视频VIP');
    expect(item.category, '娱乐');
    expect(item.cycleType, 'MONTHLY');
    expect(item.cycleText, '每月一次');
    expect(item.confidence, 'HIGH');
    expect(item.confidenceText, '高可信');
    expect(item.sampleCount, 5);
    expect(item.averageAmount, '25.00');
    expect(item.amountText, '25.00');
    expect(item.averageInterval, 30);
    expect(item.intervalRange, '30~30 天');
    expect(item.lastDate, '2026-09-17');
    expect(item.nextDate, '2026-10-17');
    expect(item.reason, contains('近180天'));
  });

  test('items 缺失时按空列表处理', () {
    final bills = RecurringBills.fromJson({'windowDays': 180, 'status': 'OK'});

    expect(bills.items, isEmpty);
    expect(bills.displayable, isEmpty);
  });

  test('items 为 null 时按空列表处理', () {
    final bills = RecurringBills.fromJson({
      'windowDays': 180,
      'status': 'NO_RECURRING',
      'message': '没有发现',
      'items': null,
    });

    expect(bills.items, isEmpty);
    expect(bills.isNoRecurring, isTrue);
  });

  test('缺少可选字段时使用安全默认值', () {
    final bills = RecurringBills.fromJson({
      'status': 'OK',
      'items': [
        {'merchant': '某商户'},
      ],
    });

    final item = bills.items.single;
    expect(item.merchant, '某商户');
    expect(item.category, '');
    expect(item.cycleType, '');
    expect(item.cycleText, '周期性支出');
    expect(item.confidence, 'LOW');
    expect(item.confidenceText, '低可信');
    expect(item.sampleCount, 0);
    expect(item.averageAmount, '0.00');
    expect(item.nextDate, isNull);
    expect(bills.windowDays, 180);
  });

  test('后端新增未知字段时不会崩溃', () {
    final json = _payload();
    json['newFieldFromServer'] = {'a': 1};
    (json['items'] as List).first['unknownFutureField'] = 'x';

    final bills = RecurringBills.fromJson(json);

    expect(bills.items.length, 1);
    expect(bills.items.single.merchant, '腾讯视频VIP');
  });

  test('items 中出现非对象元素时被忽略', () {
    final bills = RecurringBills.fromJson({
      'status': 'OK',
      'items': [
        'not-an-object',
        _item(merchant: '正常商户'),
      ],
    });

    expect(bills.items.length, 1);
    expect(bills.items.single.merchant, '正常商户');
  });

  test('金额与日期解析符合项目约定', () {
    // 金额统一两位小数，不做浮点计算
    expect(RecurringBills.fromJson(_payload(items: [_item(averageAmount: '15')]))
        .items.single.amountText, '15.00');
    expect(RecurringBills.fromJson(_payload(items: [_item(averageAmount: '15.0')]))
        .items.single.amountText, '15.00');
    // 日期缺失不影响解析
    final noDate = RecurringBills.fromJson(_payload(items: [_item(nextDate: null)]))
        .items.single;
    expect(noDate.nextDate, isNull);
    expect(noDate.cycleText, '每月一次');
  });

  // ==================== 排序 ====================

  test('按置信度 HIGH > MEDIUM > LOW 排序', () {
    final sorted = sortRecurringBills([
      RecurringBill.fromJson(_item(merchant: '低', confidence: 'LOW', confidenceLabel: '低')),
      RecurringBill.fromJson(_item(merchant: '高', confidence: 'HIGH', confidenceLabel: '高')),
      RecurringBill.fromJson(_item(merchant: '中', confidence: 'MEDIUM', confidenceLabel: '中')),
    ]);

    expect(sorted.map((item) => item.confidence).toList(), ['HIGH', 'MEDIUM', 'LOW']);
  });

  test('同置信度按下一次日期越近越优先', () {
    final sorted = sortRecurringBills([
      RecurringBill.fromJson(_item(merchant: '远', nextDate: '2026-12-01')),
      RecurringBill.fromJson(_item(merchant: '近', nextDate: '2026-09-20')),
      RecurringBill.fromJson(_item(merchant: '中', nextDate: '2026-10-15')),
    ]);

    expect(sorted.map((item) => item.merchant).toList(), ['近', '中', '远']);
  });

  test('同日期按平均金额降序', () {
    final sorted = sortRecurringBills([
      RecurringBill.fromJson(_item(merchant: '小', averageAmount: '25.00')),
      RecurringBill.fromJson(_item(merchant: '大', averageAmount: '1200.00')),
      RecurringBill.fromJson(_item(merchant: '中', averageAmount: '88.00')),
    ]);

    expect(sorted.map((item) => item.merchant).toList(), ['大', '中', '小']);
  });

  test('所有条件相同时按商户字典序保证稳定', () {
    final sorted = sortRecurringBills([
      RecurringBill.fromJson(_item(merchant: 'C店')),
      RecurringBill.fromJson(_item(merchant: 'A店')),
      RecurringBill.fromJson(_item(merchant: 'B店')),
    ]);

    expect(sorted.map((item) => item.merchant).toList(), ['A店', 'B店', 'C店']);
  });

  test('没有下一次日期时排在后面', () {
    final sorted = sortRecurringBills([
      RecurringBill.fromJson(_item(merchant: '无日期', nextDate: null)),
      RecurringBill.fromJson(_item(merchant: '有日期', nextDate: '2026-11-01')),
    ]);

    expect(sorted.first.merchant, '有日期');
  });

  // ==================== Widget 状态 ====================

  testWidgets('HIGH 结果正常显示卡片内容', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload()),
      loading: false,
    )));

    expect(find.text('周期性支出提醒'), findsOneWidget);
    expect(find.text('腾讯视频VIP'), findsOneWidget);
    expect(find.text('娱乐 · 每月一次'), findsOneWidget);
    expect(find.text('¥25.00'), findsOneWidget);
    expect(find.text('高可信'), findsOneWidget);
    expect(find.text('2026年10月17日'), findsOneWidget);
    expect(find.text('5 次记录'), findsOneWidget);
    expect(find.textContaining('近180天'), findsOneWidget);
  });

  testWidgets('MEDIUM 结果展示中可信', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(items: [
        _item(merchant: '学校书店', cycleType: 'BIWEEKLY', cycleLabel: '每两周一次',
            confidence: 'MEDIUM', confidenceLabel: '中', averageAmount: '45.00'),
      ])),
      loading: false,
    )));

    expect(find.text('中可信'), findsOneWidget);
    expect(find.textContaining('每两周一次'), findsOneWidget);
    expect(find.text('¥45.00'), findsOneWidget);
  });

  testWidgets('未知周期类型安全降级不崩溃', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(items: [
        _item(cycleType: 'YEARLY', cycleLabel: ''),
      ])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('周期性支出'), findsWidgets);
  });

  testWidgets('加载中显示分析提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: RecurringBillSection(data: null, loading: true)),
    ));

    expect(find.text('正在分析你的消费规律…'), findsOneWidget);
  });

  testWidgets('NO_DATA 显示记录太少的引导而不是错误', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(status: 'NO_DATA', items: [])),
      loading: false,
    )));

    expect(find.text('记录还太少'), findsOneWidget);
    expect(find.textContaining('积累更多数据'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('NOT_ENOUGH_HISTORY 显示时间不够的引导', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(status: 'NOT_ENOUGH_HISTORY', items: [])),
      loading: false,
    )));

    expect(find.text('账单时间还不够长'), findsOneWidget);
    expect(find.textContaining('几个月的数据'), findsOneWidget);
  });

  testWidgets('NO_RECURRING 显示未发现周期', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(status: 'NO_RECURRING', items: [])),
      loading: false,
    )));

    expect(find.text('暂未发现明显周期性支出'), findsOneWidget);
  });

  testWidgets('OK 但 items 为空时按未发现周期处理', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(items: [])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
    expect(find.text('暂未发现明显周期性支出'), findsOneWidget);
  });

  testWidgets('网络错误显示统一中文提示与重试', (tester) async {
    var retried = false;
    await tester.pumpWidget(_host(RecurringBillSection(
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

  testWidgets('长商户名不溢出卡片', (tester) async {
    await tester.pumpWidget(_host(RecurringBillSection(
      data: RecurringBills.fromJson(_payload(items: [
        _item(merchant: '某某某某某某某某超级长的商户名称有限公司光谷广场旗舰店'),
      ])),
      loading: false,
    )));

    expect(tester.takeException(), isNull);
  });

  // ==================== 首页 ====================

  testWidgets('首页最多展示 1 条且取排序后的第一条', (tester) async {
    ApiClient.testClient = _pageClient(items: [
      _item(merchant: '中等商户', confidence: 'MEDIUM', confidenceLabel: '中'),
      _item(merchant: '腾讯视频VIP', confidence: 'HIGH', confidenceLabel: '高'),
    ]);

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    // 首页内容较长，周期区块在可视区之外时需要先滚动过去
    await tester.scrollUntilVisible(find.text('周期性支出提醒'), 200);
    expect(find.text('周期性支出提醒'), findsOneWidget);
    expect(find.byType(RecurringBillCard), findsOneWidget);
    expect(find.text('腾讯视频VIP'), findsOneWidget, reason: '应当展示置信度最高的那条');
    expect(find.text('中等商户'), findsNothing);
  });

  testWidgets('首页只有 LOW 时不显示周期区块', (tester) async {
    ApiClient.testClient = _pageClient(items: [
      _item(merchant: '低可信商户', confidence: 'LOW', confidenceLabel: '低'),
    ]);

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('周期性支出提醒'), findsNothing);
    expect(find.byType(RecurringBillCard), findsNothing);
  });

  testWidgets('首页无周期结果时不产生空白区域', (tester) async {
    ApiClient.testClient = _pageClient(status: 'NO_RECURRING', items: []);

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('周期性支出提醒'), findsNothing);
  });

  testWidgets('周期接口失败时首页其他内容正常', (tester) async {
    ApiClient.testClient = _pageClient(recurringFails: true);

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    // 首页概览仍在，周期区块隐藏
    expect(find.textContaining('本月支出'), findsWidgets);
    expect(find.text('周期性支出提醒'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ==================== 统计页 ====================

  testWidgets('统计页展示全部周期结果', (tester) async {
    ApiClient.testClient = _pageClient(items: [
      _item(merchant: '腾讯视频VIP', confidence: 'HIGH', confidenceLabel: '高'),
      _item(merchant: '学校书店', confidence: 'MEDIUM', confidenceLabel: '中',
          cycleType: 'BIWEEKLY', cycleLabel: '每两周一次'),
      _item(merchant: '城市公交', confidence: 'HIGH', confidenceLabel: '高',
          cycleType: 'WEEKLY', cycleLabel: '每周一次'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    // 统计页内容较长，先滚动让周期区块进入可视区
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('周期性支出提醒'), findsOneWidget);
    expect(find.byType(RecurringBillCard), findsNWidgets(3));
  });

  testWidgets('统计页周期区块位于预算预测之后、消费洞察之前', (tester) async {
    ApiClient.testClient = _pageClient(items: [_item()]);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    // 周期区块先出现（在消费洞察之上），滚动到位后消费洞察也能出现
    await tester.scrollUntilVisible(find.text('周期性支出提醒'), 200);
    expect(find.text('智能预算预测'), findsOneWidget, reason: '预算预测应在其上方');
    expect(find.text('周期性支出提醒'), findsOneWidget);
    expect(find.text('腾讯视频VIP'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('本月消费洞察'), 200);
    expect(find.text('本月消费洞察'), findsOneWidget);
  });

  testWidgets('统计页无周期数据时仍显示引导文案', (tester) async {
    ApiClient.testClient = _pageClient(status: 'NO_DATA', items: []);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('周期性支出提醒'), findsOneWidget);
    expect(find.text('记录还太少'), findsOneWidget);
  });

  // ==================== Service ====================

  test('InsightService.recurring 复用 ApiClient 且路径正确', () async {
    Uri? captured;
    ApiClient.testClient = MockClient((request) async {
      captured = request.url;
      return _ok(_payload());
    });
    ApiClient.token = 'fake-token';

    final bills = await InsightService.recurring();

    expect(captured, isNotNull);
    expect(captured!.path, endsWith('/api/insights/recurring'));
    expect(bills.status, 'OK');
    expect(bills.items.single.merchant, '腾讯视频VIP');
  });

  test('周期接口异常转换为项目统一中文提示', () async {
    ApiClient.testClient = MockClient((request) async => _fail(500));

    expect(
      () => InsightService.recurring(),
      throwsA(predicate((error) => error.toString().contains('服务器开小差了'))),
    );
  });
}

/// 首页 / 统计页共用的桩：周期接口按参数返回，其余接口给最小可用数据
http.Client _pageClient({
  List<Map<String, dynamic>>? items,
  String status = 'OK',
  bool recurringFails = false,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/insights/recurring')) {
      return recurringFails ? _fail(500) : _ok(_payload(status: status, items: items));
    }
    return _pageStub(request);
  });
}

Future<http.Response> _pageStub(http.Request request) async {
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
      'summary': '本月支出 ¥1886.50。',
      'insights': const [],
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
  if (path.endsWith('/bills')) {
    return _ok({'total': 0, 'page': 1, 'size': 5, 'list': const []});
  }
  return _ok(const {});
}
