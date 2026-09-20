import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/budget.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/utils/categories.dart';
import 'package:campus_ledger/utils/money.dart';
import 'package:campus_ledger/widgets/month_selector.dart';
import 'package:campus_ledger/widgets/stat_widgets.dart';

/// 预算页：月度总预算 + 分类预算，执行情况由后端统计
class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key, required this.month});

  final String month;

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  late String _month = widget.month;
  BudgetSummary? _summary;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await BudgetService.list(_month);
      if (!mounted) {
        return;
      }
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _changeMonth(String month) {
    setState(() => _month = month);
    _load();
  }

  /// 弹出金额输入框，新增或修改预算
  Future<void> _editBudget({
    required String category,
    required String categoryName,
    BudgetItem? existing,
  }) async {
    final formKey = GlobalKey<FormState>();
    final controller = TextEditingController(text: existing?.amount ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '设置$categoryName预算' : '修改$categoryName预算'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(
              labelText: '预算金额',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
            ),
            validator: Money.validate,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || _saving) {
      return;
    }

    setState(() => _saving = true);
    try {
      final amount = controller.text.trim();
      if (existing == null) {
        await BudgetService.create(month: _month, category: category, amount: amount);
      } else {
        await BudgetService.update(existing.id, month: _month, category: category, amount: amount);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('预算已保存')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickCategoryToBudget() async {
    final budgeted = (_summary?.categories ?? []).map((item) => item.category).toSet();
    final options = Categories.expenseCategories.where((c) => !budgeted.contains(c)).toList();
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('所有支出分类都已经设置预算了')),
      );
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要设置预算的分类', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final category in options)
              ListTile(title: Text(category), onTap: () => Navigator.pop(context, category)),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      await _editBudget(category: picked, categoryName: picked);
    }
  }

  Future<void> _deleteBudget(BudgetItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除${item.categoryName}预算？'),
        content: const Text('删除后本月不再按这条预算统计。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _saving = true);
    try {
      await BudgetService.delete(item.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('预算已删除')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      body: Column(
        children: [
          MonthSelector(month: _month, onChanged: _changeMonth),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final summary = _summary!;
    final total = summary.total;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '本月已支出 ¥${summary.monthExpense}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('总预算', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (total == null)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      '还没有设置本月总预算',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _editBudget(category: '', categoryName: '月度总预算'),
                      child: const Text('设置总预算'),
                    ),
                  ],
                ),
              ),
            )
          else
            BudgetProgressCard(
              item: total,
              onEdit: _saving
                  ? null
                  : () => _editBudget(
                        category: '',
                        categoryName: '月度总预算',
                        existing: total,
                      ),
              onDelete: _saving ? null : () => _deleteBudget(total),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('分类预算', style: theme.textTheme.titleMedium),
              TextButton.icon(
                onPressed: _saving ? null : _pickCategoryToBudget,
                icon: const Icon(Icons.add),
                label: const Text('添加'),
              ),
            ],
          ),
          if (summary.categories.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '还没有设置分类预算',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            for (final item in summary.categories) ...[
              BudgetProgressCard(
                item: item,
                onEdit: _saving
                    ? null
                    : () => _editBudget(
                          category: item.category,
                          categoryName: item.categoryName,
                          existing: item,
                        ),
                onDelete: _saving ? null : () => _deleteBudget(item),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
