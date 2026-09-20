import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/budget.dart';
import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/models/source_statistics.dart';
import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/models/budget_prediction.dart';
import 'package:campus_ledger/models/recurring_bill.dart';
import 'package:campus_ledger/models/spending_anomaly.dart';
import 'package:campus_ledger/models/spending_forecast.dart';
import 'package:campus_ledger/models/spending_rhythm.dart';
import 'package:campus_ledger/models/spending_merchant.dart';
import 'package:campus_ledger/models/income_balance.dart';
import 'package:campus_ledger/pages/budget_page.dart';
import 'package:campus_ledger/services/budget_service.dart';
import 'package:campus_ledger/services/statistics_service.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/widgets/empty_view.dart';
import 'package:campus_ledger/widgets/insight_list.dart';
import 'package:campus_ledger/widgets/budget_prediction_card.dart';
import 'package:campus_ledger/widgets/recurring_bill_card.dart';
import 'package:campus_ledger/widgets/anomaly_card.dart';
import 'package:campus_ledger/widgets/forecast_card.dart';
import 'package:campus_ledger/widgets/rhythm_card.dart';
import 'package:campus_ledger/widgets/merchant_card.dart';
import 'package:campus_ledger/widgets/balance_card.dart';
import 'package:campus_ledger/widgets/month_selector.dart';
import 'package:campus_ledger/widgets/stat_charts.dart';
import 'package:campus_ledger/widgets/stat_widgets.dart';

