import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/pages/home_page.dart';
import 'package:campus_ledger/pages/statistics_page.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/widgets/insight_list.dart';

http.Response _json(Object body, {int status = 200}) {
  return http.Response(jsonEncode(body), status,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

http.Response _ok(Object data) => _json({'code': 0, 'message': 'success', 'data': data});

Map<String, dynamic> _insightsPayload({List<Map<String, dynamic>>? insights, String summary = ''}) {
  return {
    'month': '2026-09',
    'expense': '1886.50',
    'income': '2000.00',
    'balance': '113.50',
    'expenseChangePercent': '12.30',
    'topCategory': '餐饮',
    'topCategoryPercent': '42.00',
    'summary': summary.isEmpty ? '本月支出 ¥1886.50，比上月 ↑12.30%，餐饮是主要支出类别。' : summary,
    'insights': insights ?? const [],
  };
}

/// 统计页需要的全部接口，按路径分发；不认识的路径返回空数组避免异常
http.Client _statisticsClient({Map<String, dynamic>? insights, int insightsStatus = 200}) {
  return MockClient((request) async {
    final path = request.url.path;
    // 统计页也会请求预算预测，这里统一返回"没有预算"，避免真实网络调用
    if (path.endsWith('/budgets/predictions')) {
      return _ok({
        'month': '2026-09',
        'status': 'NO_BUDGET',
        'message': '本月还没有设置预算，设置后可以预测月末支出',
        'elapsedDays': 17,
        'daysInMonth': 30,
        'daysLeft': 13,
        'items': const [],
      });
    }
    if (path.endsWith('/insights/monthly')) {
      if (insightsStatus != 200) {
        return _json({'code': 500, 'message': '服务器开小差了，请稍后重试', 'data': null}, status: 500);
      }
      return _ok(insights ?? _insightsPayload());
    }
    if (path.endsWith('/statistics/monthly')) {
      return _ok({
        'month': '2026-09',
        'income': '2000.00',
        'expense': '1886.50',
        'balance': '113.50',
      });
    }
    if (path.endsWith('/statistics/category')) {
      return _ok([
        {'category': '餐饮', 'amount': '792.00', 'percentage': 42.0},
      ]);
    }
    if (path.endsWith('/statistics/source')) {
      return _ok([
        {'source': 'WECHAT', 'sourceName': '微信', 'amount': '1000.00', 'percentage': 53.0},
      ]);
    }
    if (path.endsWith('/statistics/daily')) {
      return _ok([
        {'date': '2026-09-16', 'income': '0.00', 'expense': '15.00'},
      ]);
    }
    if (path.endsWith('/budgets')) {
      return _json({'code': 404, 'message': '没有设置预算', 'data': null}, status: 404);
    }
    return _ok(const []);
  });
}

http.Client _homeClient({Map<String, dynamic>? insights}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/budgets/predictions')) {
      return _ok({
        'month': '2026-09',
        'status': 'NO_BUDGET',
        'message': '本月还没有设置预算，设置后可以预测月末支出',
        'elapsedDays': 17,
        'daysInMonth': 30,
        'daysLeft': 13,
        'items': const [],
      });
    }
    if (path.endsWith('/insights/monthly')) {
      return _ok(insights ?? _insightsPayload());
    }
    if (path.endsWith('/statistics/daily-summary')) {
      return _ok({'date': '2026-09-16', 'income': '0.00', 'expense': '15.00'});
    }
    if (path.endsWith('/statistics/monthly')) {
      return _ok({
        'month': '2026-09',
        'income': '2000.00',
        'expense': '1886.50',
        'balance': '113.50',
      });
    }
    if (path.endsWith('/statistics/trends')) {
      return _ok({
        'month': '2026-09',
        'currentExpense': '1886.50',
        'currentIncome': '2000.00',
        'previousMonth': '2026-08',
        'previousExpense': '1680.00',
        'previousHasData': true,
        'expenseChangePercent': '12.30',
      });
    }
    if (path.endsWith('/bills')) {
      return _ok({'total': 0, 'page': 1, 'size': 5, 'list': const []});
    }
    return _ok(const {});
  });
}

