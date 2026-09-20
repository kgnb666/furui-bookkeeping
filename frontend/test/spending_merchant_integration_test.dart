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
import 'package:campus_ledger/widgets/merchant_card.dart';

/// 消费对象分析真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final suffix = now.millisecondsSinceEpoch % 1000000;
  final okUser = 's4f3_ok_$suffix';
  final thinUser = 's4f3_thin_$suffix';
  final emptyUser = 's4f3_empty_$suffix';
  final unknownUser = 's4f3_unk_$suffix';
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
      print('后端未启动（http://localhost:8080），消费对象联调用例将被跳过。');
      return;
    }

    // 账号 A：三天、两个消费对象（食堂 700 / 超市 300）
    await AuthService.register(username: okUser, password: password, nickname: '对象样本');
    await AuthService.login(okUser, password);
    await _create(now, 1, '400.00', '食堂');
    await _create(now, 2, '300.00', '食堂');
    await _create(now, 3, '200.00', '超市');
    await _create(now, 3, '100.00', '超市');
    await AuthService.logout();

    // 账号 B：只有一天（预期 INSUFFICIENT_DATA）
    await AuthService.register(username: thinUser, password: password, nickname: '一天样本');
    await AuthService.login(thinUser, password);
    await _create(now, 1, '100.00', '食堂');
    await _create(now, 1, '100.00', '超市');
    await AuthService.logout();

    // 账号 C：没有账单（预期 NO_DATA）
    await AuthService.register(username: emptyUser, password: password, nickname: '空账号');
    await AuthService.login(emptyUser, password);
    await AuthService.logout();

    // 账号 D：含一笔未填写消费对象的支出（800 / 1000）
    await AuthService.register(username: unknownUser, password: password, nickname: '未填写样本');
    await AuthService.login(unknownUser, password);
    await _create(now, 1, '100.00', '食堂');
    await _create(now, 2, '100.00', '超市');
    await _create(now, 3, '800.00', null);
    await AuthService.logout();
  });

  test('Case 1：正常数据返回 OK 且总览指标正确', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final response = await InsightService.merchants(current);

    expect(response.status, 'OK');
    expect(response.month, current);
    expect(response.totalAmount, '1000.00');
    expect(response.totalCount, 4);
    expect(response.averageAmount, '250.00');
    expect(response.merchantCount, 2);
    expect(response.merchantCoverage, '100.00');
    expect(response.top3Concentration, '100.00');
    expect(response.coverageText, '已有 100% 支出记录填写消费对象');
  });

  test('Case 2：多个消费对象按金额降序并带笔数与占比', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final response = await InsightService.merchants(current);
    final names = response.topMerchants.map((item) => item.merchantName).toList();

    expect(names, ['食堂', '超市']);
    final first = response.topMerchants.first;
    expect(first.amountText, '¥700.00');
    expect(first.count, 2);
    expect(first.percentageText, '70%');
    expect(response.topMerchants[1].percentageText, '30%');
    expect(response.summary, contains('支出主要集中在'));
  });

  test('Case 3：未填写消费对象时返回金额与占比提示', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(unknownUser, password);

    final response = await InsightService.merchants(current);

    expect(response.status, 'OK');
    expect(response.totalAmount, '1000.00');
    expect(response.unknownMerchantAmount, '800.00');
    expect(response.unknownMerchantRate, '80.00');
    expect(response.merchantCoverage, '66.67');
    expect(response.unknownText, '还有 80% 支出未填写消费对象');
    expect(response.summary, contains('未填写交易对象'));
  });

  test('Case 4：空账号返回 NO_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final response = await InsightService.merchants(current);

    expect(response.status, 'NO_DATA');
    expect(response.totalAmount, '0.00');
    expect(response.totalCount, 0);
    expect(response.topMerchants, isEmpty);
  });

  test('Case 5：只有一天消费时返回 INSUFFICIENT_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(thinUser, password);

    final response = await InsightService.merchants(current);

    expect(response.status, 'INSUFFICIENT_DATA');
    expect(response.totalAmount, '200.00');
    expect(response.totalCount, 2);
    expect(response.topMerchants, isEmpty);
  });

  test('Case 6：历史月份与未来月份都返回 NOT_APPLICABLE', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    final past = await InsightService.merchants(previous);
    final future = await InsightService.merchants(next);

    expect(past.status, 'NOT_APPLICABLE');
    expect(future.status, 'NOT_APPLICABLE');
    expect(past.topMerchants, isEmpty);
  });

  test('Case 7：用户隔离——空账号看不到有数据账号的消费对象', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);
    final forC = await InsightService.merchants(current);

    await AuthService.login(okUser, password);
    final forA = await InsightService.merchants(current);

    expect(forA.status, 'OK');
    expect(forC.status, 'NO_DATA');
    expect(forC.totalAmount, '0.00');
    expect(forC.topMerchants, isEmpty);
  });

  test('Case 8：非法月份返回业务错误', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(okUser, password);

    await expectLater(
      InsightService.merchants('2026-9'),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('Case 9：用真实数据渲染消费对象区块', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 真实网络请求必须放在 runAsync 里，否则 FakeAsync 时钟不会推进
    final response = (await tester.runAsync(() async {
      await AuthService.login(okUser, password);
      return InsightService.merchants(current);
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MerchantSection(data: response, loading: false),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('消费对象分析'), findsOneWidget);
    expect(find.text('看看你的钱主要花给谁'), findsOneWidget);
    expect(find.text('¥1000.00'), findsOneWidget);
    expect(find.text('消费对象排行'), findsOneWidget);
    expect(find.text('食堂'), findsOneWidget);
    expect(find.text('¥700.00'), findsOneWidget);
    expect(find.byType(MerchantCard), findsOneWidget);
  });

  testWidgets('Case 10：真实数据下数据不足与空账号显示引导', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final responses = (await tester.runAsync(() async {
      await AuthService.login(thinUser, password);
      final thin = await InsightService.merchants(current);
      await AuthService.login(emptyUser, password);
      final empty = await InsightService.merchants(current);
      return [thin, empty];
    }))!;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MerchantSection(data: responses[0], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('消费记录不足'), findsOneWidget);
    expect(find.text('记录更多消费对象后即可分析'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: MerchantSection(data: responses[1], loading: false)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('本月暂无支出记录'), findsOneWidget);
  });
}

/// 在当月第 day 天记一笔支出（day 一定不大于今天）；merchant 为 null 表示不填写消费对象
Future<void> _create(DateTime now, int day, String amount, String? merchant) async {
  await BillService.create(
    type: 1,
    amount: amount,
    category: '餐饮',
    billDate: Formatters.apiDate(DateTime(now.year, now.month, day)),
    merchant: merchant ?? '',
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
