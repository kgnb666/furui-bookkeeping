import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/services/statistics_service.dart';
import 'package:campus_ledger/utils/money.dart';

/// 统计与预算的真实联调测试：需要一个已启动的后端（Spring Boot + MySQL）。
/// 后端未启动时用例会被标记为 skipped。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const month = '2026-09';
  const emptyMonth = '2026-07';
  final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
  final userA = 'stage4a_$suffix';
  final userB = 'stage4b_$suffix';
  const password = '123456';
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），统计与预算联调用例将被跳过。');
      return;
    }
    // 准备一批金额固定的账单，便于人工核算统计结果
    await AuthService.register(username: userA, password: password, nickname: '统计测试');
    await AuthService.login(userA, password);
    await BillService.create(type: 1, amount: '50.00', category: '餐饮', billDate: '2026-09-05', merchant: '食堂');
    await BillService.create(type: 1, amount: '20.00', category: '交通', billDate: '2026-09-05', merchant: '地铁');
    await BillService.create(type: 1, amount: '30.00', category: '餐饮', billDate: '2026-09-06', merchant: '外卖');
    await BillService.create(type: 2, amount: '500.00', category: '生活费', billDate: '2026-09-06', merchant: '家长转账');
    // 不计收支：任何统计里都不应该出现这 200 元
    await BillService.create(type: 3, amount: '200.00', category: '转账', billDate: '2026-09-07', merchant: '同学');
  });

  test('月度概览与账单明细一致，且不计收支不计入', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    final monthly = await StatisticsService.monthly(month);
    expect(monthly.income, '500.00');
    expect(monthly.expense, '100.00');
    expect(monthly.balance, '400.00', reason: '500 - 100，不含 200 的不计收支');

    // 用账单列表核对（列表里 type=1 也不含不计收支）
    final bills = await BillService.list(month: month, type: 1, size: 100);
    final expenseFromBills = Money.sum(bills.list.map((bill) => bill.amount));
    expect(expenseFromBills, monthly.expense);

    final all = await BillService.list(month: month, size: 100);
    expect(all.total, 5, reason: '一共 5 条账单');
  });

  test('分类统计的金额与占比正确并排除不计收支', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    final categories = await StatisticsService.category(month);
    expect(categories.length, 2);
    expect(categories[0].category, '餐饮');
    expect(categories[0].amount, '80.00');
    expect(categories[0].percentage, 80.00);
    expect(categories[1].category, '交通');
    expect(categories[1].amount, '20.00');
    expect(categories[1].percentage, 20.00);

    final sum = Money.sum(categories.map((item) => item.amount));
    expect(sum, '100.00');
  });

  test('每日趋势覆盖整月，不计收支当天为 0', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    final daily = await StatisticsService.daily(month);
    expect(daily.length, 30);
    expect(daily[4].date, '2026-09-05');
    expect(daily[4].expense, '70.00', reason: '9 月 5 日：餐饮 50 + 交通 20');
    expect(daily[5].expense, '30.00');
    expect(daily[5].income, '500.00');
    expect(daily[6].expense, '0.00', reason: '9 月 7 日只有不计收支，支出应为 0');
    expect(daily[6].income, '0.00');

    expect(Money.sum(daily.map((item) => item.expense)), '100.00');
  });

  test('来源统计只统计支出，收入与不计收支都不计入', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    final sources = await StatisticsService.source(month);
    expect(sources.length, 1, reason: '测试账号的支出全部来自手动记录');
    expect(sources[0].source, 'MANUAL');
    expect(sources[0].sourceName, '手动记录');
    expect(sources[0].amount, '100.00', reason: '50 + 20 + 30，不含收入 500 与不计收支 200');
    expect(sources[0].percentage, 100.00);

    // 与账单列表逐个来源反算的结果一致
    final bills = await BillService.list(month: month, type: 1, size: 100);
    final manualAmount = Money.sum(
      bills.list.where((bill) => bill.source == 'MANUAL').map((bill) => bill.amount),
    );
    expect(manualAmount, sources[0].amount);
  });

  test('来源统计空月份返回空列表', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    expect(await StatisticsService.source(emptyMonth), isEmpty);
  });

  test('空月份返回 0 且不报错', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    final monthly = await StatisticsService.monthly(emptyMonth);
    expect(monthly.income, '0.00');
    expect(monthly.expense, '0.00');
    expect(monthly.balance, '0.00');
    expect(await StatisticsService.category(emptyMonth), isEmpty);
    expect((await StatisticsService.daily(emptyMonth)).length, 31);
  });

  test('预算新增、查询、修改、删除与执行情况', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    var summary = await BudgetService.list(month);
    expect(summary.total, isNull);
    expect(summary.categories, isEmpty);
    expect(summary.monthExpense, '100.00');

    final total = await BudgetService.create(month: month, category: '', amount: '200.00');
    expect(total.amount, '200.00');
    expect(total.used, '100.00', reason: '已使用金额由后端按支出统计');
    expect(total.remaining, '100.00');
    expect(total.usageRate, 50.00);
    expect(total.status, 'NORMAL');

    final food = await BudgetService.create(month: month, category: '餐饮', amount: '50.00');
    expect(food.used, '80.00');
    expect(food.status, 'OVER', reason: '餐饮花了 80，预算 50，应超支');

    summary = await BudgetService.list(month);
    expect(summary.total!.amount, '200.00');
    expect(summary.categories.length, 1);

    final updated = await BudgetService.update(total.id, month: month, category: '', amount: '100.00');
    expect(updated.amount, '100.00');
    expect(updated.status, 'REACHED', reason: '支出 100 等于预算 100');

    await BudgetService.delete(food.id);
    summary = await BudgetService.list(month);
    expect(summary.categories, isEmpty);

    await expectLater(BudgetService.delete(food.id), throwsA(isA<ApiException>()));
  });

  test('预算的重复、非法金额与非法分类都会被拒绝', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    // 重复设置当月总预算（上一条用例已经建过）
    await expectLater(
      BudgetService.create(month: month, category: '', amount: '300.00'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      BudgetService.create(month: month, category: '购物', amount: '0'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      BudgetService.create(month: month, category: '生活费', amount: '100.00'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      BudgetService.create(month: '2026/09', category: '购物', amount: '100.00'),
      throwsA(isA<ApiException>()),
    );
  });

  test('统计与预算都按用户隔离', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    final myBudget = await BudgetService.list(month);

    await AuthService.register(username: userB, password: password);
    await AuthService.login(userB, password);

    final otherMonthly = await StatisticsService.monthly(month);
    expect(otherMonthly.income, '0.00');
    expect(otherMonthly.expense, '0.00', reason: '看不到其他用户的账单');

    final otherBudget = await BudgetService.list(month);
    expect(otherBudget.total, isNull, reason: '看不到其他用户的预算');
    expect(otherBudget.categories, isEmpty);

    final otherSources = await StatisticsService.source(month);
    expect(otherSources, isEmpty, reason: '看不到其他用户的来源统计');

    await expectLater(BudgetService.delete(myBudget.total!.id), throwsA(isA<ApiException>()));
    await AuthService.logout();
  });

  test('统计接口的 token 失效处理与账单接口一致', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    ApiClient.token = 'not-a-valid-token';
    await expectLater(StatisticsService.monthly(month), throwsA(isA<ApiException>()));
    await AuthService.logout();
  });
}

Future<bool> _backendReady() async {
  // 用短超时探测健康检查接口，后端未启动时返回 false，用例转为 skipped
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
