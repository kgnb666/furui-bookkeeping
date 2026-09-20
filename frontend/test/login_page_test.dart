import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:campus_ledger/pages/login_page.dart';
import 'package:campus_ledger/pages/register_page.dart';

void main() {
  testWidgets('登录页展示必要元素', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('福瑞记账'), findsOneWidget);
    expect(find.text('记下每一笔 · 收获更好的自己'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
    expect(find.text('没有账号？立即注册'), findsOneWidget);
  });

  testWidgets('登录页空输入会提示错误', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();

    expect(find.text('请输入用户名'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);
  });

  testWidgets('注册页校验两次密码是否一致', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterPage()));

    await tester.enterText(find.widgetWithText(TextFormField, '用户名'), 'abc');
    await tester.enterText(find.widgetWithText(TextFormField, '密码'), '123');
    await tester.enterText(find.widgetWithText(TextFormField, '确认密码'), '456');
    await tester.tap(find.widgetWithText(FilledButton, '注册'));
    await tester.pump();

    expect(find.text('用户名长度需为 4~20 位'), findsOneWidget);
    expect(find.text('密码长度需为 6~20 位'), findsOneWidget);
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
  });
}
