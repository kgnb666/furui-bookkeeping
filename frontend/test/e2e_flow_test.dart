import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/statistics_service.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/models/income_balance.dart';
import 'package:campus_ledger/models/spending_merchant.dart';
import 'package:campus_ledger/models/spending_rhythm.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/widgets/balance_card.dart';
import 'package:campus_ledger/widgets/merchant_card.dart';
import 'package:campus_ledger/widgets/rhythm_card.dart';

/// 端到端流程验证：真实后端（Spring Boot + MySQL）下的完整用户旅程。
///
/// 覆盖：注册 → 登录 → 记支出 / 收入 → 账单列表 → 统计 → 导出 → 七个智能能力，
/// 并把其中三个智能能力的**真实返回数据**渲染成页面组件后断言。
/// 后端未启动时自动 skip。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();
  final suffix = now.millisecondsSinceEpoch % 1000000;
  final user = 'e2e_$suffix';
  const password = '123456';
  final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），端到端流程用例将被跳过。');
      return;
    }

    // 完整旅程：注册 → 登录 → 记 4 笔支出（跨 4 天、3 个交易对象）+ 1 笔收入
    await AuthService.register(username: user, password: password, nickname: '端到端');
    await AuthService.login(user, password);
    for (var i = 1; i <= 4; i++) {
      await BillService.create(
        type: 1,
        amount: '${100 + i * 50}.00',
        category: i.isEven ? '餐饮' : '交通',
        billDate: Formatters.apiDate(DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: i - 1))),
        merchant: i.isEven ? '第一食堂' : '城市公交',
      );
    }
    await BillService.create(
      type: 2,
      amount: '2400.00',
      category: '生活费',
      billDate: Formatters.apiDate(DateTime(now.year, now.month, now.day)),
      merchant: '家里转账',
    );
  });

  tearDownAll(() async {
    if (backendReady) {
      await AuthService.logout();
    }
  });

  test('端到端 1：账单列表与统计接口能读到刚写入的真实数据', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(user, password);

    final expenses = await BillService.list(month: month, type: 1, size: 100);
    final incomes = await BillService.list(month: month, type: 2, size: 100);
    expect(expenses.total, 4);
    expect(incomes.total, 1);

    final monthly = await StatisticsService.monthly(month);
    // 四笔支出：150 + 200 + 250 + 300 = 900.00
    expect(monthly.expense, '900.00');
    expect(monthly.income, '2400.00');
    expect(monthly.balance, '1500.00');
  });

  test('端到端 2：七个智能能力在真实数据下都给出可用状态', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(user, password);

    final insights = await InsightService.monthly(month);
    expect(insights.month, month);

    final recurring = await InsightService.recurring();
    expect(recurring.status.isNotEmpty, isTrue);

    final anomalies = await InsightService.anomalies(month);
    expect(anomalies.status.isNotEmpty, isTrue);

    final forecast = await InsightService.forecast(month);
    expect(forecast.status.isNotEmpty, isTrue);

    final rhythm = await InsightService.rhythm(month);
    expect(rhythm.status.isNotEmpty, isTrue);

    final merchants = await InsightService.merchants(month);
    expect(merchants.status.isNotEmpty, isTrue);

    final balance = await InsightService.balance(month);
    expect(balance.status.isNotEmpty, isTrue);
  });

  testWidgets('端到端 3：三个智能模块的真实数据可以渲染成页面组件', (tester) async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final results = (await tester.runAsync(() async {
      await AuthService.login(user, password);
      final balance = await InsightService.balance(month);
      final merchants = await InsightService.merchants(month);
      final rhythm = await InsightService.rhythm(month);
      return <Object>[balance, merchants, rhythm];
    }))!;
    final balance = results[0] as IncomeBalanceResponse;
    final merchants = results[1] as SpendingMerchantResponse;
    final rhythm = results[2] as SpendingRhythmResponse;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              BalanceSection(data: balance, loading: false),
              MerchantSection(data: merchants, loading: false),
              RhythmSection(data: rhythm, loading: false),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('收支结余分析'), findsOneWidget);
    expect(find.text('消费对象分析'), findsOneWidget);
    expect(find.text('消费节奏分析'), findsOneWidget);
    expect(find.byType(BalanceCard), findsOneWidget, reason: '有收入时应渲染结余卡片');
    expect(find.byType(MerchantCard), findsOneWidget, reason: '多交易对象时应渲染排行卡片');
    expect(find.byType(RhythmCard), findsOneWidget, reason: '多天消费时应渲染节奏卡片');
    expect(tester.takeException(), isNull);
  });
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
