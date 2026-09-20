import 'package:flutter/material.dart';

import 'package:campus_ledger/models/spending_merchant.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 消费对象分析卡片：总览、覆盖情况、消费对象排行、集中度与数据质量提示。
/// 每个数字都能用原始账单手工核对（金额、笔数、占比）。
class MerchantCard extends StatelessWidget {
  const MerchantCard({super.key, required this.data});

  final SpendingMerchantResponse data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unknownText = data.unknownText;
    // 后端最多返回 5 条，前端再做一次保护，避免异常数据把页面撑长
    final items = data.topMerchants.length > maxMerchantRows
        ? data.topMerchants.sublist(0, maxMerchantRows)
        : data.topMerchants;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '看看你的钱主要花给谁',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _overviewItem(theme, '本月支出', data.totalText, Brand.orange),
                _overviewItem(theme, '消费笔数', data.totalCountText, Colors.grey.shade800),
                _overviewItem(theme, '平均客单价', data.averageText, Brand.green),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.storefront_outlined, size: 15, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    data.coverageText,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                '消费对象排行',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < items.length; i++) _merchantRow(theme, i + 1, items[i]),
            ],
            const Divider(height: 24),
            Text(
              data.concentrationText,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (unknownText != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      unknownText,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ],
            if (data.summary.isNotEmpty) ...[
              const SizedBox(height: 10),
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

  /// 消费对象排行最多展示的条数
  static const int maxMerchantRows = 5;

  Widget _overviewItem(ThemeData theme, String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
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

  /// 一行消费对象：排名 + 名称 + 金额 + 条形 + 笔数 + 占比
  Widget _merchantRow(ThemeData theme, int rank, MerchantSpendingItem item) {
    final highlight = rank <= 3;
    final color = highlight ? Brand.orange : Colors.grey.shade400;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '$rank',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: highlight ? Brand.orange : Colors.grey.shade500,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  item.merchantName.isEmpty ? '未填写消费对象' : item.merchantName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.amountText,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 6,
                    color: Colors.grey.shade200,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: item.ratio,
                      child: Container(color: color),
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

/// 消费对象分析区块：统一处理四种业务状态与加载 / 错误，与相邻智能区块风格一致。
class MerchantSection extends StatelessWidget {
  const MerchantSection({
    super.key,
    required this.data,
    required this.loading,
    this.errorText,
    this.onRetry,
    this.title = '消费对象分析',
  });

  final SpendingMerchantResponse? data;
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
            Icon(Icons.storefront_outlined, size: 15, color: Colors.grey.shade400),
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
            Text('正在分析消费对象…', style: TextStyle(fontSize: 13, color: Colors.grey)),
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
          '记录几笔账单后即可分析消费对象');
    }
    if (payload.isInsufficient) {
      return _hint(theme, Icons.hourglass_empty, '消费记录不足', '记录更多消费对象后即可分析',
          _factText(payload));
    }
    if (payload.isNotApplicable) {
      return _hint(theme, Icons.event_busy_outlined, '该月份不支持消费对象分析',
          '统计分析仅针对当前月份');
    }
    if (payload.isOk) {
      return MerchantCard(data: payload);
    }
    // 未知状态：退回后端给的说明，避免区块出现空白
    return _hint(theme, Icons.storefront_outlined,
        payload.message.isEmpty ? '暂无可展示的消费对象分析' : payload.message, null);
  }

  /// 数据不足时仍然如实告诉用户已有的消费事实
  String? _factText(SpendingMerchantResponse payload) {
    if (payload.totalCount <= 0) {
      return null;
    }
    return '本月支出 ${payload.totalText}，共 ${payload.totalCountText}';
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
