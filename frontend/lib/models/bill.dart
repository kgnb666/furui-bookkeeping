class Bill {
  Bill({
    required this.id,
    required this.type,
    required this.typeName,
    required this.amount,
    required this.category,
    required this.billDate,
    required this.merchant,
    required this.remark,
    required this.source,
    required this.sourceName,
    this.sourceTradeId,
    this.importBatchId,
    this.createdAt,
  });

  final int id;

  /// 1=支出 2=收入 3=不计收支
  final int type;
  final String typeName;

  /// 金额是字符串，前端不做浮点计算
  final String amount;
  final String category;
  final String billDate;
  final String merchant;
  final String remark;
  final String source;
  final String sourceName;
  final String? sourceTradeId;
  final int? importBatchId;
  final String? createdAt;

  bool get isExpense => type == 1;
  bool get isIncome => type == 2;
  bool get isNeutral => type == 3;

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      id: (json['id'] as num).toInt(),
      type: (json['type'] as num).toInt(),
      typeName: json['typeName'] as String? ?? '',
      amount: json['amount'] as String? ?? '0.00',
      category: json['category'] as String? ?? '',
      billDate: json['billDate'] as String? ?? '',
      merchant: json['merchant'] as String? ?? '',
      remark: json['remark'] as String? ?? '',
      source: json['source'] as String? ?? 'MANUAL',
      sourceName: json['sourceName'] as String? ?? '',
      sourceTradeId: json['sourceTradeId'] as String?,
      importBatchId: json['importBatchId'] == null ? null : (json['importBatchId'] as num).toInt(),
      createdAt: json['createdAt'] as String?,
    );
  }
}
