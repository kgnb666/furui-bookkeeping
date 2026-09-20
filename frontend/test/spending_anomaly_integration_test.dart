import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/widgets/anomaly_card.dart';

/// 消费异常检测真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final suffix = now.millisecondsSinceEpoch % 1000000;
  final anomalyUser = 's4c_ano_$suffix';
  final emptyUser = 's4c_empty_$suffix';
  final thinUser = 's4c_thin_$suffix';
  const password = '123456';
  final month = _monthKey(now);
  final previousMonth = _monthKey(DateTime(now.year, now.month - 1, 1));
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），消费异常联调用例将被跳过。');
      return;
    }

    // 账号 A：前 3 个月稳定消费 + 本月明显偏离，三类异常都能命中
    await AuthService.register(username: anomalyUser, password: password, nickname: '异常联调');
    await AuthService.login(anomalyUser, password);
    await _seedAnomalyData(now);
    await AuthService.logout();

    // 账号 B：完全没有账单（预期 NO_DATA）
    await AuthService.register(username: emptyUser, password: password, nickname: '空账号');
    await AuthService.login(emptyUser, password);
    await AuthService.logout();

    // 账号 C：本月有支出但只此一笔，也没有历史（预期 NOT_ENOUGH_BASELINE）
    await AuthService.register(username: thinUser, password: password, nickname: '无基线');
    await AuthService.login(thinUser, password);
    await BillService.create(
      type: 1,
      amount: '50.00',
      category: '餐饮',
      billDate: _dayInMonth(now, 0, 1),
      merchant: '第一食堂',
    );
    await AuthService.logout();
  });

  test('Case 1：命中三类异常且返回 OK', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(anomalyUser, password);

    final result = await InsightService.anomalies(month);

    expect(result.status, 'OK');
    expect(result.month, month);
    expect(result.items, isNotEmpty);
    expect(result.items.length, lessThanOrEqualTo(5), reason: '最多返回 5 条');
    expect(result.baselineMonths, hasLength(3));
    expect(result.baselineMonths, contains(previousMonth));

    final types = result.items.map((item) => item.type).toSet();
    expect(types, contains('CATEGORY_SPIKE'));
    expect(types, contains('LARGE_TRANSACTION'));
    expect(types, contains('FREQUENCY_SPIKE'));

    for (final item in result.items) {
      expect(item.severity, anyOf('HIGH', 'MEDIUM'));
      expect(item.severityLabel, anyOf('需注意', '留意'));
      expect(item.severityText, item.severityLabel);
      expect(item.title, isNotEmpty);
      expect(item.message, isNotEmpty);
      expect(item.difference, matches(RegExp(r'^\d+(\.\d+)?$')));
    }
    // 高危异常排在前面的都是 HIGH
    expect(result.items.first.severity, 'HIGH');
  });

  test('Case 2：单笔异常带上商户与日期，缺失时退回分类', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(anomalyUser, password);

    final result = await InsightService.anomalies(month);
    final large = result.items.firstWhere((item) => item.isLargeTransaction);

    expect(large.currentAmount, '300.00');
    expect(large.baselineAmount, isNotEmpty);
    expect(large.merchant, '数码店');
    expect(large.billDateText, matches(RegExp(r'^\d{4}年\d{2}月\d{2}日$')));
    expect(large.locationText, contains('数码店'));
    expect(large.currentText, startsWith('¥'));
    expect(large.isAmountBased, isTrue);
  });

  test('Case 3：分类上涨与频次异常的展示换算可用', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(anomalyUser, password);

    final result = await InsightService.anomalies(month);
    final spike = result.items.firstWhere((item) => item.isCategorySpike);
    final frequency = result.items.firstWhere((item) => item.isFrequencySpike);

    expect(spike.currentText, startsWith('¥'));
    expect(spike.baselineText, startsWith('¥'));
    expect(spike.differenceText, startsWith('¥'));
    expect(spike.locationText, isNotEmpty);

    // 频次类的 current/baseline 是笔数，不带货币符号
    expect(frequency.currentText, isNot(startsWith('¥')));
    expect(frequency.differenceText, endsWith(' 笔'));
    expect(frequency.billDate, isNull);
  });

  test('Case 4：空账号返回 NO_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final result = await InsightService.anomalies(month);

    expect(result.status, 'NO_DATA');
    expect(result.items, isEmpty);
    expect(result.message, isNotEmpty);
  });

  test('Case 5：基线不足时返回 NOT_ENOUGH_BASELINE', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(thinUser, password);

    final result = await InsightService.anomalies(month);

    expect(result.status, 'NOT_ENOUGH_BASELINE');
    expect(result.items, isEmpty);
  });

  test('Case 6：用户隔离——空账号看不到异常账号的结果', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);
    final forB = await InsightService.anomalies(month);

    await AuthService.login(anomalyUser, password);
    final forA = await InsightService.anomalies(month);

    expect(forA.items, isNotEmpty);
    expect(forB.items, isEmpty, reason: 'B 不能看到 A 的消费异常');
    expect(forB.status, 'NO_DATA');
  });

  test('Case 7：历史月份可查，超过 12 个月返回 400', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(anomalyUser, password);

    final history = await InsightService.anomalies(previousMonth);
    expect(history.month, previousMonth);
    expect(history.status, isNotEmpty);

    final tooOld = _monthKey(DateTime(now.year - 2, now.month, 1));
    await expectLater(
      InsightService.anomalies(tooOld),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('Case 8：真实数据渲染异常区块', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 真实网络请求必须放在 runAsync 里，否则 FakeAsync 时钟不会推进
    final result = (await tester.runAsync(() async {
      await AuthService.login(anomalyUser, password);
      return InsightService.anomalies(month);
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AnomalyCardSection(data: result, loading: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('消费异常提醒'), findsOneWidget);
    expect(find.byType(AnomalyCard), findsNWidgets(result.items.length));
    expect(find.text('需注意'), findsWidgets);
    for (final item in result.items) {
      expect(find.text(item.title), findsOneWidget);
    }
  });

  testWidgets('Case 9：空数据与基线不足渲染引导文案', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final results = (await tester.runAsync(() async {
      await AuthService.login(emptyUser, password);
      final empty = await InsightService.anomalies(month);
      await AuthService.login(thinUser, password);
      final thin = await InsightService.anomalies(month);
      return [empty, thin];
    }))!;
    final empty = results[0];
    final thin = results[1];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AnomalyCardSection(data: empty, loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本月还没有支出记录'), findsOneWidget);
    expect(find.byType(AnomalyCard), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AnomalyCardSection(data: thin, loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('积累几个月数据后，这里可以对比出消费异常'), findsOneWidget);
  });
}

/// 构造账号 A：稳定的前 3 个月 + 明显偏离的本月
Future<void> _seedAnomalyData(DateTime now) async {
  // 分类上涨：前 3 个月各 400，本月 1200
  for (final monthsAgo in [1, 2, 3]) {
    await BillService.create(
      type: 1,
      amount: '400.00',
      category: '餐饮',
      billDate: _dayInMonth(now, monthsAgo, 20),
      merchant: '第一食堂',
    );
  }
  await BillService.create(
    type: 1,
    amount: '1200.00',
    category: '餐饮',
    billDate: _dayInMonth(now, 0, 1),
    merchant: '第一食堂',
  );

  // 频次异常：前 3 个月各 3 笔，本月 8 笔（单笔 10 元，金额差异不足 100 元，不会触发金额上涨）
  for (final monthsAgo in [1, 2, 3]) {
    for (final day in [10, 11, 12]) {
      await BillService.create(
        type: 1,
        amount: '10.00',
        category: '交通',
        billDate: _dayInMonth(now, monthsAgo, day),
        merchant: '城市公交',
      );
    }
  }
  for (var i = 0; i < 8; i++) {
    await BillService.create(
      type: 1,
      amount: '10.00',
      category: '交通',
      billDate: _dayInMonth(now, 0, 1),
      merchant: '城市公交',
    );
  }

  // 单笔异常：同类近 90 天中位数 20 元，本月出现 300 元
  for (final daysAgo in [30, 37, 44, 51, 58]) {
    await BillService.create(
      type: 1,
      amount: '20.00',
      category: '购物',
      billDate: Formatters.apiDate(now.subtract(Duration(days: daysAgo))),
      merchant: '校园超市',
    );
  }
  await BillService.create(
    type: 1,
    amount: '300.00',
    category: '购物',
    billDate: _dayInMonth(now, 0, 1),
    merchant: '数码店',
  );
}

String _monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// 取 monthsAgo 个月前的某一天；日期越界时自动落到当月最后一天
String _dayInMonth(DateTime now, int monthsAgo, int day) {
  final base = DateTime(now.year, now.month - monthsAgo, 1);
  final lastDay = DateTime(base.year, base.month + 1, 0).day;
  return Formatters.apiDate(DateTime(base.year, base.month, day > lastDay ? lastDay : day));
}

Future<bool> _backendReady() async {
  try {
    final base = Uri.parse('${ApiConfig.baseUrl}/');
    final response = await HttpClient()
        .getUrl(base.resolve('health'))
        .timeout(const Duration(seconds: 2))
        .then((request) => request.close())
        .timeout(const Duration(seconds: 2));
    await response.drain<void>();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}
