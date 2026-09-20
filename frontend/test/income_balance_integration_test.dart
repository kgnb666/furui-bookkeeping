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
import 'package:campus_ledger/widgets/balance_card.dart';

/// 收支结余分析真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final suffix = now.millisecondsSinceEpoch % 1000000;
  final okUser = 's4g_ok_$suffix';
  final expenseOnlyUser = 's4g_exp_$suffix';
  final emptyUser = 's4g_empty_$suffix';
  const password = '123456';
  final current = _monthKey(now);
  final previous = _monthKey(DateTime(now.year, now.month - 1, 1));
  final next = _monthKey(DateTime(now.year, now.month + 1, 1));
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），收支结余联调用例将被跳过。');
      return;
    }

    // 账号 A：本月收入 3000（生活费 2400 + 兼职 600），支出 1000；上月收入 2000、支出 1000
    await AuthService.register(username: okUser, password: password, nickname: '结余样本');
    await AuthService.login(okUser, password);
    await _create(now, 1, 2, '2400.00', '生活费');
    await _create(now, 2, 2, '600.00', '兼职收入');
    await _create(now, 3, 1, '1000.00', '餐饮');
    await _create(now, 4, 2, '2000.00', '生活费', monthsAgo: 1);
    await _create(now, 5, 1, '1000.00', '餐饮', monthsAgo: 1);
    await AuthService.logout();

    // 账号 B：只有支出，没有收入（预期 NO_INCOME_DATA）
    await AuthService.register(username: expenseOnlyUser, password: password, nickname: '只记支出');
    await AuthService.login(expenseOnlyUser, password);
    await _create(now, 1, 1, '900.00', '餐饮');
    await AuthService.logout();

    // 账号 C：没有任何账单（预期 NO_DATA）
    await AuthService.register(username: emptyUser, password: password, nickname: '空账号');
    await AuthService.login(emptyUser, password);
    await AuthService.logout();
  });

  test('Case 1：有收入有支出时结余与结余率正确', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final response = await InsightService.balance(current);

    expect(response.status, 'OK');
    expect(response.month, current);
    expect(response.incomeAmount, '3000.00');
    expect(response.expenseAmount, '1000.00');
    expect(response.balance, '2000.00');
    expect(response.balanceText, '¥2000.00');
    expect(response.balanceRate, '66.67');
    expect(response.isOverSpent, isFalse);
  });

  test('Case 2：收入结构按分类返回金额与占比', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final response = await InsightService.balance(current);
    final categories = response.incomeItems.map((item) => item.category).toList();

    expect(categories, ['生活费', '兼职收入']);
    expect(response.incomeItems.first.amountText, '¥2400.00');
    expect(response.incomeItems.first.percentageText, '80%');
    expect(response.incomeItems[1].percentageText, '20%');
    expect(response.incomeCount, 2);
  });

  test('Case 3：与上月对比返回多存金额', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final response = await InsightService.balance(current);

    // 本月结余 2000，上月结余 1000 → 多存 1000
    expect(response.hasPreviousData, isTrue);
    expect(response.previousBalance, '1000.00');
    expect(response.balanceChange, '1000.00');
    expect(response.comparisonText, '比上月多存 ¥1000.00');
    expect(response.summary, contains('比上月多存'));
  });

  test('Case 4：空账号返回 NO_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final response = await InsightService.balance(current);

    expect(response.status, 'NO_DATA');
    expect(response.incomeAmount, '0.00');
    expect(response.expenseAmount, '0.00');
    expect(response.incomeItems, isEmpty);
  });

  test('Case 5：只有支出时返回 NO_INCOME_DATA 并保留支出事实', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(expenseOnlyUser, password);

    final response = await InsightService.balance(current);

    expect(response.status, 'NO_INCOME_DATA');
    expect(response.incomeAmount, '0.00');
    expect(response.expenseAmount, '900.00');
    expect(response.balance, '-900.00');
    expect(response.balanceRate, '0.00');
    expect(response.incomeItems, isEmpty);
    expect(response.message, contains('没有收入记录'));
  });

  test('Case 6：历史月份与未来月份都返回 NOT_APPLICABLE', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final past = await InsightService.balance(previous);
    final future = await InsightService.balance(next);

    expect(past.status, 'NOT_APPLICABLE');
    expect(future.status, 'NOT_APPLICABLE');
  });

  test('Case 7：用户隔离——空账号看不到有数据账号的结余', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);
    final forC = await InsightService.balance(current);

    await AuthService.login(okUser, password);
    final forA = await InsightService.balance(current);

    expect(forA.status, 'OK');
    expect(forC.status, 'NO_DATA');
    expect(forC.incomeAmount, '0.00');
    expect(forC.incomeItems, isEmpty);
  });

  test('Case 8：非法月份返回业务错误', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    await expectLater(
      InsightService.balance('2026-9'),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('Case 9：用真实数据渲染收支结余区块', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 真实网络请求必须放在 runAsync 里，否则 FakeAsync 时钟不会推进
    final response = (await tester.runAsync(() async {
      await AuthService.login(okUser, password);
      return InsightService.balance(current);
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BalanceSection(data: response, loading: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('收支结余分析'), findsOneWidget);
    expect(find.text('看看这个月存下了多少'), findsOneWidget);
    expect(find.text('¥3000.00'), findsOneWidget);
    expect(find.text('¥2000.00'), findsOneWidget);
    expect(find.text('收入结构'), findsOneWidget);
    expect(find.text('生活费'), findsOneWidget);
    expect(find.byType(BalanceCard), findsOneWidget);
  });

  testWidgets('Case 10：真实数据下无收入与空账号显示引导', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final responses = (await tester.runAsync(() async {
      await AuthService.login(expenseOnlyUser, password);
      final expenseOnly = await InsightService.balance(current);
      await AuthService.login(emptyUser, password);
      final empty = await InsightService.balance(current);
      return [expenseOnly, empty];
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BalanceSection(data: responses[0], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本月没有收入记录'), findsOneWidget);
    expect(find.text('补记收入后即可计算结余率'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BalanceSection(data: responses[1], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本月暂无收支记录'), findsOneWidget);
  });
}

/// 在 now 的 monthsAgo 个月前的第 day 天记一笔账单（day 一定不大于今天）
Future<void> _create(DateTime now, int day, int type, String amount, String category,
    {int monthsAgo = 0}) async {
  final base = DateTime(now.year, now.month - monthsAgo, 1);
  final lastDay = DateTime(base.year, base.month + 1, 0).day;
  final safeDay = day > lastDay ? lastDay : day;
  await BillService.create(
    type: type,
    amount: amount,
    category: category,
    billDate: Formatters.apiDate(DateTime(base.year, base.month, safeDay)),
    merchant: '结余联调',
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
