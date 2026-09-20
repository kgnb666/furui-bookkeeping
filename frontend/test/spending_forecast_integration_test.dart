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
import 'package:campus_ledger/widgets/forecast_card.dart';

/// 下月支出预估真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final suffix = now.millisecondsSinceEpoch % 1000000;
  final threeMonthUser = 's4d3_$suffix';
  final oneMonthUser = 's4d1_$suffix';
  final emptyUser = 's4d0_$suffix';
  const password = '123456';
  final current = _monthKey(now);
  final next = _monthKey(DateTime(now.year, now.month + 1, 1));
  final previous = _monthKey(DateTime(now.year, now.month - 1, 1));
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），下月预估联调用例将被跳过。');
      return;
    }

    // 账号 A：最近 3 个完整自然月各一笔，本月额外一笔（本月不能参与预估）
    await AuthService.register(username: threeMonthUser, password: password, nickname: '三月样本');
    await AuthService.login(threeMonthUser, password);
    await _create(now, 1, '1250.00');
    await _create(now, 2, '1180.00');
    await _create(now, 3, '1320.00');
    await _create(now, 0, '5000.00');
    await AuthService.logout();

    // 账号 B：只有 1 个完整自然月（预期 INSUFFICIENT_DATA）
    await AuthService.register(username: oneMonthUser, password: password, nickname: '单月样本');
    await AuthService.login(oneMonthUser, password);
    await _create(now, 1, '1000.00');
    await AuthService.logout();

    // 账号 C：完全没有账单（预期 NO_DATA）
    await AuthService.register(username: emptyUser, password: password, nickname: '空账号');
    await AuthService.login(emptyUser, password);
    await AuthService.logout();
  });

  test('Case 1：三个月样本给出预估且数值与手算一致', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(threeMonthUser, password);

    final response = await InsightService.forecast(current);

    expect(response.status, 'OK');
    expect(response.month, current);
    expect(response.targetMonth, next);
    // (1250×3 + 1180×2 + 1320×1) / 6 = 1238.33
    expect(response.predictedAmount, '1238.33');
    expect(response.previousMonthAmount, '1250.00');
    expect(response.predictedDifference, '-11.67');
    expect(response.predictedChangePercent, '-0.93');
    expect(response.confidence, anyOf('HIGH', 'MEDIUM', 'LOW'));
    expect(response.confidenceText, isNotEmpty);
    expect(response.differenceText, '较上月减少 ¥11.67');
  });

  test('Case 2：样本只有最近三个完整月且权重为 3/2/1', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(threeMonthUser, password);

    final response = await InsightService.forecast(current);

    expect(response.sampleMonths, hasLength(3));
    expect(response.sampleMonths.map((sample) => sample.weight).toList(), [3, 2, 1]);
    expect(response.sampleMonths.first.month, previous);
    expect(response.sampleMonths.first.amount, '1250.00');
    expect(response.sampleMonths.first.amountText, '¥1250.00');
    // 当前月不能进入样本
    expect(response.sampleMonths.map((sample) => sample.month), isNot(contains(current)));
    expect(response.currentMonthAmount, '5000.00');
    expect(response.elapsedDays, now.day);
  });

  test('Case 3：只有一个完整月时返回 INSUFFICIENT_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(oneMonthUser, password);

    final response = await InsightService.forecast(current);

    expect(response.status, 'INSUFFICIENT_DATA');
    expect(response.predictedAmount, '0.00');
    expect(response.sampleMonths, isEmpty);
    expect(response.differenceText, isNull);
  });

  test('Case 4：空账号返回 NO_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final response = await InsightService.forecast(current);

    expect(response.status, 'NO_DATA');
    expect(response.predictedAmount, '0.00');
  });

  test('Case 5：未来月份与历史月份都返回 NOT_APPLICABLE', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(threeMonthUser, password);

    final future = await InsightService.forecast(next);
    final past = await InsightService.forecast(previous);

    expect(future.status, 'NOT_APPLICABLE');
    expect(past.status, 'NOT_APPLICABLE');
    expect(future.predictedAmount, '0.00');
  });

  test('Case 6：用户隔离——空账号看不到三个月样本账号的预估', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);
    final forB = await InsightService.forecast(current);

    await AuthService.login(threeMonthUser, password);
    final forA = await InsightService.forecast(current);

    expect(forA.status, 'OK');
    expect(forB.status, 'NO_DATA');
    expect(forB.sampleMonths, isEmpty);
    expect(forB.predictedAmount, '0.00');
  });

  test('Case 7：非法月份返回业务错误', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(threeMonthUser, password);

    await expectLater(
      InsightService.forecast('2026-9'),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('Case 8：用真实数据渲染下月预估区块', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 真实网络请求必须放在 runAsync 里，否则 FakeAsync 时钟不会推进
    final response = (await tester.runAsync(() async {
      await AuthService.login(threeMonthUser, password);
      return InsightService.forecast(current);
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ForecastSection(data: response, loading: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('下月支出预估'), findsOneWidget);
    expect(find.text('下月预计支出'), findsOneWidget);
    expect(find.text('¥1238.33'), findsOneWidget);
    expect(find.text('较上月减少 ¥11.67'), findsOneWidget);
    expect(find.textContaining('置信度：'), findsOneWidget);
    expect(find.byType(ForecastCard), findsOneWidget);
  });

  testWidgets('Case 9：真实数据下数据不足与空账号显示引导', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final responses = (await tester.runAsync(() async {
      await AuthService.login(oneMonthUser, password);
      final one = await InsightService.forecast(current);
      await AuthService.login(emptyUser, password);
      final empty = await InsightService.forecast(current);
      return [one, empty];
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ForecastSection(data: responses[0], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('目前历史数据不足'), findsOneWidget);
    expect(find.text('继续记录几个月后可以预测'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ForecastSection(data: responses[1], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本月暂无支出记录'), findsOneWidget);
  });
}

/// 在 monthsAgo 个月前的 15 号记一笔支出（monthsAgo = 0 表示本月）
Future<void> _create(DateTime now, int monthsAgo, String amount) async {
  await BillService.create(
    type: 1,
    amount: amount,
    category: '餐饮',
    billDate: _dayInMonth(now, monthsAgo, 15),
    merchant: '预估联调',
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
