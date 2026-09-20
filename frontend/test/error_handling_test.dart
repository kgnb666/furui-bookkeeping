import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/config/api_config.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/services/import_service.dart';
import 'package:campus_ledger/utils/formatters.dart';

/// 各状态码在 Flutter 侧最终都会变成中文可读提示（不会把 ClientException 抛给用户）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
  final user = 's5e_$suffix';
  const password = '123456';
  var backendReady = false;

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    backendReady = await _backendReady();
    if (!backendReady) {
      // ignore: avoid_print
      print('后端未启动（http://localhost:8080），异常处理联调用例将被跳过。');
      return;
    }
    await AuthService.register(username: user, password: password);
    await AuthService.login(user, password);
  });

  test('400：参数错误提示来自后端中文文案', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(user, password);
    final error = await _capture(() => BillService.create(
          type: 1,
          amount: '0',
          category: '餐饮',
          billDate: Formatters.today(),
        ));

    expect(error.statusCode, 400);
    expect(error.message, '金额必须大于 0');
  });

  test('404：资源不存在', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(user, password);
    final error = await _capture(() => BillService.detail(99999999));

    expect(error.statusCode, 404);
    expect(error.message, '账单不存在');
  });

  test('409：重复数据', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(user, password);
    final month = Formatters.currentMonth();
    await BudgetService.create(month: month, category: '餐饮', amount: '100.00');
    final error = await _capture(
      () => BudgetService.create(month: month, category: '餐饮', amount: '200.00'),
    );

    expect(error.statusCode, 409);
    expect(error.message, '该分类预算已设置');
  });

  test('413：上传文件过大', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    await AuthService.login(user, password);
    final big = Uint8List(6 * 1024 * 1024);
    final error = await _capture(
      () => ImportService.preview(source: 'WECHAT', bytes: big, fileName: 'big.csv'),
    );

    expect(error.statusCode, 413);
    expect(error.message, contains('文件太大'));
  });

  test('401：登录失效提示（不是异常堆栈）', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    ApiClient.token = 'invalid.token.value';
    final error = await _capture(() => AuthService.loadProfile());
    ApiClient.token = null;

    expect(error.statusCode, 401);
    expect(error.message.contains('登录'), isTrue);
  });

  test('网络不通时提示无法连接服务器', () async {
    if (!backendReady) {
      markTestSkipped('后端未启动');
      return;
    }
    // 指向一个不会响应的端口，模拟后端未启动
    ApiClient.overrideBaseUrl('http://localhost:9/api');
    try {
      final error = await _capture(() => AuthService.loadProfile());
      expect(error.isNetworkError, isTrue);
      expect(error.message, '无法连接服务器，请确认后端已启动');
    } finally {
      ApiClient.overrideBaseUrl(null);
    }
  });
}

Future<ApiException> _capture(Future<dynamic> Function() action) async {
  try {
    await action();
    fail('预期抛出 ApiException，但请求成功了');
  } on ApiException catch (e) {
    return e;
  }
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
