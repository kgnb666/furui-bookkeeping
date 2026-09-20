import 'package:flutter/material.dart';

import 'package:campus_ledger/models/spending_anomaly.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 单条消费异常卡片。
/// 展示标题、正文说明，以及"当前值 / 基线 / 差额"三行依据，用户可以自己核对。
class AnomalyCard extends StatelessWidget {
  const AnomalyCard({super.key, required this.item});

  final SpendingAnomaly item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = severityColor(item.severity);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(item), size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.title.isEmpty ? '消费异常' : item.title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _chip(theme, color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.message,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            _kv(theme, '当前', item.currentText, color),
            _kv(theme, '基线', item.baselineText),
            _kv(theme, '差额', item.differenceText),
            if (item.isLargeTransaction) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      item.locationText,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, Color color) {
    final label = item.severityText;
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
            width: 48,
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

  /// HIGH 用品牌红、MEDIUM 用品牌橙；颜色只属于 UI 层
  static Color severityColor(String severity) {
    switch (severity) {
      case 'HIGH':
        return Brand.expense;
      case 'MEDIUM':
        return Brand.orange;
      default:
        return Colors.grey.shade600;
    }
  }

  static IconData _icon(SpendingAnomaly item) {
    if (item.isFrequencySpike) {
      return Icons.repeat_outlined;
    }
    if (item.isLargeTransaction) {
      return Icons.priority_high_outlined;
    }
    return Icons.trending_up;
  }
}

/// 消费异常提醒区块：统一处理四种业务状态与加载/错误，与周期识别区块风格一致。
class AnomalyCardSection extends StatelessWidget {
  const AnomalyCardSection({
    super.key,
    required this.data,
    required this.loading,
    this.errorText,
    this.onRetry,
    this.title = '消费异常提醒',
  });

  final AnomaliesResponse? data;
  final bool loading;
  final String? errorText;
  final VoidCallback? onRetry;
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
            Icon(Icons.warning_amber_outlined, size: 15, color: Colors.grey.shade400),
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
            Text('正在分析本月消费异常…', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    if (errorText != null) {
      return _shell(
        theme,
        Row(
          children: [
            Expanded(child: Text(errorText!, style: TextStyle(color: theme.colorScheme.error))),
            if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('重试')),
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
      return _hint(theme, Icons.receipt_long_outlined, '本月还没有支出记录', null);
    }
    if (payload.isNotEnoughBaseline) {
      return _hint(theme, Icons.hourglass_empty, '积累几个月数据后，这里可以对比出消费异常', null);
    }
    if (payload.isNoAnomaly) {
      return _hint(theme, Icons.check_circle_outline, '本月消费节奏正常', null);
    }

    if (payload.items.isEmpty) {
      return _hint(theme, Icons.check_circle_outline, '本月消费节奏正常', null);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (payload.message.isNotEmpty) ...[
          Text(
            payload.message,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
        ],
        for (final item in payload.items) ...[
          AnomalyCard(item: item),
          const SizedBox(height: 10),
        ],
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