Map<String, dynamic> _insight(String type, String title, String message) {
  return {
    'type': type,
    'priority': 1,
    'level': type.startsWith('BUDGET') ? 'WARNING' : 'INFO',
    'title': title,
    'message': message,
    'amount': '0.00',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'fake-token',
      'user': '{"id":1,"username":"demo","nickname":"小明","email":null,"createdAt":null}',
    });
  });

  tearDown(() {
    ApiClient.testClient = null;
    ApiClient.token = null;
  });

  // ==================== 洞察卡片 ====================

  testWidgets('洞察列表按规则展示多条结论', (tester) async {
    final insights = [
      Insight.fromJson(_insight('BUDGET_OVER', '预算提醒', '餐饮 已超过本月预算（已使用 150%）')),
      Insight.fromJson(_insight('BIG_EXPENSE', '消费提醒', '发现一笔较高金额消费：数码店 ¥300.00')),
      Insight.fromJson(_insight('CATEGORY_FOCUS', '消费重点', '本月支出主要集中在 餐饮，占总支出的 42%')),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: InsightList(insights: insights))),
    ));

    expect(find.text('预算提醒'), findsOneWidget);
    expect(find.textContaining('已超过本月预算'), findsOneWidget);
    expect(find.text('消费提醒'), findsOneWidget);
    expect(find.textContaining('发现一笔较高金额消费'), findsOneWidget);
    expect(find.text('消费重点'), findsOneWidget);
    expect(find.textContaining('占总支出的 42%'), findsOneWidget);
  });

  testWidgets('没有洞察时给出友好说明', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: InsightList(insights: [])),
    ));

    expect(find.textContaining('记账一段时间后这里会给出消费分析'), findsOneWidget);
  });

  // ==================== 统计页洞察区域 ====================

  testWidgets('统计页展示本月消费洞察与摘要', (tester) async {
    ApiClient.testClient = _statisticsClient(insights: _insightsPayload(insights: [
      _insight('SPENDING_CHANGE', '消费变化', '本月支出比上月增加 206.50 元（+12.30%）'),
      _insight('CATEGORY_FOCUS', '消费重点', '本月支出主要集中在 餐饮，占总支出的 42%'),
    ]));

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.text('本月消费洞察'), findsOneWidget);
    expect(find.textContaining('餐饮是主要支出类别'), findsOneWidget);
    expect(find.text('消费变化'), findsOneWidget);
    expect(find.textContaining('增加 206.50'), findsOneWidget);
    expect(find.text('消费重点'), findsOneWidget);
  });

  testWidgets('统计页没有洞察时展示引导文案', (tester) async {
    ApiClient.testClient = _statisticsClient(insights: _insightsPayload(summary: '本月还没有支出记录'));

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    expect(find.text('本月消费洞察'), findsOneWidget);
    expect(find.textContaining('记账一段时间后这里会给出消费分析'), findsOneWidget);
  });

  testWidgets('洞察接口失败时统计页主体仍正常展示', (tester) async {
    ApiClient.testClient = _statisticsClient(insightsStatus: 500);

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();

    // 统计主体照常，洞察区域退化为引导文案
    expect(find.text('本月消费洞察'), findsOneWidget);
    expect(find.textContaining('记账一段时间后这里会给出消费分析'), findsOneWidget);
    expect(find.textContaining('1886.50'), findsWidgets);
  });

  testWidgets('统计页切换月份会重新获取洞察', (tester) async {
    final requested = <String>[];
    ApiClient.testClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/insights/monthly')) {
        requested.add(request.url.queryParameters['month'] ?? '');
        return _ok(_insightsPayload());
      }
      if (path.endsWith('/statistics/monthly')) {
        return _ok({
          'month': '2026-09',
          'income': '2000.00',
          'expense': '1886.50',
          'balance': '113.50',
        });
      }
      if (path.endsWith('/budgets')) {
        return _json({'code': 404, 'message': '无预算', 'data': null}, status: 404);
      }
      return _ok(const []);
    });

    await tester.pumpWidget(const MaterialApp(home: StatisticsPage()));
    await tester.pumpAndSettle();
    expect(requested.length, 1);

    // 点月份选择器的上一个月
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(requested.length, 2, reason: '切换月份必须重新获取洞察');
    expect(requested.last, isNot(requested.first));
  });

  // ==================== 首页摘要 ====================

  testWidgets('首页展示本月消费概览摘要', (tester) async {
    ApiClient.testClient = _homeClient();
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);

    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    // 首页新增了预算预测区域，摘要卡片位置下移，先滚动到可见位置
    await tester.scrollUntilVisible(find.byKey(const ValueKey('home-insight-summary')), 200);
    expect(find.text('本月消费概览'), findsOneWidget);
    expect(find.textContaining('餐饮是主要支出类别'), findsOneWidget);
    expect(find.text('查看消费分析'), findsOneWidget);
    // 首页也有趋势提示
    expect(find.textContaining('本月支出相比上月'), findsOneWidget);
  });

  testWidgets('首页点击查看消费分析会跳转到统计页', (tester) async {
    ApiClient.testClient = _homeClient();
    final refresh = ValueNotifier<int>(0);
    var opened = false;
    addTearDown(refresh.dispose);

    await tester.pumpWidget(MaterialApp(
      home: HomePage(
        refresh: refresh,
        onOpenBills: () {},
        onOpenStatistics: () => opened = true,
      ),
    ));
    await tester.pumpAndSettle();

    // 首页内容较长，先滚动到摘要卡片再点击卡片本体
    final card = find.byKey(const ValueKey('home-insight-summary'));
    await tester.scrollUntilVisible(card, 200);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('洞察接口失败时首页仍展示今日与本月数据', (tester) async {
    ApiClient.testClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/insights/monthly')) {
        return _json({'code': 500, 'message': '服务器开小差了，请稍后重试', 'data': null}, status: 500);
      }
      if (path.endsWith('/statistics/daily-summary')) {
        return _ok({'date': '2026-09-16', 'income': '0.00', 'expense': '15.00'});
      }
      if (path.endsWith('/statistics/monthly')) {
        return _ok({
          'month': '2026-09',
          'income': '2000.00',
          'expense': '1886.50',
          'balance': '113.50',
        });
      }
      if (path.endsWith('/statistics/trends')) {
        return _ok({
          'month': '2026-09',
          'currentExpense': '1886.50',
          'currentIncome': '2000.00',
          'previousMonth': '2026-08',
          'previousExpense': '0.00',
          'previousHasData': false,
        });
      }
      if (path.endsWith('/bills')) {
        return _ok({'total': 0, 'page': 1, 'size': 5, 'list': const []});
      }
      return _ok(const {});
    });

    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);
    await tester.pumpWidget(MaterialApp(
      home: HomePage(refresh: refresh, onOpenBills: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('¥15.00'), findsOneWidget);
    expect(find.textContaining('1886.50'), findsWidgets);
    // 洞察取不到时不显示摘要卡片，也不报错
    expect(find.text('本月消费概览'), findsNothing);
    expect(find.text('暂无对比数据'), findsOneWidget);
  });

  test('洞察模型解析与警告级别判断', () {
    final parsed = MonthlyInsights.fromJson(_insightsPayload(insights: [
      _insight('BUDGET_WARNING', '预算提醒', '餐饮 预算已使用 86%，请注意剩余预算'),
    ]));

    expect(parsed.month, '2026-09');
    expect(parsed.hasInsights, isTrue);
    expect(parsed.insights.single.isWarning, isTrue);
    expect(parsed.topCategory, '餐饮');
    expect(parsed.summary, contains('本月支出'));
  });
}
