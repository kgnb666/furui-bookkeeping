import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:campus_ledger/utils/formatters.dart';

/// 月份切换：← 2026年09月 →
class MonthSelector extends StatelessWidget {
  const MonthSelector({super.key, required this.month, required this.onChanged});

  /// 格式 yyyy-MM
  final String month;
  final ValueChanged<String> onChanged;

  String _shift(int delta) {
    final parts = month.split('-');
    final year = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    final monthValue = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (year == null || monthValue == null) {
      return month;
    }
    return DateFormat('yyyy-MM').format(DateTime(year, monthValue + delta));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: () => onChanged(_shift(-1)),
          icon: const Icon(Icons.chevron_left),
          tooltip: '上个月',
        ),
        Text(
          Formatters.monthLabel(month),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          onPressed: () => onChanged(_shift(1)),
          icon: const Icon(Icons.chevron_right),
          tooltip: '下个月',
        ),
      ],
    );
  }
}
