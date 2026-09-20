import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/models/budget_prediction.dart';
import 'package:campus_ledger/models/recurring_bill.dart';
import 'package:campus_ledger/pages/bill_detail_page.dart';
import 'package:campus_ledger/pages/bill_list_page.dart';
import 'package:campus_ledger/pages/import_page.dart';
import 'package:campus_ledger/pages/quick_add_page.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/services/statistics_service.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/pages/budget_page.dart';
import 'package:campus_ledger/utils/bill_grouping.dart';
import 'package:campus_ledger/utils/brand.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/utils/money.dart';
import 'package:campus_ledger/widgets/bill_tile.dart';
import 'package:campus_ledger/widgets/empty_view.dart';
import 'package:campus_ledger/widgets/budget_prediction_card.dart';
import 'package:campus_ledger/widgets/recurring_bill_card.dart';

/// 首页：今日与本月概览、消费趋势、分类快捷入口、最近账单、快速记账入口
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.refresh,
    required this.onOpenBills,
    this.onOpenStatistics,
    this.onBillsChanged,
  });

  final ValueNotifier<int> refresh;
  final VoidCallback onOpenBills;

  /// 点击「查看消费分析」时切到统计页
  final VoidCallback? onOpenStatistics;

  /// 账单发生变化（新增 / 删除 / 导入）时通知外层，让统计页等一起刷新
  final VoidCallback? onBillsChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  DailySummary? _today;
  MonthlyStat? _monthly;
  TrendStat? _trend;
  MonthlyInsights? _insights;
  BudgetPredictionResponse? _prediction;
  RecurringBills? _recurring;
  List<Bill> _recent = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final month = Formatters.currentMonth();
      // 今日、本月、趋势都走后端统计接口，前端不做金额汇总，口径与统计页一致
      final today = await StatisticsService.dailySummary();
      final monthly = await StatisticsService.monthly(month);
      final trend = await StatisticsService.trends(month);
      // 首页只取洞察里的一句话摘要，完整洞察在统计页展示
      MonthlyInsights? insights;
      try {
        insights = await InsightService.monthly(month);
      } on ApiException {
        insights = null;
      }
      // 预测失败同样不影响首页主体，退化为不显示预测区域
      BudgetPredictionResponse? prediction;
      try {
        prediction = await BudgetService.predictions(month);
      } on ApiException {
        prediction = null;
      }
      // 周期识别失败不影响首页主体，退化为隐藏该区块
      RecurringBills? recurring;
      try {
        recurring = await InsightService.recurring();
      } on ApiException {
        recurring = null;
      }
      final recentResult = await BillService.list(page: 1, size: 5);
      if (!mounted) {
        return;
      }
      setState(() {
        _today = today;
        _monthly = monthly;
        _trend = trend;
        _insights = insights;
        _prediction = prediction;
        _recurring = recurring;
        _recent = recentResult.list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// 记完一笔后通知外层刷新统计，再由外层回调本页
  void _notifyChanged() {
    widget.onBillsChanged?.call();
  }

  Future<void> _quickAdd() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const QuickAddPage()),
    );
    if (saved == true) {
      _notifyChanged();
      await _load();
    }
  }

  Future<void> _importBill() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportPage()),
    );
    if (imported == true) {
      _notifyChanged();
      await _load();
    }
  }

  Future<void> _openCategoryBills(String category) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BillListPage(initialCategory: category)),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _openDetail(Bill bill) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BillDetailPage(billId: bill.id)),
    );
    if (changed == true) {
      _notifyChanged();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nickname = AuthService.currentUser?.nickname ?? '同学';

    return Scaffold(
      appBar: AppBar(
        title: const Text(Brand.name),
        actions: [
          IconButton(
            onPressed: _importBill,
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入账单',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: '刷新'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('你好，$nickname', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '今天是 ${Formatters.fullDate(Formatters.today())}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            _buildOverviewCard(theme),
            const SizedBox(height: 20),
            _buildBudgetPrediction(),
            const SizedBox(height: 20),
            _buildRecurring(),
            const SizedBox(height: 20),
            _buildInsightSummary(theme),
            const SizedBox(height: 20),
            _buildCategoryShortcuts(theme),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('最近账单', style: theme.textTheme.titleMedium),
                TextButton(onPressed: widget.onOpenBills, child: const Text('查看全部')),
              ],
            ),
            _buildRecent(theme),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _quickAdd,
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
        tooltip: '快速记账',
      ),
    );
  }

  // ==================== 概览卡片 ====================

  Widget _buildOverviewCard(ThemeData theme) {
    final today = _today;
    final monthly = _monthly;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _overviewItem(theme, '今日支出', '¥${Money.format(today?.expense ?? '0.00')}', Brand.expense),
                _overviewItem(theme, '今日收入', '¥${Money.format(today?.income ?? '0.00')}', Brand.income),
              ],
            ),
            const Divider(height: 28),
            Text('本月概览', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _overviewItem(theme, '本月支出', '¥${Money.format(monthly?.expense ?? '0.00')}', Brand.expense),
                _overviewItem(theme, '本月收入', '¥${Money.format(monthly?.income ?? '0.00')}', Brand.income),
                _overviewItem(theme, '本月结余', '¥${Money.format(monthly?.balance ?? '0.00')}',
                    monthly != null && monthly.balance.startsWith('-')
                        ? Brand.expense
                        : Colors.grey.shade800),
              ],
            ),
            const SizedBox(height: 12),
            _buildTrend(theme),
          ],
        ),
      ),
    );
  }

  /// 消费趋势：比上月多花 / 少花多少，上月没有数据时给出明确提示
  Widget _buildTrend(ThemeData theme) {
    final trend = _trend;
    if (trend == null) {
      return const SizedBox.shrink();
    }
    if (!trend.canCompare) {
      return Row(
        children: [
          Icon(Icons.insights_outlined, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Text(
            '暂无对比数据',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      );
    }
    final up = trend.isUp;
    final color = up ? Brand.expense : Brand.income;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(up ? Icons.trending_up : Icons.trending_down, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '本月支出相比上月 ${up ? '↑' : '↓'} ${trend.changeText}%',
              style: theme.textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewItem(ThemeData theme, String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 分类快捷入口 ====================

  /// 周期性支出提醒：首页最多 1 条，且只在存在 HIGH/MEDIUM 结果时显示；
  /// 没有值得提醒的结果时不占位，避免留下空白区域。
  Widget _buildRecurring() {
    final recurring = _recurring;
    if (_loading || _error != null || recurring == null) {
      return const SizedBox.shrink();
    }
    if (recurring.displayable.isEmpty) {
      return const SizedBox.shrink();
    }
    return RecurringBillSection(
      data: recurring,
      loading: false,
      limit: 1,
      onViewAll: widget.onOpenStatistics,
    );
  }

  Widget _buildBudgetPrediction() {
    final prediction = _prediction;
    if (_loading || _error != null || prediction == null) {
      return const SizedBox.shrink();
    }
    return BudgetPredictionSection(
      prediction: prediction,
      loading: false,
      limit: 2,
      onSetupBudget: _openBudget,
      // 有外层回调时切到统计页看完整分析；独立打开首页时退化为进入预算页
      onViewAnalysis: widget.onOpenStatistics ?? _openBudget,
    );
  }

  Future<void> _openBudget() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BudgetPage(month: Formatters.currentMonth())),
    );
    if (mounted) {
      await _load();
    }
  }

  /// 首页只给一句话消费概览，避免堆大量文字；点进去看完整分析
  Widget _buildInsightSummary(ThemeData theme) {
    final insights = _insights;
    if (insights == null || insights.summary.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: const ValueKey('home-insight-summary'),
        onTap: widget.onOpenStatistics,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Brand.orange),
                  const SizedBox(width: 6),
                  Text('本月消费概览',
                      style: theme.textTheme.titleSmall?.copyWith(color: Brand.orange)),
                ],
              ),
              const SizedBox(height: 10),
              Text(insights.summary, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('查看消费分析',
                      style: theme.textTheme.bodySmall?.copyWith(color: Brand.orange)),
                  const Icon(Icons.chevron_right, size: 18, color: Brand.orange),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryShortcuts(ThemeData theme) {
    const shortcuts = ['餐饮', '交通', '购物', '娱乐', '学习', '其他'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类快捷入口', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in shortcuts)
              ActionChip(
                avatar: Icon(BillTile.categoryIcon(category), size: 18, color: Brand.orange),
                label: Text(category),
                onPressed: () => _openCategoryBills(category),
              ),
          ],
        ),
      ],
    );
  }

  // ==================== 最近账单 ====================

  Widget _buildRecent(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_recent.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: EmptyView(
          icon: Icons.receipt_long_outlined,
          title: '还没有记账记录',
          subtitle: '点击右下角「记一笔」开始记账，或导入微信/支付宝账单',
        ),
      );
    }

    // 按天分组展示，标题用「今天 / 昨天」，更贴近日常阅读习惯
    final groups = BillGrouping.group(_recent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              Formatters.groupLabel(group.date),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.brown.shade400),
            ),
          ),
          for (final bill in group.bills)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: BillTile(
                bill: bill,
                showDate: false,
                onTap: () => _openDetail(bill),
              ),
            ),
        ],
      ],
    );
  }
}