/// 统计页：月度概览、分类支出、每日趋势，以及本月预算入口
class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key, this.refresh});

  /// 账单发生变化时的刷新信号，独立打开该页面时可以为空
  final ValueNotifier<int>? refresh;

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String _month = Formatters.currentMonth();
  MonthlyStat? _monthly;
  List<CategoryStat> _categories = [];
  List<SourceStat> _sources = [];
  List<DailyStat> _daily = [];
  MonthlyInsights? _insights;
  BudgetPredictionResponse? _prediction;
  RecurringBills? _recurring;
  AnomaliesResponse? _anomalies;
  SpendingForecastResponse? _forecast;
  SpendingRhythmResponse? _rhythm;
  SpendingMerchantResponse? _merchant;
  IncomeBalanceResponse? _balanceInsight;
  BudgetSummary? _budget;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_reloadKeepingMonth);
    _load();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reloadKeepingMonth);
    super.dispose();
  }

  void _reloadKeepingMonth() {
    if (mounted) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final monthly = await StatisticsService.monthly(_month);
      final categories = await StatisticsService.category(_month);
      final sources = await StatisticsService.source(_month);
      final daily = await StatisticsService.daily(_month);
      // 预算只是统计页上的一个入口，取不到时不影响统计展示
      BudgetSummary? budget;
      try {
        budget = await BudgetService.list(_month);
      } on ApiException {
        budget = null;
      }
      // 消费洞察同样属于增强信息，取不到不影响统计主体
      MonthlyInsights? insights;
      try {
        insights = await InsightService.monthly(_month);
      } on ApiException {
        insights = null;
      }
      // 预算预测：历史月份后端会返回 NOT_APPLICABLE，前端据此提示
      BudgetPredictionResponse? prediction;
      try {
        prediction = await BudgetService.predictions(_month);
      } on ApiException {
        prediction = null;
      }
      // 周期识别与月份无关（跨月模式），失败时该区块隐藏
      RecurringBills? recurring;
      try {
        recurring = await InsightService.recurring();
      } on ApiException {
        recurring = null;
      }
      // 消费异常按月份查询，取不到时该区块隐藏，不影响其他区块
      AnomaliesResponse? anomalies;
      try {
        anomalies = await InsightService.anomalies(_month);
      } on ApiException {
        anomalies = null;
      }
      // 下月支出预估：只对当前月份返回结论，其他月份返回 NOT_APPLICABLE，失败时该区块隐藏
      SpendingForecastResponse? forecast;
      try {
        forecast = await InsightService.forecast(_month);
      } on ApiException {
        forecast = null;
      }
      // 消费节奏分析：同样只对当前月份返回结论，失败时该区块隐藏
      SpendingRhythmResponse? rhythm;
      try {
        rhythm = await InsightService.rhythm(_month);
      } on ApiException {
        rhythm = null;
      }
      // 消费对象分析：失败时只隐藏本区块，不影响其它模块
      SpendingMerchantResponse? merchant;
      try {
        merchant = await InsightService.merchants(_month);
      } on ApiException {
        merchant = null;
      }
      // 收支结余分析：同样独立降级
      IncomeBalanceResponse? balanceInsight;
      try {
        balanceInsight = await InsightService.balance(_month);
      } on ApiException {
        balanceInsight = null;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _monthly = monthly;
        _categories = categories;
        _sources = sources;
        _daily = daily;
        _budget = budget;
        _insights = insights;
        _prediction = prediction;
        _recurring = recurring;
        _anomalies = anomalies;
        _forecast = forecast;
        _rhythm = rhythm;
        _merchant = merchant;
        _balanceInsight = balanceInsight;
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

  void _changeMonth(String month) {
    setState(() => _month = month);
    _load();
  }

  Future<void> _openBudget() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BudgetPage(month: _month)),
    );
    await _load();
  }

  bool get _isEmptyMonth {
    final monthly = _monthly;
    if (monthly == null) {
      return true;
    }
    return monthly.income == '0.00' && monthly.expense == '0.00';
  }

  bool get _hasExpense {
    for (final day in _daily) {
      if (day.expense != '0.00') {
        return true;
      }
    }
    return false;
  }

  /// 本月消费洞察：卡片化展示后端按规则给出的结论
  /// 周期性支出提醒：独立区块，展示全部识别结果。
  /// 与月份无关——切换统计月份时周期识别结果不跟着变。
  Widget _buildRecurringSection() {
    final recurring = _recurring;
    if (recurring == null) {
      return const SizedBox.shrink();
    }
    return RecurringBillSection(data: recurring, loading: false, onRetry: _load);
  }

  /// 消费异常提醒：独立区块，展示本月最多 5 条异常。
  /// 与周期识别一样按月份切换重新请求，失败时只降级本区块。
  Widget _buildAnomalySection() {
    final anomalies = _anomalies;
    if (anomalies == null) {
      return const SizedBox.shrink();
    }
    return AnomalyCardSection(data: anomalies, loading: false, onRetry: _load);
  }

  /// 下月支出预估：独立区块，与消费异常一样按月份切换重新请求，失败时只降级本区块
  Widget _buildForecastSection() {
    final forecast = _forecast;
    if (forecast == null) {
      return const SizedBox.shrink();
    }
    return ForecastSection(data: forecast, loading: false, onRetry: _load);
  }

  /// 消费节奏分析：独立区块，按月份切换重新请求，失败时只降级本区块
  Widget _buildRhythmSection() {
    final rhythm = _rhythm;
    if (rhythm == null) {
      return const SizedBox.shrink();
    }
    return RhythmSection(data: rhythm, loading: false, onRetry: _load);
  }

  /// 消费对象分析：独立区块，按月份切换重新请求，失败时只降级本区块
  Widget _buildMerchantSection() {
    final merchant = _merchant;
    if (merchant == null) {
      return const SizedBox.shrink();
    }
    return MerchantSection(data: merchant, loading: false, onRetry: _load);
  }

  /// 收支结余分析：紧跟本月概览（同一个收入/支出/结余数据的一步解读），失败时只降级本区块
  Widget _buildBalanceSection() {
    final balance = _balanceInsight;
    if (balance == null) {
      return const SizedBox.shrink();
    }
    return BalanceSection(data: balance, loading: false, onRetry: _load);
  }

  Widget _buildInsightsSection() {
    final theme = Theme.of(context);
    final insights = _insights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('本月消费洞察', style: theme.textTheme.titleMedium),
            const SizedBox(width: 6),
            Icon(Icons.auto_awesome, size: 15, color: Colors.grey.shade400),
          ],
        ),
        if (insights != null && insights.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            insights.summary,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 10),
        InsightList(insights: insights?.insights ?? const []),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('统计'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: '刷新'),
        ],
      ),
      body: Column(
        children: [
          MonthSelector(month: _month, onChanged: _changeMonth),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    final monthly = _monthly!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          StatOverviewCard(
            income: monthly.income,
            expense: monthly.expense,
            balance: monthly.balance,
          ),
          const SizedBox(height: 16),
          _buildBalanceSection(),
          const SizedBox(height: 16),
          _buildBudgetCard(),
          const SizedBox(height: 16),
          BudgetPredictionSection(
            prediction: _prediction,
            loading: false,
            onSetupBudget: _openBudget,
          ),
          const SizedBox(height: 16),
          _buildRecurringSection(),
          const SizedBox(height: 16),
          _buildAnomalySection(),
          const SizedBox(height: 16),
          _buildForecastSection(),
          const SizedBox(height: 16),
          _buildInsightsSection(),
          const SizedBox(height: 16),
          if (_isEmptyMonth)
            const Card(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: EmptyView(
                  icon: Icons.bar_chart,
                  title: '本月暂无收支记录',
                  subtitle: '换个月份看看，或者先记一笔账',
                ),
              ),
            )
          else ...[
            _buildCategorySection(),
            const SizedBox(height: 16),
            _buildSourceSection(),
            const SizedBox(height: 16),
            _buildMerchantSection(),
            const SizedBox(height: 16),
            _buildRhythmSection(),
            const SizedBox(height: 16),
            _buildDailySection(),
          ],
        ],
      ),
    );
  }

  Widget _buildBudgetCard() {
    final theme = Theme.of(context);
    final total = _budget?.total;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('本月预算', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  if (total == null)
                    Text(
                      '还没有设置本月预算',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    )
                  else ...[
                    Text('¥${total.amount}', style: theme.textTheme.titleMedium),
                    Text(
                      '已使用 ${total.usageRate.toStringAsFixed(2)}%'
                      '${total.isOver ? '（已超支）' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: total.isOver ? const Color(0xFFD64545) : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            OutlinedButton(
              onPressed: _openBudget,
              child: Text(total == null ? '设置预算' : '查看预算'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('支出分类', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                if (_categories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '本月没有支出记录',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                    ),
                  )
                else ...[
                  CategoryPieChart(categories: _categories),
                  const Divider(height: 24),
                  for (final stat in _categories) CategoryStatTile(stat: stat),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('支付来源', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: _sources.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '本月没有支出记录',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                  ),
                )
              : Column(
                  children: [
                    for (final stat in _sources) SourceStatTile(stat: stat),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDailySection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('每日支出趋势', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
            child: _hasExpense
                ? DailyExpenseChart(daily: _daily)
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        '本月暂无支出记录',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
