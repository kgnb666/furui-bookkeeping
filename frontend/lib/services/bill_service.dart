import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/models/page_result.dart';
import 'package:campus_ledger/services/api_client.dart';
import 'package:campus_ledger/services/ledger_notification_service.dart';

/// 账单接口：增删改查与筛选分页
class BillService {
  BillService._();

  static Future<PageResult<Bill>> list({
    String? month,
    int? type,
    String? category,
    String? source,
    String? keyword,
    String? minAmount,
    String? maxAmount,
    int page = 1,
    int size = 20,
  }) async {
    final data = await ApiClient.get('/bills', query: {
      'month': month,
      'type': type?.toString(),
      'category': category,
      'source': source,
      'keyword': keyword,
      'minAmount': minAmount,
      'maxAmount': maxAmount,
      'page': page,
      'size': size,
    }) as Map<String, dynamic>;
    return PageResult.fromJson(data, Bill.fromJson);
  }

  static Future<Bill> detail(int id) async {
    final data = await ApiClient.get('/bills/$id') as Map<String, dynamic>;
    return Bill.fromJson(data);
  }

  static Future<Bill> create({
    required int type,
    required String amount,
    required String category,
    required String billDate,
    String merchant = '',
    String remark = '',
  }) async {
    final data = await ApiClient.post('/bills', body: {
      'type': type.toString(),
      'amount': amount,
      'category': category,
      'billDate': billDate,
      'merchant': merchant,
      'remark': remark,
    }) as Map<String, dynamic>;
    // 记账后立刻刷新通知栏看板（未开启或无 Android 原生侧时为空操作）
    await LedgerNotificationService.refresh();
    return Bill.fromJson(data);
  }

  static Future<Bill> update(
    int id, {
    required int type,
    required String amount,
    required String category,
    required String billDate,
    String merchant = '',
    String remark = '',
  }) async {
    final data = await ApiClient.put('/bills/$id', body: {
      'type': type.toString(),
      'amount': amount,
      'category': category,
      'billDate': billDate,
      'merchant': merchant,
      'remark': remark,
    }) as Map<String, dynamic>;
    await LedgerNotificationService.refresh();
    return Bill.fromJson(data);
  }

  static Future<void> delete(int id) async {
    await ApiClient.delete('/bills/$id');
    await LedgerNotificationService.refresh();
  }
}
