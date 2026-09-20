import 'package:flutter/material.dart';

import 'package:campus_ledger/models/spending_forecast.dart';
import 'package:campus_ledger/utils/brand.dart';
import 'package:campus_ledger/utils/money.dart';

/// 下月支出预估卡片。
/// 展示预估金额、与最近一个有效月份的对比、置信度与依据（样本月份），
/// 用户能按"最近月 ×3、次近月 ×2、第三近月 ×1"自己复核预测值。
class ForecastCard extends StatelessWidget {
  const ForecastCard({super.key, required this.data});

  final SpendingForecastResponse data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final differenceText = data.differenceText;
    final percentText = data.changePercentText;
    final reason = data.confidenceReason;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '下月预计支出',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                ),
                const SizedBox(width: 6),
                Text(
                  data.targetMonth,
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '¥${Money.format(data.predictedAmount)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Brand.orange,
              ),
            ),
            if (differenceText != null) ...[
              const SizedBox(height: 8),
              _differenceRow(theme, differenceText, percentText),
            ],
            const SizedBox(height: 10),
            _confidenceChip(theme),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reason,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
              ),
            ],
            const Divider(height: 24),
            Text(
              '依据',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 6),
            for (final sample in data.sampleMonths) _sampleRow(theme, sample),
            const SizedBox(height: 10),
            Text(
              '按你过去的记账节奏推算，仅供参考，不代表实际支出',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  /// 与上月的对比：少花用品牌绿、多花用暖红，与首页消费趋势的配色口径一致
  Widget _differenceRow(ThemeData theme, String text, String? percentText) {
    final decrease = data.isDecrease;
    final color = decrease ? Brand.income : Brand.expense;
    return Row(
      children: [
        Icon(decrease ? Icons.trending_down : Icons.trending_up, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (percentText != null) ...[
          const SizedBox(width: 6),
          Text(
            percentText,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ],
    );
  }

  /// 置信度标签：颜色只属于 UI 层，后端只返回等级
  Widget _confidenceChip(ThemeData theme) {
    final label = '置信度：${data.confidenceText}';
    final color = ForecastCard.confidenceColor(data.confidence);
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

  Widget _sampleRow(ThemeData theme, ForecastSampleMonth sample) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sample.month,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
          ),
          Text(
            sample.amountText,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Text(
            sample.weightText,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// HIGH 用品牌绿、MEDIUM 用品牌橙、LOW 用中性灰
  static Color confidenceColor(String confidence) {
    switch (confidence) {
      case 'HIGH':
        return Brand.green;
      case 'MEDIUM':
        return Brand.orange;
      case 'LOW':
        return Colors.grey.shade600;
      default:
        return Colors.grey.shade600;
    }
  }
}

/// 下月支出预估区块：统一处理四种业务状态与加载 / 错误，与相邻智能区块风格一致。
class ForecastSection extends StatelessWidget {
  const ForecastSection({
    super.key,
    required this.data,
    required this.loading,
    this.errorText,
    this.onRetry,
    this.title = '下月支出预估',
  });

  final SpendingForecastResponse? data;
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
            Icon(Icons.auto_graph, size: 15, color: Colors.grey.shade400),
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
            Text('正在计算下月预估…', style: TextStyle(fontSize: 13, color: Colors.grey)),
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
      return _hint(theme, Icons.receipt_long_outlined, '本月暂无支出记录', '记录几笔账单后即可预估下月支出');
    }
    if (payload.isInsufficient) {
      return _hint(theme, Icons.hourglass_empty, '目前历史数据不足', '继续记录几个月后可以预测',
          _currentMonthFact(payload));
    }
    if (payload.isNotApplicable) {
      return _hint(theme, Icons.event_busy_outlined, '该月份不支持预测', '下月支出预估只对当前月份有效');
    }
    if (payload.isOk) {
      return ForecastCard(data: payload);
    }
    // 未知状态：退回后端给的说明，避免区块出现空白
    return _hint(theme, Icons.auto_graph,
        payload.message.isEmpty ? '暂无可展示的下月预估' : payload.message, null);
  }

  /// 数据不足时仍然如实告诉用户本月已经花了多少
  String? _currentMonthFact(SpendingForecastResponse payload) {
    final amount = Money.toCents(payload.currentMonthAmount);
    if (amount <= 0 || payload.elapsedDays == null) {
      return null;
    }
    return '本月已过 ${payload.elapsedDays} 天，已支出 ¥${Money.format(payload.currentMonthAmount)}';
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
