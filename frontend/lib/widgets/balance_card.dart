import 'package:flutter/material.dart';

import 'package:campus_ledger/models/income_balance.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 收支结余分析卡片：本月收入、支出、结余、结余率、与上月对比与收入结构。
/// 结余为正用品牌绿、超支用暖红，全部数字都能用原始账单手工核对。
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.data});

  final IncomeBalanceResponse data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = data.comparisonText;
    final balanceColor = data.isOverSpent ? Brand.expense : Brand.income;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '看看这个月存下了多少',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _overviewItem(theme, '本月收入', data.incomeText, Brand.green),
                _overviewItem(theme, '本月支出', data.expenseText, Brand.expense),
                _overviewItem(theme, '本月结余', data.balanceText, balanceColor),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.savings_outlined, size: 15, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data.balanceRateText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (comparison != null)
                  Text(
                    comparison,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
              ],
            ),
            if (data.incomeItems.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '收入结构',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              for (final item in data.incomeItems) _incomeRow(theme, item),
            ],
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

  Widget _overviewItem(ThemeData theme, String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// 一行收入结构：分类 + 金额 + 条形 + 笔数与占比
  Widget _incomeRow(ThemeData theme, IncomeCategoryItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.category.isEmpty ? '未分类收入' : item.category,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.amountText,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 6,
                    color: Colors.grey.shade200,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: item.ratio,
                      child: Container(color: Brand.green),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.countText} · ${item.percentageText}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 收支结余区块：统一处理四种业务状态与加载 / 错误。
class BalanceSection extends StatelessWidget {
  const BalanceSection({
    super.key,
    required this.data,
    required this.loading,
    this.errorText,
    this.onRetry,
    this.title = '收支结余分析',
  });

  final IncomeBalanceResponse? data;
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
            Icon(Icons.savings_outlined, size: 15, color: Colors.grey.shade400),
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
            Text('正在分析收支结余…', style: TextStyle(fontSize: 13, color: Colors.grey)),
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
      return _hint(theme, Icons.receipt_long_outlined, '本月暂无收支记录',
          '记几笔账后即可分析收支结余');
    }
    if (payload.isNoIncomeData) {
      return _hint(theme, Icons.hourglass_empty, '本月没有收入记录',
          '补记收入后即可计算结余率', '本月已支出 ${payload.expenseText}');
    }
    if (payload.isNotApplicable) {
      return _hint(theme, Icons.event_busy_outlined, '该月份不支持收支结余分析',
          '统计分析仅针对当前月份');
    }
    if (payload.isOk) {
      return BalanceCard(data: payload);
    }
    return _hint(theme, Icons.savings_outlined,
        payload.message.isEmpty ? '暂无可展示的收支结余' : payload.message, null);
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
