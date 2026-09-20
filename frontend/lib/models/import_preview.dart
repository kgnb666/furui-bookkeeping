/// 导入预览：总条数与四类数量，以及逐条记录
class ImportPreview {
  ImportPreview({
    required this.source,
    required this.sourceName,
    required this.fileName,
    required this.totalCount,
    required this.newCount,
    required this.duplicateCount,
    required this.neutralCount,
    required this.failedCount,
    required this.items,
  });

  final String source;
  final String sourceName;
  final String fileName;
  final int totalCount;
  final int newCount;
  final int duplicateCount;
  final int neutralCount;
  final int failedCount;
  final List<ImportPreviewItem> items;

  List<ImportPreviewItem> get selectedItems => items.where((item) => item.selected).toList();

  factory ImportPreview.fromJson(Map<String, dynamic> json) {
    return ImportPreview(
      source: json['source'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      newCount: (json['newCount'] as num?)?.toInt() ?? 0,
      duplicateCount: (json['duplicateCount'] as num?)?.toInt() ?? 0,
      neutralCount: (json['neutralCount'] as num?)?.toInt() ?? 0,
      failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => ImportPreviewItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ImportPreviewItem {
  ImportPreviewItem({
    required this.rowIndex,
    required this.billDate,
    required this.sourceTradeTime,
    required this.merchant,
    required this.remark,
    required this.amount,
    required this.type,
    required this.typeName,
    required this.category,
    required this.categoryFrom,
    required this.sourceTradeId,
    required this.duplicate,
    required this.duplicateReason,
    required this.importable,
    required this.defaultSelected,
    required this.failReason,
  });

  final int rowIndex;
  final String billDate;
  final String sourceTradeTime;
  final String merchant;
  final String remark;
  final String amount;
  final int type;
  final String typeName;
  final String category;
  final String categoryFrom;
  final String sourceTradeId;
  final bool duplicate;
  final String? duplicateReason;
  final bool importable;
  final bool defaultSelected;
  final String? failReason;

  /// 用户是否勾选，初值取后端给的 defaultSelected
  bool selected = false;

  /// 用户可以在预览页修改分类
  String editableCategory = '';

  bool get isNeutral => type == 3;

  void initSelection() {
    selected = defaultSelected;
    editableCategory = category;
  }

  Map<String, dynamic> toConfirmJson() => {
        'billDate': billDate,
        'sourceTradeTime': sourceTradeTime,
        'merchant': merchant,
        'remark': remark,
        'amount': amount,
        'type': type.toString(),
        'category': editableCategory,
        'sourceTradeId': sourceTradeId,
      };

  factory ImportPreviewItem.fromJson(Map<String, dynamic> json) {
    final item = ImportPreviewItem(
      rowIndex: (json['rowIndex'] as num?)?.toInt() ?? 0,
      billDate: json['billDate'] as String? ?? '',
      sourceTradeTime: json['sourceTradeTime'] as String? ?? '',
      merchant: json['merchant'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      amount: json['amount'] as String? ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
      typeName: json['typeName'] as String? ?? '',
      category: json['category'] as String? ?? '',
      categoryFrom: json['categoryFrom'] as String? ?? '',
      sourceTradeId: json['sourceTradeId'] as String? ?? '',
      duplicate: json['duplicate'] as bool? ?? false,
      duplicateReason: json['duplicateReason'] as String?,
      importable: json['importable'] as bool? ?? false,
      defaultSelected: json['defaultSelected'] as bool? ?? false,
      failReason: json['failReason'] as String?,
    );
    item.initSelection();
    return item;
  }
}

/// 导入结果
class ImportResult {
  ImportResult({
    required this.batchId,
    required this.totalCount,
    required this.importedCount,
    required this.duplicateCount,
    required this.failedCount,
    required this.failures,
  });

  final int batchId;
  final int totalCount;
  final int importedCount;
  final int duplicateCount;
  final int failedCount;
  final List<String> failures;

  factory ImportResult.fromJson(Map<String, dynamic> json) {
    return ImportResult(
      batchId: (json['batchId'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      importedCount: (json['importedCount'] as num?)?.toInt() ?? 0,
      duplicateCount: (json['duplicateCount'] as num?)?.toInt() ?? 0,
      failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
      failures: (json['failures'] as List<dynamic>? ?? [])
          .map((item) => (item as Map<String, dynamic>)['reason'] as String? ?? '')
          .where((reason) => reason.isNotEmpty)
          .toList(),
    );
  }
}

/// 导入历史
class ImportBatch {
  ImportBatch({
    required this.id,
    required this.source,
    required this.sourceName,
    required this.fileName,
    required this.totalCount,
    required this.importedCount,
    required this.duplicateCount,
    required this.failedCount,
    required this.createdAt,
  });

  final int id;
  final String source;
  final String sourceName;
  final String fileName;
  final int totalCount;
  final int importedCount;
  final int duplicateCount;
  final int failedCount;
  final String createdAt;

  factory ImportBatch.fromJson(Map<String, dynamic> json) {
    return ImportBatch(
      id: (json['id'] as num).toInt(),
      source: json['source'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      importedCount: (json['importedCount'] as num?)?.toInt() ?? 0,
      duplicateCount: (json['duplicateCount'] as num?)?.toInt() ?? 0,
      failedCount: (json['failedCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }
}
