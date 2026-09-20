import 'package:flutter/material.dart';

import 'package:campus_ledger/models/spending_rhythm.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 消费节奏分析卡片：总支出、记账覆盖、峰值、星期分布与月内阶段分布。
/// 每个数字都带百分比，用户可以自己核对"钱花在什么时候"。
class RhythmCard extends StatelessWidget {
  const RhythmCard({super.key, required this.data});

  final SpendingRhythmResponse data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当月支出',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            Text(
              data.totalText,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Brand.orange,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event_available_outlined, size: 15, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '记账覆盖：${data.coveredDaysText}，${data.coveredRateText}',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              '峰值',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            _kv(theme, '最高消费星期', data.peakWeekday),
            _kv(theme, '最高消费阶段', data.peakPeriod),
            _kv(theme, '消费集中度', data.concentrationText),
            const Divider(height: 24),
            Text(
              '星期分布',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            for (final item in data.weekdayItems)
              _barRow(
                theme,
                label: item.weekdayName,
                amount: item.amountText,
                percentage: item.percentageText,
                ratio: item.ratio,
                highlight: item.weekdayName == data.peakWeekday,
                color: Brand.orange,
              ),
            const Divider(height: 24),
            Text(
              '月内阶段',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            for (final item in data.periodItems)
              _barRow(
                theme,
                label: item.periodName,
                amount: item.amountText,
                percentage: item.percentageText,
                ratio: item.ratio,
                highlight: item.periodName == data.peakPeriod,
                color: Brand.green,
                tooltip: item.rangeText,
              ),
            if (data.summary.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                data.summary,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 一行分布：名称 + 横向条形 + 金额 + 百分比
  Widget _barRow(ThemeData theme, {
    required String label,
    required String amount,
    required String percentage,
    required double ratio,
    required bool highlight,
    required Color color,
    String? tooltip,
  }) {
    final barColor = highlight ? color : color.withValues(alpha: 0.35);
    final labelColor = highlight ? color : Colors.grey.shade700;
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: labelColor,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: Colors.grey.shade200,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio,
                  child: Container(color: barColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              percentage,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: highlight ? color : Colors.grey.shade600,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? row : Tooltip(message: tooltip, child: row);
  }
}

/// 消费节奏区块：统一处理四种业务状态与加载 / 错误，与相邻智能区块风格一致。
class RhythmSection extends StatelessWidget {
  const RhythmSection({
    super.key,
    required this.data,
    required this.loading,
    this.errorText,
    this.onRetry,
    this.title = '消费节奏分析',
  });

  final SpendingRhythmResponse? data;
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
            Icon(Icons.schedule, size: 15, color: Colors.grey.shade400),
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
            Text('正在分析你的消费节奏…', style: TextStyle(fontSize: 13, color: Colors.grey)),
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

    // 四种业务状态都给引导文案，都不当成错误
    if (payload.isNoData) {
      return _hint(theme, Icons.receipt_long_outlined, '本月暂无支出记录',
          '记录几笔账单后即可分析消费节奏');
    }
    if (payload.isInsufficient) {
      return _hint(theme, Icons.hourglass_empty, '消费记录不足', '需要更多消费日期后分析节奏',
          _factText(payload));
    }
    if (payload.isNotApplicable) {
      return _hint(theme, Icons.event_busy_outlined, '该月份不支持消费节奏分析',
          '统计分析仅针对当前月份');
    }
    if (payload.isOk) {
      return RhythmCard(data: payload);
    }
    // 未知状态：退回后端给的说明，避免区块出现空白
    return _hint(theme, Icons.schedule,
        payload.message.isEmpty ? '暂无可展示的消费节奏' : payload.message, null);
  }

  /// 数据不足时仍然如实告诉用户已有的记录情况
  String? _factText(SpendingRhythmResponse payload) {
    if (payload.coveredDays <= 0) {
      return null;
    }
    return '本月已有 ${payload.coveredDays} 天消费，共支出 ${payload.totalText}';
  }

  Widget _shell(ThemeData theme, Widget child) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _hint(ThemeData theme, IconData icon, String title, String? subtitle, [String? fact]) {
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
                if (fact != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    fact,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
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
