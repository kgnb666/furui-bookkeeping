import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/utils/formatters.dart';

/// 周期性支出真实联调：直接请求本地 Spring Boot + MySQL。
/// 后端没启动时用例自动跳过，不影响其余测试。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
  final recurringUser = 's4b_rec_$suffix';
  final emptyUser = 's4b_empty_$suffix';
  final noRecurringUser = 's4b_plain_$suffix';
  final shortHistoryUser = 's4b_short_$suffix';
  const password = '123456';
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），周期支出联调用例将被跳过。');
      return;
    }
    // 账号 A：构造 5 个月周期（每月一次）+ 每周一次的真周期，外加高频噪声
    await AuthService.register(username: recurringUser, password: password, nickname: '周期联调');
    await AuthService.login(recurringUser, password);
    await _seedRecurringData();

    // 账号 B：完全没有账单
    await AuthService.logout();
    await AuthService.register(username: emptyUser, password: password, nickname: '空账号');
    await AuthService.login(emptyUser, password);
    await AuthService.logout();

    // 账号 C：账单多、跨度长，但没有规律（预期 NO_RECURRING）
    await AuthService.register(username: noRecurringUser, password: password, nickname: '无规律');
    await AuthService.login(noRecurringUser, password);
    await _seedNoRecurringData();
    await AuthService.logout();

    // 账号 D：有账单但都集中在最近 20 天（预期 NOT_ENOUGH_HISTORY）
    await AuthService.register(username: shortHistoryUser, password: password, nickname: '历史短');
    await AuthService.login(shortHistoryUser, password);
    await _seedShortHistoryData();
    await AuthService.logout();
  });

  test('Case 1：识别出周期支出且返回 OK', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(recurringUser, password);

    final bills = await InsightService.recurring();

    expect(bills.status, 'OK');
    expect(bills.windowDays, 180);
    expect(bills.items, isNotEmpty);

    // 每月一次的会员应当被识别
    final monthly = bills.items.firstWhere(
      (item) => item.merchant == '腾讯视频VIP',
      orElse: () => throw AssertionError('未识别出每月一次的会员支出'),
    );
    expect(monthly.cycleType, 'MONTHLY');
    expect(monthly.cycleText, '每月一次');
    expect(monthly.sampleCount, greaterThanOrEqualTo(4));
    expect(monthly.averageAmount, matches(RegExp(r'^\d+\.\d{2}$')));
    expect(monthly.confidence, anyOf('HIGH', 'MEDIUM'));
    expect(monthly.reason, isNotEmpty);
    expect(monthly.nextDate, isNotNull);

    // 每周一次的固定通勤也应当被识别
    final weekly = bills.items.where((item) => item.merchant == '城市公交');
    expect(weekly, isNotEmpty, reason: '每周固定通勤应被识别');
    expect(weekly.first.cycleType, 'WEEKLY');

    // 高频噪声不应出现在结果里
    final merchants = bills.items.map((item) => item.merchant).toList();
    expect(merchants, isNot(contains('第一食堂')), reason: '每天吃饭不应被识别为周期');
    expect(merchants, isNot(contains('淘宝')), reason: '随机购物不应被识别为周期');
  });

  test('Case 2：空账号返回 NO_DATA', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final bills = await InsightService.recurring();

    expect(bills.status, 'NO_DATA');
    expect(bills.items, isEmpty);
    expect(bills.message, isNotEmpty);
  });

  test('Case 5：用户隔离——空账号看不到周期账号的账单', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);
    final forB = await InsightService.recurring();

    await AuthService.login(recurringUser, password);
    final forA = await InsightService.recurring();

    expect(forA.items, isNotEmpty);
    expect(forB.items, isEmpty, reason: 'B 不能看到 A 的周期支出');
    expect(forB.status, 'NO_DATA');
  });

  test('Case 6：无可用的周期结果时不返回无效条目', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(emptyUser, password);

    final bills = await InsightService.recurring();

    // 空数据下不产生任何可展示条目，前端据此隐藏区块
    expect(bills.displayable, isEmpty);
  });

  test('Case 3：有足够账单但没有周期时返回 NO_RECURRING', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(noRecurringUser, password);

    final bills = await InsightService.recurring();

    expect(bills.status, 'NO_RECURRING');
    expect(bills.items, isEmpty);
    expect(bills.message, contains('没有发现'));
  });

  test('Case 4：账单历史不足时返回 NOT_ENOUGH_HISTORY', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(shortHistoryUser, password);

    final bills = await InsightService.recurring();

    expect(bills.status, 'NOT_ENOUGH_HISTORY');
    expect(bills.items, isEmpty);
    expect(bills.message, isNotEmpty);
  });

  test('接口按用户返回，不接收前端传入的用户标识', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 参数里只有可选的 type，没有 userId
    await AuthService.login(recurringUser, password);
    final byType = await InsightService.recurring(type: 'EXPENSE');

    expect(byType.status, isNotEmpty);
  });
}

/// 构造账号 A 的账单：真周期 + 高频噪声
Future<void> _seedRecurringData() async {
  final today = DateTime.now();
  String day(int daysAgo) => Formatters.apiDate(today.subtract(Duration(days: daysAgo)));

  // 真周期：每月一次的会员（0/30/60/90/120 天前）
  for (final daysAgo in [0, 30, 60, 90, 120]) {
    await BillService.create(
      type: 1,
      amount: '25.00',
      category: '娱乐',
      billDate: day(daysAgo),
      merchant: '腾讯视频VIP',
    );
  }
  // 真周期：每周一次的通勤（0/7/14/21/28 天前）
  for (final daysAgo in [0, 7, 14, 21, 28]) {
    await BillService.create(
      type: 1,
      amount: '2.00',
      category: '交通',
      billDate: day(daysAgo),
      merchant: '城市公交',
    );
  }
  // 噪声：每天吃饭
  for (var i = 0; i < 40; i++) {
    await BillService.create(
      type: 1,
      amount: '15.00',
      category: '餐饮',
      billDate: day(i),
      merchant: '第一食堂',
    );
  }
  // 噪声：间隔随机的网购
  for (final daysAgo in [3, 19, 44, 52, 77, 101]) {
    await BillService.create(
      type: 1,
      amount: '88.00',
      category: '购物',
      billDate: day(daysAgo),
      merchant: '淘宝',
    );
  }
}

/// 账号 C 的账单：跨度长、笔数够，但每个商户的出现间隔都不规律
Future<void> _seedNoRecurringData() async {
  final today = DateTime.now();
  // 12 个商户，各出现 4~6 次，间隔刻意打乱（2/5/9/13/21/34 天不等）
  const gaps = [2, 5, 9, 13, 21, 34];
  for (var m = 0; m < 12; m++) {
    var daysAgo = 3 + m;
    var index = 0;
    while (daysAgo < 175) {
      await BillService.create(
        type: 1,
        amount: '${30 + m}.00',
        category: '购物',
        billDate: Formatters.apiDate(today.subtract(Duration(days: daysAgo))),
        merchant: '商铺$m',
      );
      daysAgo += gaps[index % gaps.length] + m;
      index++;
    }
  }
}

/// 账号 D 的账单：都集中在最近 20 天，时间跨度不足
Future<void> _seedShortHistoryData() async {
  final today = DateTime.now();
  for (var i = 0; i < 20; i++) {
    await BillService.create(
      type: 1,
      amount: '20.00',
      category: '餐饮',
      billDate: Formatters.apiDate(today.subtract(Duration(days: i))),
      merchant: '食堂',
    );
  }
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
