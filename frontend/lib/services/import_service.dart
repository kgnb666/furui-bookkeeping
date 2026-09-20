import 'package:campus_ledger/models/import_preview.dart';
import 'package:campus_ledger/services/api_client.dart';

/// 账单导入：预览、确认、导入历史
class ImportService {
  ImportService._();

  static Future<ImportPreview> preview({
    required String source,
    required List<int> bytes,
    required String fileName,
  }) async {
    final data = await ApiClient.upload(
      '/bills/import/preview',
      bytes: bytes,
      fileName: fileName,
      fields: {'source': source},
    ) as Map<String, dynamic>;
    return ImportPreview.fromJson(data);
  }

  static Future<ImportResult> confirm({
    required String source,
    required String fileName,
    required int totalCount,
    required List<ImportPreviewItem> items,
  }) async {
    final data = await ApiClient.post('/bills/import/confirm', body: {
      'source': source,
      'fileName': fileName,
      'totalCount': totalCount,
      'items': items.map((item) => item.toConfirmJson()).toList(),
    }) as Map<String, dynamic>;
    return ImportResult.fromJson(data);
  }

  static Future<List<ImportBatch>> batches() async {
    final data = await ApiClient.get('/bills/import/batches') as List<dynamic>;
    return data.map((item) => ImportBatch.fromJson(item as Map<String, dynamic>)).toList();
  }
}
