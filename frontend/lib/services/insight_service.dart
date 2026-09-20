import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/recurring_bill.dart';
import 'package:campus_ledger/models/spending_anomaly.dart';
import 'package:campus_ledger/models/spending_forecast.dart';
import 'package:campus_ledger/models/spending_rhythm.dart';
import 'package:campus_ledger/models/spending_merchant.dart';
import 'package:campus_ledger/models/income_balance.dart';
import 'package:campus_ledger/services/api_client.dart';

/// 智能能力接口：分类推荐与消费洞察。
/// 两者都只读取当前登录用户自己的历史账单，前端不传用户标识。
class InsightService {
  InsightService._();

  /// 根据商户与备注推荐分类。收支类型用 1/2/3 或 EXPENSE/INCOME/NEUTRAL。
  static Future<CategoryRecommend> recommend({
    required int type,
    String merchant = '',
    String note = '',
  }) async {
    final data = await ApiClient.get('/categories/recommend', query: {
      'type': type.toString(),
      'merchant': merchant.isEmpty ? null : merchant,
      'note': note.isEmpty ? null : note,
    }) as Map<String, dynamic>;
    return CategoryRecommend.fromJson(data);
  }

  /// 某个月的消费洞察
  static Future<MonthlyInsights> monthly(String month) async {
    final data = await ApiClient.get('/insights/monthly', query: {'month': month})
        as Map<String, dynamic>;
    return MonthlyInsights.fromJson(data);
  }

  /// 周期性账单识别：分析最近 180 天的支出，找出可能的周期消费。
  /// 与月份无关（跨月模式），因此不传 month 参数。
  static Future<RecurringBills> recurring({String? type}) async {
    final data = await ApiClient.get('/insights/recurring', query: {'type': type});
    if (data is! Map<String, dynamic>) {
      throw ApiException(500, '周期性支出数据格式不正确');
    }
    return RecurringBills.fromJson(data);
  }

  /// 消费异常检测：对比指定月份与它之前的 3 个自然月，找出偏离常态的消费。
  /// 与消费洞察一样按月份查询，只允许最近 12 个自然月（超出时后端返回 400）。
  static Future<AnomaliesResponse> anomalies(String month) async {
    final data = await ApiClient.get('/insights/anomalies', query: {'month': month});
    if (data is! Map<String, dynamic>) {
      throw ApiException(500, '消费异常数据格式不正确');
    }
    return AnomaliesResponse.fromJson(data);
  }

  /// 下月支出预估：按最近 3 个「有支出的完整自然月」加权，预估下个月的支出总额。
  /// 只对当前月份返回结论，其他月份返回 NOT_APPLICABLE；用户身份由 JWT 决定，不传 userId。
  static Future<SpendingForecastResponse> forecast(String month) async {
    final data = await ApiClient.get('/insights/forecast', query: {'month': month});
    if (data is! Map<String, dynamic>) {
      throw ApiException(500, '下月预估数据格式不正确');
    }
    return SpendingForecastResponse.fromJson(data);
  }

  /// 消费节奏分析：分析参考月里"钱花在什么时候"（星期分布与月内阶段分布）。
  /// 只对当前月份给出结论，其他月份返回 NOT_APPLICABLE；用户身份由 JWT 决定，不传 userId。
  static Future<SpendingRhythmResponse> rhythm(String month) async {
    final data = await ApiClient.get('/insights/rhythm', query: {'month': month});
    if (data is! Map<String, dynamic>) {
      throw ApiException(500, '消费节奏数据格式不正确');
    }
    return SpendingRhythmResponse.fromJson(data);
  }

  /// 消费对象分析：回答"我的钱主要花在哪些商户"。
  /// 只分析当前月份的支出明细，按消费对象聚合金额与笔数；用户身份由 JWT 决定，不传 userId。
  static Future<SpendingMerchantResponse> merchants(String month) async {
    final data = await ApiClient.get('/insights/merchants', query: {'month': month});
    if (data is! Map<String, dynamic>) {
      throw ApiException(500, '消费对象数据格式不正确');
    }
    return SpendingMerchantResponse.fromJson(data);
  }

  /// 收支结余分析：回答"我这个月存下了多少"（收入、支出、结余、结余率与收入结构）。
  /// 只分析当前月份；没有收入记录时后端返回 NO_INCOME_DATA，不编造结余率。
  static Future<IncomeBalanceResponse> balance(String month) async {
    final data = await ApiClient.get('/insights/balance', query: {'month': month});
    if (data is! Map<String, dynamic>) {
      throw ApiException(500, '收支结余数据格式不正确');
    }
    return IncomeBalanceResponse.fromJson(data);
  }
}
