import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/models/source_statistics.dart';
import 'package:campus_ledger/services/api_client.dart';

/// 统计接口：统计口径全部由后端决定（只算收入与支出，不计收支不参与）
class StatisticsService {
  StatisticsService._();

  static Future<MonthlyStat> monthly(String month) async {
    final data = await ApiClient.get('/statistics/monthly', query: {'month': month}) as Map<String, dynamic>;
    return MonthlyStat.fromJson(data);
  }

  static Future<List<CategoryStat>> category(String month) async {
    final data = await ApiClient.get('/statistics/category', query: {'month': month}) as List<dynamic>;
    return data.map((item) => CategoryStat.fromJson(item as Map<String, dynamic>)).toList();
  }

  static Future<List<DailyStat>> daily(String month) async {
    final data = await ApiClient.get('/statistics/daily', query: {'month': month}) as List<dynamic>;
    return data.map((item) => DailyStat.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// 支付来源统计（只算支出，不含不计收支与收入）
  static Future<List<SourceStat>> source(String month) async {
    final data = await ApiClient.get('/statistics/source', query: {'month': month}) as List<dynamic>;
    return data.map((item) => SourceStat.fromJson(item as Map<String, dynamic>)).toList();
  }

  /// 某天的收支合计，不传日期时由后端按服务器当天计算
  static Future<DailySummary> dailySummary({String? date}) async {
    final data = await ApiClient.get('/statistics/daily-summary', query: {'date': date}) as Map<String, dynamic>;
    return DailySummary.fromJson(data);
  }

  /// 消费趋势：本月与上月支出对比
  static Future<TrendStat> trends(String month) async {
    final data = await ApiClient.get('/statistics/trends', query: {'month': month}) as Map<String, dynamic>;
    return TrendStat.fromJson(data);
  }
}
