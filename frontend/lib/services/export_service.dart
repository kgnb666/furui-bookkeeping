import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:campus_ledger/services/api_client.dart';

/// 导出结果：文件名与导出条数
class ExportOutcome {
  const ExportOutcome({required this.fileName, required this.count});

  final String fileName;
  final int count;
}

/// 账单导出：CSV / XLSX / JSON。
/// 只导出当前登录用户的数据，范围由后端按 token 决定，前端不传用户标识。
class ExportService {
  ExportService._();

  static const List<String> formats = ['csv', 'xlsx', 'json'];

  static String labelOf(String format) {
    switch (format) {
      case 'xlsx':
        return 'Excel 表格（.xlsx）';
      case 'json':
        return 'JSON 备份（.json）';
      default:
        return 'CSV 表格（.csv）';
    }
  }

  static String mimeOf(String format) {
    switch (format) {
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'json':
        return 'application/json';
      default:
        return 'text/csv';
    }
  }

  /// 拉取导出文件并保存，返回文件名与条数。
  /// [count] 由调用方先查一次列表总数得到，用于结果提示。
  static Future<ExportOutcome> export({
    required String format,
    String? month,
    required int count,
  }) async {
    final result = await ApiClient.download('/bills/export', query: {
      'format': format,
      'month': month,
    });
    await FilePicker.saveFile(
      fileName: result.fileName,
      bytes: Uint8List.fromList(result.bytes),
      mimeType: mimeOf(format),
    );
    return ExportOutcome(fileName: result.fileName, count: count);
  }
}
