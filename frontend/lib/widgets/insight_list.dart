import 'package:flutter/material.dart';

import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 本月消费洞察：把后端按规则生成的结论卡片化展示。
/// 每条都带标题与完整说明，用户能看懂结论是怎么来的。
class InsightList extends StatelessWidget {
  const InsightList({super.key, required this.insights});

  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (insights.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.insights_outlined, size: 18, color: Colors.grey.shade400),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '本月数据还比较少，记账一段时间后这里会给出消费分析。',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final insight in insights)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _colorFor(insight).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_iconFor(insight), size: 18, color: _colorFor(insight)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _colorFor(insight),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(insight.message, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static Color _colorFor(Insight insight) {
    return insight.isWarning ? Brand.expense : Brand.orange;
  }

  static IconData _iconFor(Insight insight) {
    switch (insight.type) {
      case 'BUDGET_OVER':
        return Icons.error_outline;
      case 'BUDGET_WARNING':
        return Icons.warning_amber_outlined;
      case 'BIG_EXPENSE':
        return Icons.trending_up;
      case 'CATEGORY_GROWTH':
        return Icons.stacked_line_chart;
      case 'SPENDING_CHANGE':
        return Icons.swap_vert;
      case 'CATEGORY_FOCUS':
        return Icons.pie_chart_outline;
      default:
        return Icons.insights_outlined;
    }
  }
}
