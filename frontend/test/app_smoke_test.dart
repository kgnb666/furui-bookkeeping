import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/main.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/auth_service.dart';

/// 应用级冒烟测试：验证"启动时是否已登录"这条最基础的链路。
void main() {
  tearDown(() {
    ApiClient.token = null;
    ApiClient.onUnauthorized = null;
  });

  testWidgets('未登录启动时进入登录页', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const CampusLedgerApp());
    await tester.pumpAndSettle();

    expect(find.text('福瑞记账'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.text('没有账号？立即注册'), findsOneWidget);
  });

  testWidgets('本地已有 token 时直接进入主界面', (tester) async {
    SharedPreferences.setMockInitialValues({
      'token': 'fake-token-for-widget-test',
      'user': '{"id":1,"username":"demo","nickname":"小明","email":null,"createdAt":null}',
    });
    await AuthService.loadFromStorage();

    await tester.pumpWidget(const CampusLedgerApp());
    await tester.pump();

    // 底部导航的四个入口应出现
    expect(find.text('首页'), findsWidgets);
    expect(find.text('账单'), findsWidgets);
    expect(find.text('统计'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });
}
