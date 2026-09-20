import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:campus_ledger/pages/login_page.dart';
import 'package:campus_ledger/pages/main_shell_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/utils/brand.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.loadFromStorage();
  runApp(const CampusLedgerApp());
}

class CampusLedgerApp extends StatefulWidget {
  const CampusLedgerApp({super.key});

  @override
  State<CampusLedgerApp> createState() => _CampusLedgerAppState();
}

class _CampusLedgerAppState extends State<CampusLedgerApp> {
  @override
  void initState() {
    super.initState();
    // 登录失效时统一回到登录页
    ApiClient.onUnauthorized = _backToLogin;
  }

  void _backToLogin() {
    AuthService.logout();
    appNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      // 关于对话框等系统组件的按钮文案使用中文
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Brand.orange,
          primary: Brand.orange,
          secondary: Brand.green,
        ),
        scaffoldBackgroundColor: Brand.cream,
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: const CardThemeData(
          color: Brand.surface,
          elevation: 0.5,
          margin: EdgeInsets.zero,
        ),
      ),
      home: AuthService.isLoggedIn ? const MainShellPage() : const LoginPage(),
    );
  }
}
