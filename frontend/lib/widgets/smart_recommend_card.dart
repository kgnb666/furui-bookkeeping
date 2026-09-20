import 'package:flutter/material.dart';

import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 智能推荐卡片：展示推荐分类、可信度与原因，用户点击才会应用。
/// 没有足够历史数据时不显示虚假推荐，只给一句引导。
class SmartRecommendCard extends StatelessWidget {
  const SmartRecommendCard({
    super.key,
    required this.recommend,
    required this.loading,
    this.onApply,
    this.dismissed = false,
  });

  final CategoryRecommend? recommend;
  final bool loading;

  /// 点击「使用推荐」后的回调，由表单把分类切过去
  final VoidCallback? onApply;

  /// 用户已应用过推荐，卡片收起
  final bool dismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (dismissed) {
      return const SizedBox.shrink();
    }
    if (loading) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('正在根据你的记账习惯分析…',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    final data = recommend;
    if (data == null || !data.hasSuggestion) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 18, color: Colors.grey.shade400),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '记录更多账单后，系统会逐渐了解你的消费习惯',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: Brand.orange.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Brand.orange),
                const SizedBox(width: 6),
                Text('智能推荐',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Brand.orange, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (data.confidenceLabel.isNotEmpty)
                  Text(
                    data.confidenceLabel,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.category!,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.reason,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                if (onApply != null)
                  FilledButton.tonal(
                    onPressed: onApply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text('使用推荐'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
