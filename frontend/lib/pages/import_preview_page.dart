import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/import_preview.dart';
import 'package:campus_ledger/pages/import_result_page.dart';
import 'package:campus_ledger/services/import_service.dart';
import 'package:campus_ledger/utils/categories.dart';

/// 导入预览：区分新增 / 重复 / 不计收支 / 解析失败，可改分类、可勾选，确认后才入库
class ImportPreviewPage extends StatefulWidget {
  const ImportPreviewPage({super.key, required this.preview});

  final ImportPreview preview;

  @override
  State<ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends State<ImportPreviewPage> {
  static const String _all = '全部';

  String _filter = _all;
  bool _submitting = false;

  List<ImportPreviewItem> get _filtered {
    final items = widget.preview.items;
    switch (_filter) {
      case '新增':
        return items.where((item) => item.importable && !item.duplicate && !item.isNeutral).toList();
      case '重复':
        return items.where((item) => item.duplicate).toList();
      case '不计收支':
        return items.where((item) => item.isNeutral).toList();
      case '解析失败':
        return items.where((item) => !item.importable).toList();
      default:
        return items;
    }
  }

  void _toggleAll() {
    final selectable = _filtered.where((item) => item.importable).toList();
    final allSelected = selectable.isNotEmpty && selectable.every((item) => item.selected);
    setState(() {
      for (final item in selectable) {
        item.selected = !allSelected;
      }
    });
  }

  Future<void> _editCategory(ImportPreviewItem item) async {
    final categories = Categories.of(item.type);
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('修改分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final category in categories)
              ListTile(
                title: Text(category),
                trailing: category == item.editableCategory ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(category),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => item.editableCategory = picked);
    }
  }

  Future<void> _confirm() async {
    if (_submitting) {
      return;
    }
    final selected = widget.preview.selectedItems;
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一条记录')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ImportService.confirm(
        source: widget.preview.source,
        fileName: widget.preview.fileName,
        totalCount: widget.preview.totalCount,
        items: selected,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ImportResultPage(result: result)),
      );
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.preview;
    final items = _filtered;
    final selectedCount = preview.selectedItems.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入预览'),
        actions: [
          TextButton(onPressed: _submitting ? null : _toggleAll, child: const Text('全选/全不选')),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本次发现 ${preview.totalCount} 条交易', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${preview.sourceName} · ${preview.fileName}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      _countText('新增', preview.newCount, const Color(0xFF2E9E6B)),
                      _countText('重复', preview.duplicateCount, Colors.grey.shade700),
                      _countText('不计收支', preview.neutralCount, Colors.orange.shade800),
                      _countText('解析失败', preview.failedCount, theme.colorScheme.error),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final filter in [_all, '新增', '重复', '不计收支', '解析失败'])
                  ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('没有符合条件的记录'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) => _buildItem(items[index]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Row(
          children: [
            Expanded(child: Text('已选择 $selectedCount 条')),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _submitting ? null : _confirm,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('确认导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countText(String label, int count, Color color) {
    return Text(
      '$label $count',
      style: TextStyle(color: color, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildItem(ImportPreviewItem item) {
    final reason = item.failReason ?? item.duplicateReason;
    final title = item.merchant.isEmpty ? item.editableCategory : item.merchant;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: CheckboxListTile(
        value: item.selected,
        onChanged: item.importable
            ? (value) => setState(() => item.selected = value ?? false)
            : null,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                InkWell(
                  onTap: item.importable ? () => _editCategory(item) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.importable ? '${item.editableCategory} ▾' : item.editableCategory,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                Text(item.typeName, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text(item.billDate, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  reason,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        secondary: Text(
          '¥${item.amount}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
