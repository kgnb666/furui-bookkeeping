import 'package:flutter/material.dart';

import 'package:campus_ledger/models/budget.dart';
import 'package:campus_ledger/models/source_statistics.dart';
import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/utils/money.dart';

/// 收入 / 支出 / 结余 三列概览
class StatOverviewCard extends StatelessWidget {
  const StatOverviewCard({
    super.key,
    required this.income,
    required this.expense,
    required this.balance,
  });

  final String income;
  final String expense;
  final String balance;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _item(context, '本月收入', income, const Color(0xFF2E9E6B)),
            _item(context, '本月支出', expense, const Color(0xFFD64545)),
            _item(context, '本月结余', balance, Colors.grey.shade800),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, String label, String value, Color color) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥$value',
              style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分类支出的一行
class CategoryStatTile extends StatelessWidget {
  const CategoryStatTile({super.key, required this.stat});

  final CategoryStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(stat.category)),
          Text(
            '¥${stat.amount}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              '${stat.percentage.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 支付来源支出的一行（与分类支出保持同一种展示方式）
class SourceStatTile extends StatelessWidget {
  const SourceStatTile({super.key, required this.stat});

  final SourceStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(stat.sourceName)),
          Text(
            '¥${stat.amount}',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              '${stat.percentage.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 预算执行卡片：预算金额、已使用、剩余（或已超支）、进度条、使用率
class BudgetProgressCard extends StatelessWidget {
  const BudgetProgressCard({
    super.key,
    required this.item,
    this.onEdit,
    this.onDelete,
  });

  final BudgetItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overAmount = Money.fromCents(Money.toCents(item.used) - Money.toCents(item.amount));
    final progress = (item.usageRate / 100).clamp(0.0, 1.0);
    final color = item.isOver
        ? const Color(0xFFD64545)
        : item.isReached
            ? Colors.orange.shade700
            : theme.colorScheme.primary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.categoryName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '¥${item.amount}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: '修改预算',
                  ),
                if (onDelete != null)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: '删除预算',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '已使用 ¥${item.used}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                ),
                Text(
                  '使用率 ${item.usageRate.toStringAsFixed(2)}%',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (item.isOver)
              Text(
                '已超支 ¥$overAmount',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD64545),
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (item.isReached)
              Text(
                '已达到预算',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Text(
                '剩余 ¥${item.remaining}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
              ),
          ],
        ),
      ),
    );
  }
}
