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
import 'package:campus_ledger/widgets/rhythm_card.dart';

/// 消费节奏分析真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final suffix = now.millisecondsSinceEpoch % 1000000;
  final rhythmUser = 's4e3_ok_$suffix';
  final thinUser = 's4e3_thin_$suffix';
  final emptyUser = 's4e3_empty_$suffix';
  const password = '123456';
  final current = _monthKey(now);
  final previous = _monthKey(DateTime(now.year, now.month - 1, 1));
  final next = _monthKey(DateTime(now.year, now.month + 1, 1));
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），消费节奏联调用例将被跳过。');
      return;
    }

    // 账号 A：当月前三天各一笔（金额 300 / 200 / 100），三个不同星期
    await AuthService.register(username: rhythmUser, password: password, nickname: '节奏样本');
    await AuthService.login(rhythmUser, password);
    await _create(now, 1, '300.00');
    await _create(now, 2, '200.00');
    await _create(now, 3, '100.00');
    await AuthService.logout();

    // 账号 B：只有两天有消费（预期 INSUFFICIENT_DATA）
    await AuthService.register(username: thinUser, password: password, nickname: '两天样本');
    await AuthService.login(thinUser, password);
    await _create(now, 1, '100.00');
    await _create(now, 2, '100.00');
    await AuthService.logout();

    // 账号 C：完全没有账单（预期 NO_DATA）
    await AuthService.register(username: emptyUser, password: password, nickname: '空账号');
    await AuthService.login(emptyUser, password);
    await AuthService.logout();
  });

  test('Case 1：有三天消费时返回 OK 且金额与分布正确', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(rhythmUser, password);

    final response = await InsightService.rhythm(current);

    expect(response.status, 'OK');
    expect(response.month, current);
    expect(response.totalAmount, '600.00');
    expect(response.totalText, '¥600.00');
    expect(response.coveredDays, 3);
    expect(response.coveredRate, ((3 * 100) / daysInMonth).toStringAsFixed(2));
    expect(response.weekdayItems, hasLength(7));
    expect(response.periodItems, hasLength(3));
  });

  test('Case 2：星期分布与月内阶段分布与账单一致', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(rhythmUser, password);

    final response = await InsightService.rhythm(current);

    // 三天金额分别 300 / 200 / 100，占 50% / 33.33% / 16.67%
    final highest = response.weekdayItems.reduce((a, b) => a.ratio >= b.ratio ? a : b);
    expect(highest.amountText, '¥300.00');
    expect(highest.percentageText, '50%');
    expect(response.peakWeekday, highest.weekdayName);
    expect(response.concentrationText, '50%');

    // 前三天都落在第一阶段，因此第一段占 100%
    expect(response.periodItems.first.amountText, '¥600.00');
    expect(response.periodItems.first.percentageText, '100%');
    expect(response.peakPeriod, response.periodItems.first.periodName);
    expect(response.summary, contains(response.peakWeekday));
  });

  test('Case 3：只有两天消费时返回 INSUFFICIENT_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(thinUser, password);

    final response = await InsightService.rhythm(current);

    expect(response.status, 'INSUFFICIENT_DATA');
    expect(response.coveredDays, 2);
    expect(response.totalAmount, '200.00');
    expect(response.weekdayItems, isEmpty);
    expect(response.periodItems, isEmpty);
    expect(response.peakWeekday, isEmpty);
  });

  test('Case 4：空账号返回 NO_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final response = await InsightService.rhythm(current);

    expect(response.status, 'NO_DATA');
    expect(response.totalAmount, '0.00');
    expect(response.coveredDays, 0);
    expect(response.weekdayItems, isEmpty);
  });

  test('Case 5：历史月份与未来月份都返回 NOT_APPLICABLE', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(rhythmUser, password);

    final past = await InsightService.rhythm(previous);
    final future = await InsightService.rhythm(next);

    expect(past.status, 'NOT_APPLICABLE');
    expect(future.status, 'NOT_APPLICABLE');
    expect(past.weekdayItems, isEmpty);
  });

  test('Case 6：用户隔离——空账号看不到有数据账号的节奏', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);
    final forB = await InsightService.rhythm(current);

    await AuthService.login(rhythmUser, password);
    final forA = await InsightService.rhythm(current);

    expect(forA.status, 'OK');
    expect(forB.status, 'NO_DATA');
    expect(forB.totalAmount, '0.00');
    expect(forB.weekdayItems, isEmpty);
  });

  test('Case 7：非法月份返回业务错误', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(rhythmUser, password);

    await expectLater(
      InsightService.rhythm('2026-9'),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('Case 8：用真实数据渲染消费节奏区块', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 真实网络请求必须放在 runAsync 里，否则 FakeAsync 时钟不会推进
    final response = (await tester.runAsync(() async {
      await AuthService.login(rhythmUser, password);
      return InsightService.rhythm(current);
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RhythmSection(data: response, loading: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('消费节奏分析'), findsOneWidget);
    expect(find.text('¥600.00'), findsWidgets);
    expect(find.text('星期分布'), findsOneWidget);
    expect(find.text('月内阶段'), findsOneWidget);
    expect(find.text('最高消费星期'), findsOneWidget);
    expect(find.byType(RhythmCard), findsOneWidget);
  });

  testWidgets('Case 9：真实数据下数据不足与空账号显示引导', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final responses = (await tester.runAsync(() async {
      await AuthService.login(thinUser, password);
      final thin = await InsightService.rhythm(current);
      await AuthService.login(emptyUser, password);
      final empty = await InsightService.rhythm(current);
      return [thin, empty];
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RhythmSection(data: responses[0], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('消费记录不足'), findsOneWidget);
    expect(find.text('需要更多消费日期后分析节奏'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: RhythmSection(data: responses[1], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本月暂无支出记录'), findsOneWidget);
  });
}

/// 在当月第 day 天记一笔支出（day 一定不大于今天）
Future<void> _create(DateTime now, int day, String amount) async {
  await BillService.create(
    type: 1,
    amount: amount,
    category: '餐饮',
    billDate: Formatters.apiDate(DateTime(now.year, now.month, day)),
    merchant: '节奏联调',
  );
}

String _monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

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
