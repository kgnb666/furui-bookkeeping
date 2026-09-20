import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/pages/bill_edit_page.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/utils/brand.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/utils/money.dart';
import 'package:campus_ledger/widgets/bill_tile.dart';

/// 账单详情：大金额 + 分类 + 时间 + 备注 + 来源，底部固定编辑/删除
class BillDetailPage extends StatefulWidget {
  const BillDetailPage({super.key, required this.billId});

  final int billId;

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  Bill? _bill;
  bool _loading = true;
  bool _deleting = false;
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
      final bill = await BillService.detail(widget.billId);
      if (!mounted) {
        return;
      }
      setState(() {
        _bill = bill;
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

  Future<void> _edit() async {
    final bill = _bill;
    if (bill == null) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BillEditPage(bill: bill)),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _delete() async {
    final bill = _bill;
    if (bill == null || _deleting) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔账单？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await BillService.delete(bill.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账单已删除')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bill = _bill;
    return Scaffold(
      appBar: AppBar(title: const Text('账单详情')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(theme)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _buildAmountCard(theme, bill!),
                    const SizedBox(height: 16),
                    _buildSection(
                      theme,
                      title: '交易信息',
                      icon: Icons.receipt_long_outlined,
                      rows: [
                        _DetailRow('分类', bill.category, icon: BillTile.categoryIcon(bill.category)),
                        _DetailRow('类型', bill.typeName, icon: Icons.swap_vert),
                        _DetailRow('时间', Formatters.fullDate(bill.billDate), icon: Icons.event_outlined),
                        _DetailRow('支付方式', bill.sourceName.isEmpty ? '手动记录' : bill.sourceName,
                            icon: Icons.account_balance_wallet_outlined),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSection(
                      theme,
                      title: '备注信息',
                      icon: Icons.notes_outlined,
                      rows: [
                        _DetailRow('交易对象', bill.merchant.isEmpty ? '-' : bill.merchant,
                            icon: Icons.storefront_outlined),
                        _DetailRow('备注', bill.remark.isEmpty ? '-' : bill.remark,
                            icon: Icons.edit_note_outlined),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSection(
                      theme,
                      title: '记录信息',
                      icon: Icons.info_outline,
                      rows: [
                        _DetailRow('创建时间', Formatters.dateTime(bill.createdAt),
                            icon: Icons.schedule_outlined),
                      ],
                    ),
                  ],
                ),
      bottomNavigationBar: bill == null || _error != null ? null : _buildActions(theme),
    );
  }

  /// 金额是详情页的主视觉：大号字 + 收支符号 + 分类图标
  Widget _buildAmountCard(ThemeData theme, Bill bill) {
    final color = bill.isIncome
        ? Brand.income
        : bill.isExpense
            ? Brand.expense
            : Colors.grey.shade700;
    final sign = bill.isIncome ? '+ ' : bill.isExpense ? '- ' : '';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(BillTile.categoryIcon(bill.category), color: color, size: 26),
            ),
            const SizedBox(height: 12),
            Text(bill.category, style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$sign¥${Money.format(bill.amount)}',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${bill.typeName} · ${Formatters.fullDate(bill.billDate)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme,
      {required String title, required IconData icon, required List<_DetailRow> rows}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          for (final row in rows) _buildRow(theme, row),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildRow(ThemeData theme, _DetailRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(row.icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(row.label, style: TextStyle(color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _deleting ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.expense,
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _deleting ? null : _edit,
                icon: _deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_outlined),
                label: const Text('编辑'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 详情页的一行信息
class _DetailRow {
  const _DetailRow(this.label, this.value, {required this.icon});

  final String label;
  final String value;
  final IconData icon;
}
