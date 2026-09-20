import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/utils/formatters.dart';

/// 预算预测真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
  final user = 's4a_$suffix';
  const password = '123456';
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），预算预测联调用例将被跳过。');
      return;
    }
    await AuthService.register(username: user, password: password, nickname: '预测联调');
    await AuthService.login(user, password);
  });

  test('没有设置预算时返回 NO_BUDGET', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final response = await BudgetService.predictions(Formatters.currentMonth());

    expect(response.status, 'NO_BUDGET');
    expect(response.items, isEmpty);
    expect(response.message, isNotEmpty);
    expect(response.elapsedDays, greaterThan(0));
    expect(response.daysInMonth, inInclusiveRange(28, 31));
  });

  test('消费不足三天时返回 INSUFFICIENT_DATA 且不给出预测金额', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final month = Formatters.currentMonth();
    await BillService.create(
      type: 1,
      amount: '999.00',
      category: '餐饮',
      billDate: Formatters.today(),
    );
    await BudgetService.create(month: month, category: '', amount: '100.00');

    final response = await BudgetService.predictions(month);

    expect(response.status, 'INSUFFICIENT_DATA');
    final item = response.items.single;
    expect(item.isInsufficient, isTrue);
    expect(item.spent, '999.00');
    expect(item.budgetAmount, '100.00');
    // 数据不足时必须没有预测结论
    expect(item.projected, '0.00');
    expect(item.projectedOver, '0.00');
    expect(item.overDate, isNull);
    expect(item.hasPrediction, isFalse);
  });

  test('消费三天后给出预测，金额与手工算式一致', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final month = Formatters.currentMonth();
    final today = Formatters.today();
    final year = month.substring(0, 4);
    final monthNumber = month.substring(5, 7);
    // 再补两天消费，凑满三天：餐饮累计 500，另加交通 150
    await BillService.create(
        type: 1, amount: '19.00', category: '餐饮', billDate: '$year-$monthNumber-02');
    await BillService.create(
        type: 1, amount: '1.00', category: '餐饮', billDate: '$year-$monthNumber-03');
    await BillService.create(
        type: 1, amount: '150.00', category: '交通', billDate: today);
    await BudgetService.create(month: month, category: '餐饮', amount: '600.00');
    await BudgetService.create(month: month, category: '交通', amount: '300.00');

    final response = await BudgetService.predictions(month);

    expect(response.status, 'OK');

    final food = response.items.firstWhere((item) => item.category == '餐饮');
    expect(food.spent, '1019.00');
    expect(food.spentDays, 3);
    expect(food.hasPrediction, isTrue);
    // 金额保持字符串且格式为两位小数
    expect(food.projected, matches(RegExp(r'^\d+\.\d{2}$')));
    expect(food.dailyAverage, matches(RegExp(r'^\d+\.\d{2}$')));
    // 与后端同一套整数分算式复核：日均 = 已用 ÷ 已过天数，预计 = 日均 × 当月天数
    expect(
      food.projected,
      _expectedProjected(food.spent, response.elapsedDays, response.daysInMonth),
      reason: '预计金额必须等于日均 × 当月天数（整分进位）',
    );
    // 预算 600、已用 1019 时必然超支
    expect(food.willOverBudget, isTrue);
    expect(food.projectedOver, isNot('0.00'));

    final transport = response.items.firstWhere((item) => item.category == '交通');
    expect(transport.spent, '150.00');
    expect(transport.riskLevel, isNotEmpty);
  });

  test('非当前月份返回 NOT_APPLICABLE', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final response = await BudgetService.predictions('2020-01');

    expect(response.status, 'NOT_APPLICABLE');
    expect(response.items, isEmpty);
    expect(response.message, contains('仅支持预测本月'));
  });

  test('非法月份返回 400 且提示为中文', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    try {
      await BudgetService.predictions('2026-13-01');
      fail('非法月份应当抛出业务异常');
    } on ApiException catch (e) {
      expect(e.statusCode, 400);
      expect(e.message, contains('yyyy-MM'));
    }
  });

  test('用户隔离：另一个账号看不到上面的预算预测', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final other = 's4a_other_$suffix';
    final token = ApiClient.token;
    ApiClient.token = null;
    await AuthService.register(username: other, password: password);
    await AuthService.login(other, password);

    final response = await BudgetService.predictions(Formatters.currentMonth());

    expect(response.status, 'NO_BUDGET', reason: '新账号没有预算，不应看到别人的预测');
    expect(response.items, isEmpty);

    ApiClient.token = token;
  });
}

/// 与后端一致的整分算式，避免浮点误差影响断言：
/// 日均（分，四舍五入）= 已用分 ÷ 已过天数；预计 = 日均分 × 当月天数
String _expectedProjected(String spent, int elapsedDays, int daysInMonth) {
  final parts = spent.split('.');
  final spentCents = int.parse(parts[0]) * 100 +
      (parts.length > 1 ? int.parse(parts[1].padRight(2, '0').substring(0, 2)) : 0);
  final dailyCents = (spentCents * 2 + elapsedDays) ~/ (elapsedDays * 2);
  final projectedCents = dailyCents * daysInMonth;
  return '${projectedCents ~/ 100}.${(projectedCents % 100).toString().padLeft(2, '0')}';
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
