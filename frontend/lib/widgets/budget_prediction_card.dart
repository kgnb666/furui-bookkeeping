import 'package:flutter/material.dart';

import 'package:campus_ledger/models/budget_prediction.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 风险等级到 UI 的映射。后端只返回等级字符串，颜色、图标、中文文案都由前端决定。
class BudgetRiskStyle {
  BudgetRiskStyle._();

  static const Color safeColor = Color(0xFF2E9E6B);
  static const Color lowColor = Color(0xFF6FAE4B);
  static const Color mediumColor = Brand.orange;
  static const Color highColor = Color(0xFFE2703A);
  static const Color overColor = Brand.expense;
  static const Color unknownColor = Color(0xFF8A8A8A);

  static Color colorOf(String riskLevel) {
    switch (riskLevel) {
      case 'SAFE':
        return safeColor;
      case 'LOW':
        return lowColor;
      case 'MEDIUM':
        return mediumColor;
      case 'HIGH':
        return highColor;
      case 'OVER':
        return overColor;
      default:
        return unknownColor;
    }
  }

  static IconData iconOf(String riskLevel) {
    switch (riskLevel) {
      case 'SAFE':
        return Icons.check_circle_outline;
      case 'LOW':
        return Icons.visibility_outlined;
      case 'MEDIUM':
        return Icons.info_outline;
      case 'HIGH':
        return Icons.warning_amber_outlined;
      case 'OVER':
        return Icons.error_outline;
      default:
        return Icons.help_outline;
    }
  }
}

/// 单条预算预测卡片。
/// 数据不足时不展示任何预测结论，只显示"已使用 / 预算"的事实。
class BudgetPredictionCard extends StatelessWidget {
  const BudgetPredictionCard({
    super.key,
    required this.item,
    this.compact = false,
  });

  final BudgetPredictionItem item;

  /// 首页使用紧凑样式：只显示关键数字
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = BudgetRiskStyle.colorOf(item.riskLevel);
    final title = item.total ? '本月预算' : '${item.categoryName}预算';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.isInsufficient
                      ? Icons.help_outline
                      : BudgetRiskStyle.iconOf(item.riskLevel),
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _riskChip(theme, color),
              ],
            ),
            const SizedBox(height: 10),
            _progressRow(theme, color),
            const SizedBox(height: 10),
            if (item.isInsufficient)
              _insufficientBody(theme)
            else
              _predictionBody(theme, color),
          ],
        ),
      ),
    );
  }

  Widget _riskChip(ThemeData theme, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        item.riskLabel,
        style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 进度条显示「当前已使用 / 预算」，不是预测使用率；数值已 clamp 到 0~1。
  Widget _progressRow(ThemeData theme, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: item.currentProgress,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '已使用 ¥${item.spent} / ¥${item.budgetAmount}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${item.currentProgressText}%',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  /// 数据不足：只给事实与一句引导，不给预测结论
  Widget _insufficientBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '消费数据不足，记录更多账单后生成预测',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          Text(
            item.message,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ],
    );
  }

  /// 正常预测：预计月底、预计超支、预计使用率、触顶日期
  Widget _predictionBody(ThemeData theme, Color color) {
    final rows = <Widget>[
      _kv(theme, '预计月底', '¥${item.projected}'),
      if (item.willOverBudget) _kv(theme, '预计超支', '¥${item.projectedOver}', color),
      _kv(theme, '预计使用率', '${item.projectedUsageText}%'),
      if (item.overDateText != null && item.willOverBudget)
        _kv(theme, '预计达到预算', item.overDateText!, color),
    ];
    if (compact) {
      // 首页只给最关键的两行，避免信息过载
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.take(3).toList(),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _kv(ThemeData theme, String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: valueColor == null ? FontWeight.w500 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 智能预算预测区域：统一处理各种状态，首页与统计页复用。
class BudgetPredictionSection extends StatelessWidget {
  const BudgetPredictionSection({
    super.key,
    required this.prediction,
    required this.loading,
    this.errorText,
    this.limit,
    this.onSetupBudget,
    this.onViewAnalysis,
    this.title = '智能预算预测',
  });

  final BudgetPredictionResponse? prediction;
  final bool loading;
  final String? errorText;

  /// 最多展示几条预测，null 表示全部（统计页用）
  final int? limit;
  final VoidCallback? onSetupBudget;
  final VoidCallback? onViewAnalysis;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
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
            Text('正在计算预算预测…', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    if (errorText != null) {
      return _shell(
        theme,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorText!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      );
    }

    final data = prediction;
    if (data == null) {
      return const SizedBox.shrink();
    }

    if (data.isNotApplicable) {
      return _hint(theme, Icons.event_busy_outlined, '预算预测仅支持当前月份');
    }

    if (data.hasNoBudget) {
      return _shell(
        theme,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined, size: 18, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                Text('还没有设置预算', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '设置预算后，系统可以预测你的消费趋势',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            if (onSetupBudget != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: onSetupBudget,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('去设置'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (data.items.isEmpty) {
      return _hint(theme, Icons.insights_outlined, '暂无预算预测数据');
    }

    final sorted = sortBudgetPredictions(data.items);
    final shown = limit == null ? sorted : sorted.take(limit!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.message.isNotEmpty) ...[
          Text(
            data.message,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
        ],
        for (final item in shown) ...[
          BudgetPredictionCard(item: item, compact: limit != null),
          const SizedBox(height: 10),
        ],
        if (onViewAnalysis != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onViewAnalysis,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('查看预算分析'),
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

  Widget _hint(ThemeData theme, IconData icon, String text) {
    return _shell(
      theme,
      Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
