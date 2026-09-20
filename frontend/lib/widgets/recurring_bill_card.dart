import 'package:flutter/material.dart';

import 'package:campus_ledger/models/recurring_bill.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 周期性支出卡片。展示商户、周期、平均金额、下次预计日期与依据，
/// 技术字段（变异系数、分类占比）不作为主要 UI 内容。
class RecurringBillCard extends StatelessWidget {
  const RecurringBillCard({super.key, required this.item, this.compact = false});

  final RecurringBill item;

  /// 首页使用紧凑样式，只保留最关键的信息
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _confidenceColor(item.confidence);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.autorenew, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.merchant.isEmpty ? '未知商户' : item.merchant,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _chip(theme, item.confidenceText, color),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${item.category.isEmpty ? '未分类' : item.category} · ${item.cycleText}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            _amountRow(theme, color),
            const SizedBox(height: 8),
            _kv(theme, '最近一次', _dateText(item.lastDate)),
            _kv(theme, '预计下次', _dateText(item.nextDate), color),
            const SizedBox(height: 8),
            Text(
              item.reason,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// 平均金额一行：金额 + 样本数
  Widget _amountRow(ThemeData theme, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '¥${item.amountText}',
          style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        Text(
          '/ 次',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            '${item.sampleCount} 次记录',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, String label, Color color) {
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: valueColor == null ? FontWeight.w500 : FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static Color _confidenceColor(String confidence) {
    switch (confidence) {
      case 'HIGH':
        return Brand.income;
      case 'MEDIUM':
        return Brand.orange;
      default:
        return Colors.grey.shade600;
    }
  }

  /// 2026-10-17 → 2026年10月17日；无法解析时原样返回，缺失显示 -
  static String _dateText(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return '${parsed.year}年${parsed.month.toString().padLeft(2, '0')}月'
        '${parsed.day.toString().padLeft(2, '0')}日';
  }
}

/// 周期性支出区块：统一处理四种业务状态与加载/错误，首页与统计页复用。
class RecurringBillSection extends StatelessWidget {
  const RecurringBillSection({
    super.key,
    required this.data,
    required this.loading,
    this.errorText,
    this.limit,
    this.onRetry,
    this.onViewAll,
    this.title = '周期性支出提醒',
  });

  final RecurringBills? data;
  final bool loading;
  final String? errorText;

  /// 最多展示几条，null 表示全部（统计页用）
  final int? limit;
  final VoidCallback? onRetry;
  final VoidCallback? onViewAll;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(width: 6),
            Icon(Icons.autorenew, size: 15, color: Colors.grey.shade400),
          ],
        ),
        const SizedBox(height: 10),
        _buildBody(theme),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (loading) {
      return _shell(
        theme,
        const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('正在分析你的消费规律…', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    if (errorText != null) {
      return _shell(
        theme,
        Row(
          children: [
            Expanded(
              child: Text(errorText!, style: TextStyle(color: theme.colorScheme.error)),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }

    final payload = data;
    if (payload == null) {
      return const SizedBox.shrink();
    }

    // 四种业务状态分别给引导文案，都不当成错误
    if (payload.isNoData) {
      return _hint(theme, Icons.edit_note_outlined, '记录还太少',
          '继续记录消费，积累更多数据后，系统可以帮你发现固定支出。');
    }
    if (payload.isNotEnoughHistory) {
      return _hint(theme, Icons.hourglass_empty, '账单时间还不够长',
          '积累至少几个月的数据后，系统可以识别月度固定支出。');
    }
    if (payload.isNoRecurring) {
      return _hint(theme, Icons.search_off_outlined, '暂未发现明显周期性支出', null);
    }

    final sorted = sortRecurringBills(payload.items);
    if (sorted.isEmpty) {
      return _hint(theme, Icons.search_off_outlined, '暂未发现明显周期性支出', null);
    }
    final shown = limit == null ? sorted : sorted.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in shown) ...[
          RecurringBillCard(item: item, compact: limit != null),
          const SizedBox(height: 10),
        ],
        if (onViewAll != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onViewAll,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('查看全部'),
              iconAlignment: IconAlignment.end,
            ),
          ),
      ],
    );
  }

  Widget _shell(ThemeData theme, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _hint(ThemeData theme, IconData icon, String title, String? subtitle) {
    return _shell(
      theme,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
