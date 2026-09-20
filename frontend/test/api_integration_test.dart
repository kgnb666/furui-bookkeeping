import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/import_service.dart';
import 'package:campus_ledger/utils/formatters.dart';

/// 真实联调测试：直接请求本地启动的 Spring Boot + MySQL。
/// 后端没启动时用例会被标记为 skipped，不会让 CI/本地测试变红。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
  final userA = 'stage3a_$suffix';
  const password = '123456';
  var backendReady = false;

  setUpAll(() async {
    // flutter_test 默认会把所有 HttpClient 请求伪装成 400，这里恢复成真实网络请求
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），联调用例将被跳过。');
      return;
    }
    await AuthService.register(username: userA, password: password, nickname: '联调测试');
  });

  test('注册后可以登录并获取个人资料', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final user = await AuthService.login(userA, password);
    expect(user.username, userA);

    final profile = await AuthService.loadProfile();
    expect(profile.username, userA);
    expect(profile.nickname, '联调测试');
  });

  test('密码错误与重复用户名都会被拒绝', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await expectLater(
      AuthService.login(userA, 'wrong-password'),
      throwsA(isA<ApiException>()),
    );
    await expectLater(
      AuthService.register(username: userA, password: password),
      throwsA(isA<ApiException>()),
    );
  });

  test('账单增删改查与筛选', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    final today = Formatters.today();

    final first = await BillService.create(
      type: 1,
      amount: '15.00',
      category: '餐饮',
      billDate: today,
      merchant: '食堂',
      remark: '午饭',
    );
    expect(first.amount, '15.00');
    expect(first.source, 'MANUAL');
    expect(first.sourceName, '手动记录');

    // 手动记账允许同一天同金额同商户记两笔
    final second = await BillService.create(
      type: 1,
      amount: '15.00',
      category: '餐饮',
      billDate: today,
      merchant: '食堂',
      remark: '午饭',
    );
    expect(second.id, isNot(first.id));

    final income = await BillService.create(
      type: 2,
      amount: '1500.00',
      category: '生活费',
      billDate: today,
      merchant: '家长转账',
    );
    expect(income.isIncome, isTrue);

    final monthPage = await BillService.list(month: Formatters.currentMonth(), size: 100);
    expect(monthPage.total, greaterThanOrEqualTo(3));

    final expensePage = await BillService.list(type: 1, size: 100);
    expect(expensePage.list.every((bill) => bill.isExpense), isTrue);

    final keywordPage = await BillService.list(keyword: '午饭');
    expect(keywordPage.list.any((bill) => bill.merchant == '食堂'), isTrue);

    final detail = await BillService.detail(first.id);
    expect(detail.merchant, '食堂');

    final updated = await BillService.update(
      first.id,
      type: 1,
      amount: '18.50',
      category: '交通',
      billDate: today,
      merchant: '地铁',
      remark: '通勤',
    );
    expect(updated.amount, '18.50');
    expect(updated.category, '交通');

    await BillService.delete(second.id);
    await expectLater(BillService.detail(second.id), throwsA(isA<ApiException>()));
  });

  test('微信账单预览与确认导入，重复导入会被拦住', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    final bytes = await _sampleBytes('wechat-sample.csv');

    final preview = await ImportService.preview(
      source: 'WECHAT',
      bytes: bytes,
      fileName: 'wechat-sample.csv',
    );
    expect(preview.totalCount, 13);
    expect(preview.failedCount, 0);
    expect(preview.neutralCount, 1);
    expect(preview.duplicateCount, 0);
    expect(preview.selectedItems.length, 12);
    expect(preview.items.first.category, '餐饮');

    final result = await ImportService.confirm(
      source: 'WECHAT',
      fileName: 'wechat-sample.csv',
      totalCount: preview.totalCount,
      items: preview.selectedItems,
    );
    expect(result.importedCount, 12);
    expect(result.duplicateCount, 0);

    final imported = await BillService.list(source: 'WECHAT', size: 100);
    expect(imported.total, 12);
    expect(imported.list.every((bill) => bill.sourceName == '微信'), isTrue);

    final again = await ImportService.preview(
      source: 'WECHAT',
      bytes: bytes,
      fileName: 'wechat-sample.csv',
    );
    expect(again.newCount, 0);
    expect(again.duplicateCount, 12);
  });

  test('支付宝账单可以导入，预览页改过的分类会生效', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    final bytes = await _sampleBytes('alipay-sample.csv');

    final preview = await ImportService.preview(
      source: 'ALIPAY',
      bytes: bytes,
      fileName: 'alipay-sample.csv',
    );
    expect(preview.totalCount, 12);
    expect(preview.neutralCount, 1);
    expect(preview.selectedItems.length, 11);

    // 模拟用户在预览页把自动推荐的分类改成别的
    final target = preview.items.firstWhere((item) => item.merchant.contains('星巴克'));
    expect(target.category, '餐饮');
    target.editableCategory = '生活';

    final result = await ImportService.confirm(
      source: 'ALIPAY',
      fileName: 'alipay-sample.csv',
      totalCount: preview.totalCount,
      items: preview.selectedItems,
    );
    expect(result.importedCount, 11);

    final imported = await BillService.list(source: 'ALIPAY', size: 100);
    expect(imported.total, 11);
    final starBucks = imported.list.firstWhere((bill) => bill.merchant.contains('星巴克'));
    expect(starBucks.category, '生活');
  });

  test('导入历史可以看到自己的导入批次', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    final batches = await ImportService.batches();

    expect(batches.length, greaterThanOrEqualTo(2));
    expect(batches.first.sourceName.isNotEmpty, isTrue);
  });

  test('用户只能访问自己的账单', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);
    final mine = await BillService.list(size: 1);
    final otherBillId = mine.list.first.id;

    final userB = 'stage3b_$suffix';
    await AuthService.register(username: userB, password: password);
    await AuthService.login(userB, password);

    await expectLater(BillService.detail(otherBillId), throwsA(isA<ApiException>()));
    final otherList = await BillService.list(size: 100);
    expect(otherList.list.any((bill) => bill.id == otherBillId), isFalse);

    await AuthService.logout();
  });

  test('修改密码后旧密码失效，需要重新登录', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    final userC = 'stage3c_$suffix';
    await AuthService.register(username: userC, password: password);
    await AuthService.login(userC, password);

    await AuthService.changePassword(oldPassword: password, newPassword: 'newpass123');
    await AuthService.logout();
    expect(ApiClient.token, isNull);

    await expectLater(AuthService.login(userC, password), throwsA(isA<ApiException>()));
    final user = await AuthService.login(userC, 'newpass123');
    expect(user.username, userC);

    await AuthService.logout();
  });

  test('token 失效时接口返回 401 并触发重新登录回调', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(userA, password);

    var unauthorizedCalled = false;
    ApiClient.onUnauthorized = () => unauthorizedCalled = true;
    ApiClient.token = 'not-a-valid-token';
    try {
      await expectLater(AuthService.loadProfile(), throwsA(isA<ApiException>()));
      expect(unauthorizedCalled, isTrue, reason: '401 时应触发清除 token 并回登录页的回调');
    } finally {
      ApiClient.onUnauthorized = null;
      await AuthService.logout();
    }
  });
}

Future<bool> _backendReady() async {
  // 用短超时探测健康检查接口：后端没启动时立刻返回 false，用例转为 skipped，
  // 不能沿用 ApiClient 的 30 秒超时，否则整个测试文件会卡住并报失败。
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

Future<List<int>> _sampleBytes(String name) async {
  for (final base in ['../samples', 'samples', '../../samples']) {
    final file = File('$base/$name');
    if (file.existsSync()) {
      return file.readAsBytes();
    }
  }
  throw StateError('找不到样例账单文件：$name');
}
