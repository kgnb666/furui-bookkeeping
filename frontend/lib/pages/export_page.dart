import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/export_service.dart';
import 'package:campus_ledger/utils/formatters.dart';

/// 数据导出：选择月份与格式，导出当前登录用户自己的账单。
class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  static const String _allMonths = '全部月份';

  String _month = Formatters.currentMonth();
  String _format = 'csv';
  bool _exporting = false;
  String? _error;

  Future<void> _export() async {
    if (_exporting) {
      return;
    }
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final month = _month == _allMonths ? null : _month;
      // 先取一次总数：既是给用户的结果提示，也提前拦住"没有数据可导出"
      final page = await BillService.list(month: month, page: 1, size: 1);
      if (page.total == 0) {
        if (mounted) {
          setState(() {
            _exporting = false;
            _error = '所选范围内没有账单可以导出';
          });
        }
        return;
      }
      final outcome = await ExportService.export(
        format: _format,
        month: month,
        count: page.total,
      );
      if (!mounted) {
        return;
      }
      setState(() => _exporting = false);
      await _showResult(outcome.fileName, outcome.count);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _exporting = false;
        _error = e.message;
      });
    }
  }

  Future<void> _showResult(String fileName, int count) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 8),
            Text('导出成功'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('文件名称', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            SelectableText(fileName, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            const Text('导出数量', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text('$count 条', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('数据导出')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导出范围', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _month,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      for (final month in [_allMonths, ...Formatters.recentMonths()])
                        DropdownMenuItem(value: month, child: Text(month == _allMonths ? month : Formatters.monthLabel(month))),
                    ],
                    onChanged: _exporting ? null : (value) => setState(() => _month = value ?? _allMonths),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '只导出当前登录账号自己的账单，其他账号的数据不会被导出。',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('导出格式', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final format in ExportService.formats)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                onTap: _exporting ? null : () => setState(() => _format = format),
                leading: Icon(
                  _format == format ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _format == format ? theme.colorScheme.primary : Colors.grey.shade400,
                ),
                title: Text(ExportService.labelOf(format)),
                subtitle: Text(_formatHint(format), style: theme.textTheme.bodySmall),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(_exporting ? '正在导出…' : '导出账单'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '单次最多导出 10000 条。超过时请按月导出。',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  static String _formatHint(String format) {
    switch (format) {
      case 'xlsx':
        return '适合用 Excel 打开与统计，金额是数值格式';
      case 'json':
        return '结构化备份，包含商户与来源等完整字段';
      default:
        return '通用表格格式，Excel / WPS 都能打开';
    }
  }
}
