import 'package:flutter/material.dart';

import 'package:campus_ledger/models/import_preview.dart';

/// 导入结果页：成功 / 重复跳过 / 失败
class ImportResultPage extends StatelessWidget {
  const ImportResultPage({super.key, required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入完成')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('导入完成', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _row('成功导入', '${result.importedCount} 条', const Color(0xFF2E9E6B)),
                  _row('重复跳过', '${result.duplicateCount} 条', Colors.grey.shade700),
                  _row('导入失败', '${result.failedCount} 条', theme.colorScheme.error),
                ],
              ),
            ),
          ),
          if (result.failures.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('失败原因', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final reason in result.failures)
                    ListTile(dense: true, title: Text(reason, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('返回账单列表'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
