import 'package:flutter/material.dart';

import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/utils/brand.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/utils/money.dart';

/// 账单列表里的一行：支出显示红色减号、收入显示绿色加号，便于一眼区分
class BillTile extends StatelessWidget {
  const BillTile({
    super.key,
    required this.bill,
    this.onTap,
    this.showDate = true,
  });

  final Bill bill;
  final VoidCallback? onTap;

  /// 列表已经按天分组时传 false，避免每行重复显示日期
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color amountColor;
    final String sign;
    if (bill.isIncome) {
      amountColor = Brand.income;
      sign = '+ ';
    } else if (bill.isExpense) {
      amountColor = Brand.expense;
      sign = '- ';
    } else {
      amountColor = Colors.grey.shade600;
      sign = '';
    }

    // 标题优先用商户/备注，没有时退回分类，保证一行里信息量最大
    final title = bill.merchant.isNotEmpty
        ? bill.merchant
        : (bill.remark.isNotEmpty ? bill.remark : bill.category);
    final parts = <String>[bill.category];
    if (bill.merchant.isNotEmpty && bill.remark.isNotEmpty) {
      parts.add(bill.remark);
    }
    parts.add(bill.sourceName.isEmpty ? '手动记录' : bill.sourceName);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: amountColor.withValues(alpha: 0.12),
        child: Icon(
          categoryIcon(bill.category),
          size: 20,
          color: amountColor,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        parts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$sign¥${Money.format(bill.amount)}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showDate) ...[
            const SizedBox(height: 2),
            Text(
              Formatters.billDate(bill.billDate),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  /// 分类对应的图标，让列表不用读文字也能快速扫过
  static IconData categoryIcon(String category) {
    switch (category) {
      case '餐饮':
        return Icons.restaurant;
      case '交通':
        return Icons.directions_bus;
      case '购物':
        return Icons.shopping_bag_outlined;
      case '娱乐':
        return Icons.sports_esports_outlined;
      case '学习':
        return Icons.menu_book_outlined;
      case '住宿':
        return Icons.home_outlined;
      case '生活':
        return Icons.local_laundry_service_outlined;
      case '医疗':
        return Icons.local_hospital_outlined;
      case '通讯':
        return Icons.phone_iphone;
      case '生活费':
        return Icons.account_balance_wallet_outlined;
      case '奖助学金':
        return Icons.emoji_events_outlined;
      case '兼职收入':
        return Icons.work_outline;
      case '红包':
        return Icons.card_giftcard;
      case '其他收入':
        return Icons.savings_outlined;
      case '转账':
        return Icons.swap_horiz;
      case '提现':
        return Icons.atm_outlined;
      case '还款':
        return Icons.credit_score_outlined;
      default:
        return Icons.more_horiz;
    }
  }
}
