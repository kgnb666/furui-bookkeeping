import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/widgets/bill_form.dart';
import 'package:campus_ledger/widgets/smart_recommend_card.dart';

/// 用假的 HTTP 客户端构造后端响应，测试智能推荐在前端的完整链路：
/// ApiClient → InsightService → BillForm → 卡片展示 → 应用推荐。
http.Client _client(Future<http.Response> Function(http.Request) handler) {
  return MockClient(handler);
}

http.Response _json(Object body, {int status = 200}) {
  return http.Response(jsonEncode(body), status,
      headers: {'content-type': 'application/json; charset=utf-8'});
}

/// 表单在真机上是可滚动的，测试里同样包一层，避免小视口下溢出报错
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// 表单里 TextFormField 的顺序：0=金额，1=商户，2=备注
Finder _field(int index) => find.byType(TextFormField).at(index);

void main() {
  tearDown(() {
    ApiClient.testClient = null;
    ApiClient.token = null;
  });

  testWidgets('填写商户后展示智能推荐分类与原因', (tester) async {
    ApiClient.testClient = _client((request) async {
      expect(request.url.path, endsWith('/categories/recommend'));
      return _json({
        'code': 0,
        'message': 'success',
        'data': {
          'category': '餐饮',
          'confidence': 'HIGH',
          'score': 355,
          'reason': '根据你过去 3 次对该商户的记录',
          'sampleCount': 3,
        },
      });
    });

    BillFormData? submitted;
    await tester.pumpWidget(_host(BillForm(
      submitLabel: '保存',
      onSubmit: (data) async => submitted = data,
    )));

    // 初始没有可依据的文本，只给引导文案，不显示假推荐
    expect(find.text('记录更多账单后，系统会逐渐了解你的消费习惯'), findsOneWidget);

    await tester.enterText(_field(1), '星巴克');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('智能推荐'), findsOneWidget);
    expect(find.text('餐饮'), findsWidgets);
    expect(find.text('根据你过去 3 次对该商户的记录'), findsOneWidget);
    expect(find.text('高可信'), findsOneWidget);
    expect(submitted, isNull);
  });

  testWidgets('点击使用推荐后分类切换到推荐值，仍需用户保存', (tester) async {
    ApiClient.testClient = _client((request) async => _json({
          'code': 0,
          'message': 'success',
          'data': {
            'category': '餐饮',
            'confidence': 'HIGH',
            'score': 355,
            'reason': '根据你过去 8 次对该商户的记录',
            'sampleCount': 8,
          },
        }));

    BillFormData? submitted;
    await tester.pumpWidget(_host(BillForm(
      submitLabel: '保存',
      onSubmit: (data) async => submitted = data,
    )));

    await tester.enterText(_field(1), '喜茶');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '使用推荐'));
    await tester.pumpAndSettle();

    // 应用推荐后卡片收起，分类变成餐饮
    expect(find.text('智能推荐'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '餐饮'), findsOneWidget);
    // 只是填好了分类，还没有保存
    expect(submitted, isNull);

    await tester.enterText(_field(0), '18.00');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted!.category, '餐饮');
  });

  testWidgets('没有历史数据时显示引导而不是虚假推荐', (tester) async {
    ApiClient.testClient = _client((request) async => _json({
          'code': 0,
          'message': 'success',
          'data': {
            'category': null,
            'confidence': 'NONE',
            'score': 0,
            'reason': '暂无足够历史记录',
            'sampleCount': 0,
          },
        }));

    await tester.pumpWidget(_host(BillForm(
      submitLabel: '保存',
      onSubmit: (_) async {},
    )));

    await tester.enterText(_field(1), '没听过的店');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('智能推荐'), findsNothing);
    expect(find.text('记录更多账单后，系统会逐渐了解你的消费习惯'), findsOneWidget);
  });

  testWidgets('推荐接口异常时不影响记账主流程', (tester) async {
    ApiClient.testClient = _client((request) async => _json(
          {'code': 500, 'message': '服务器开小差了', 'data': null},
          status: 500,
        ));

    BillFormData? submitted;
    await tester.pumpWidget(_host(BillForm(
      submitLabel: '保存',
      onSubmit: (data) async => submitted = data,
    )));

    await tester.enterText(_field(1), '星巴克');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // 推荐失败静默降级，表单照常可用
    expect(find.text('记录更多账单后，系统会逐渐了解你的消费习惯'), findsOneWidget);
    await tester.enterText(_field(0), '20.00');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
  });

  testWidgets('推荐卡片展示可信度分级', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SmartRecommendCard(
          loading: false,
          onApply: () {},
          recommend: const CategoryRecommend(
            category: '购物',
            confidence: 'MEDIUM',
            score: 200,
            reason: '根据你过去 2 次对该商户的记录',
            sampleCount: 2,
          ),
        ),
      ),
    ));

    expect(find.text('购物'), findsOneWidget);
    expect(find.text('中等可信'), findsOneWidget);
    expect(find.text('使用推荐'), findsOneWidget);
    expect(find.text('根据你过去 2 次对该商户的记录'), findsOneWidget);
  });

  testWidgets('推荐评估中展示加载提示', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SmartRecommendCard(loading: true, recommend: null)),
    ));

    expect(find.text('正在根据你的记账习惯分析…'), findsOneWidget);
  });

  test('推荐结果为无推荐时的解析与判断', () {
    final none = CategoryRecommend.fromJson({
      'category': null,
      'confidence': 'NONE',
      'score': 0,
      'reason': '暂无足够历史记录',
      'sampleCount': 0,
    });
    expect(none.hasSuggestion, isFalse);
    expect(none.confidenceLabel, isEmpty);
    expect(none.reason, '暂无足够历史记录');

    final low = CategoryRecommend.fromJson({
      'category': '餐饮',
      'confidence': 'LOW',
      'score': 30,
      'reason': '“星巴克”符合内置分类关键词',
      'sampleCount': 0,
    });
    expect(low.hasSuggestion, isTrue);
    expect(low.confidenceLabel, '仅供参考');
  });
}
