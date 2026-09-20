import 'package:campus_ledger/models/budget.dart';
import 'package:campus_ledger/models/budget_prediction.dart';
import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/services/api_client.dart';

/// 预算接口：已使用金额由后端按账单统计
class BudgetService {
  BudgetService._();

  static Future<BudgetSummary> list(String month) async {
    final data = await ApiClient.get('/budgets', query: {'month': month}) as Map<String, dynamic>;
    return BudgetSummary.fromJson(data);
  }

  /// 预算预测：只对当前月份返回预测结论，其他月份返回 NOT_APPLICABLE
  static Future<BudgetPredictionResponse> predictions(String month) async {
    final data = await ApiClient.get('/budgets/predictions', query: {'month': month});
    if (data is! Map<String, dynamic>) {
      // 服务端返回了非预期结构时按业务错误抛出，避免把类型异常抛给用户
      throw ApiException(500, '预算预测数据格式不正确');
    }
    return BudgetPredictionResponse.fromJson(data);
  }

  static Future<BudgetItem> create({
    required String month,
    required String category,
    required String amount,
  }) async {
    final data = await ApiClient.post('/budgets', body: {
      'month': month,
      'category': category,
      'amount': amount,
    }) as Map<String, dynamic>;
    return BudgetItem.fromJson(data);
  }

  static Future<BudgetItem> update(
    int id, {
    required String month,
    required String category,
    required String amount,
  }) async {
    final data = await ApiClient.put('/budgets/$id', body: {
      'month': month,
      'category': category,
      'amount': amount,
    }) as Map<String, dynamic>;
    return BudgetItem.fromJson(data);
  }

  static Future<void> delete(int id) async {
    await ApiClient.delete('/budgets/$id');
  }
}
