import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/pages/bill_detail_page.dart';
import 'package:campus_ledger/pages/bill_edit_page.dart';
import 'package:campus_ledger/pages/export_page.dart';
import 'package:campus_ledger/pages/import_history_page.dart';
import 'package:campus_ledger/pages/import_page.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/utils/bill_grouping.dart';
import 'package:campus_ledger/utils/brand.dart';
import 'package:campus_ledger/utils/categories.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/utils/money.dart';
import 'package:campus_ledger/widgets/bill_tile.dart';
import 'package:campus_ledger/widgets/empty_view.dart';

/// 账单列表：筛选 + 分页 + 增删改入口 + 导入入口
class BillListPage extends StatefulWidget {
  const BillListPage({
    super.key,
    this.refresh,
    this.initialCategory,
    this.onBillsChanged,
  });

  /// 底部导航切换过来时的刷新信号，独立打开该页面时可以为空
  final ValueNotifier<int>? refresh;

  /// 从首页分类快捷入口进入时预设的分类筛选
  final String? initialCategory;

  /// 账单发生变化时通知外层（首页与统计页）刷新
  final VoidCallback? onBillsChanged;

  @override
  State<BillListPage> createState() => _BillListPageState();
}

class _BillListPageState extends State<BillListPage> {
  static const int _pageSize = 50;
  static const String _allMonths = '全部月份';
  static const String _allCategories = '全部分类';
  static const String _allSources = '全部来源';
  static const String _allTypes = '全部类型';

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();

  /// 金额输入后延迟查询，避免每敲一个字符就请求一次
  Timer? _amountDebounce;

  final List<Bill> _bills = [];
  String _month = Formatters.currentMonth();
  String _typeLabel = _allTypes;
  late String _category;
  String _source = _allSources;
  String _keyword = '';
  String _minAmount = '';
  String _maxAmount = '';
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? _allCategories;
    widget.refresh?.addListener(_reload);
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    _scrollController.dispose();
    _keywordController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    _amountDebounce?.cancel();
    super.dispose();
  }

  /// 金额输入：数字与小数点之外的内容直接丢弃
  void _onAmountChanged(String value, {required bool isMin}) {
    final filtered = value.replaceAll(RegExp(r'[^0-9.]'), '');
    final controller = isMin ? _minAmountController : _maxAmountController;
    if (controller.text != filtered) {
      controller.value = TextEditingValue(
        text: filtered,
        selection: TextSelection.collapsed(offset: filtered.length),
      );
    }
    _amountDebounce?.cancel();
    _amountDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) {
        return;
      }
      final changed = _minAmount != _minAmountController.text.trim() ||
          _maxAmount != _maxAmountController.text.trim();
      if (changed) {
        setState(() {
          _minAmount = _minAmountController.text.trim();
          _maxAmount = _maxAmountController.text.trim();
        });
        _reload();
      }
    });
  }

  /// 是否处于筛选状态，决定空状态提示是"没有记录"还是"没有找到"
  bool get _hasFilter =>
      _month != _allMonths ||
      _typeLabel != _allTypes ||
      _category != _allCategories ||
      _source != _allSources ||
      _keyword.isNotEmpty ||
      _minAmount.isNotEmpty ||
      _maxAmount.isNotEmpty;

  /// 一键回到默认筛选（月份仍然是当前月）
  void _clearFilters() {
    _keywordController.clear();
    _minAmountController.clear();
    _maxAmountController.clear();
    _amountDebounce?.cancel();
    setState(() {
      _month = Formatters.currentMonth();
      _typeLabel = _allTypes;
      _category = _allCategories;
      _source = _allSources;
      _keyword = '';
      _minAmount = '';
      _maxAmount = '';
    });
    _reload();
  }

  int? get _typeValue {
    switch (_typeLabel) {
      case '支出':
        return Categories.expense;
      case '收入':
        return Categories.income;
      case '不计收支':
        return Categories.neutral;
      default:
        return null;
    }
  }

  String? get _sourceValue {
    switch (_source) {
      case '手动记录':
        return 'MANUAL';
      case '微信':
        return 'WECHAT';
      case '支付宝':
        return 'ALIPAY';
      default:
        return null;
    }
  }

  List<String> get _categoryOptions {
    final type = _typeValue;
    if (type != null) {
      return Categories.of(type);
    }
    return {
      ...Categories.expenseCategories,
      ...Categories.incomeCategories,
      ...Categories.neutralCategories,
    }.toList();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await BillService.list(
        month: _month == _allMonths ? null : _month,
        type: _typeValue,
        category: _category == _allCategories ? null : _category,
        source: _sourceValue,
        keyword: _keyword.isEmpty ? null : _keyword,
        minAmount: _minAmount.isEmpty ? null : _minAmount,
        maxAmount: _maxAmount.isEmpty ? null : _maxAmount,
        page: 1,
        size: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _bills
          ..clear()
          ..addAll(result.list);
        _page = 1;
        _total = result.total;
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

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || _bills.length >= _total) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final result = await BillService.list(
        month: _month == _allMonths ? null : _month,
        type: _typeValue,
        category: _category == _allCategories ? null : _category,
        source: _sourceValue,
        keyword: _keyword.isEmpty ? null : _keyword,
        minAmount: _minAmount.isEmpty ? null : _minAmount,
        maxAmount: _maxAmount.isEmpty ? null : _maxAmount,
        page: next,
        size: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _bills.addAll(result.list);
        _page = next;
        _total = result.total;
        _loadingMore = false;
      });
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _openEdit({Bill? bill}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BillEditPage(bill: bill)),
    );
    if (saved == true) {
      widget.onBillsChanged?.call();
      await _reload();
    }
  }

  Future<void> _openDetail(Bill bill) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BillDetailPage(billId: bill.id)),
    );
    if (changed == true) {
      widget.onBillsChanged?.call();
      await _reload();
    }
  }

  Future<void> _openImport() async {
    final imported = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ImportPage()),
    );
    if (imported == true) {
      widget.onBillsChanged?.call();
      await _reload();
    }
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportHistoryPage()),
    );
  }

  /// 左滑删除：先弹确认框，用户确认后再调接口，失败时把列表恢复回去
  Future<bool> _confirmAndDelete(Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔账单？'),
        content: Text(
          '${bill.category}　¥${Money.format(bill.amount)}\n删除后无法恢复。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) {
      return false;
    }
    try {
      await BillService.delete(bill.id);
      if (!mounted) {
        return false;
      }
      // 本地先移除，列表立刻有反馈；再拉一次保证分组小计与总数准确
      setState(() {
        _bills.removeWhere((item) => item.id == bill.id);
        _total = _total > 0 ? _total - 1 : 0;
      });
      widget.onBillsChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账单已删除')),
      );
      await _reload();
      return true;
    } on ApiException catch (e) {
      if (!mounted) {
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      // 删除失败时重新拉取，避免界面与服务端不一致
      await _reload();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账单'),
        actions: [
          IconButton(
            onPressed: _openImport,
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: '导入账单',
          ),
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
            tooltip: '导入记录',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExportPage()),
            ),
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '数据导出',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          _buildSummary(),
          Expanded(child: _buildList()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _dropdown<String>(
                    label: '月份',
                    value: _month,
                    items: [_allMonths, ...Formatters.recentMonths()],
                    onChanged: (value) {
                      setState(() => _month = value ?? _allMonths);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dropdown<String>(
                    label: '类型',
                    value: _typeLabel,
                    items: [_allTypes, '支出', '收入', '不计收支'],
                    onChanged: (value) {
                      setState(() {
                        _typeLabel = value ?? _allTypes;
                        if (!_categoryOptions.contains(_category)) {
                          _category = _allCategories;
                        }
                      });
                      _reload();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _dropdown<String>(
                    label: '分类',
                    value: _category,
                    items: [_allCategories, ..._categoryOptions],
                    onChanged: (value) {
                      setState(() => _category = value ?? _allCategories);
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dropdown<String>(
                    label: '来源',
                    value: _source,
                    items: [_allSources, '手动记录', '微信', '支付宝'],
                    onChanged: (value) {
                      setState(() => _source = value ?? _allSources);
                      _reload();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _keywordController,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索交易对象或备注',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _keywordController.clear();
                    setState(() => _keyword = '');
                    _reload();
                  },
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                setState(() => _keyword = value.trim());
                _reload();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '最小金额',
                      hintText: '不限',
                      prefixText: '¥',
                      border: const OutlineInputBorder(),
                      suffixIcon: _minAmount.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: '清除最小金额',
                              onPressed: () {
                                _minAmountController.clear();
                                setState(() => _minAmount = '');
                                _reload();
                              },
                            ),
                    ),
                    onChanged: (value) => _onAmountChanged(value, isMin: true),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('至', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                Expanded(
                  child: TextField(
                    controller: _maxAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '最大金额',
                      hintText: '不限',
                      prefixText: '¥',
                      border: const OutlineInputBorder(),
                      suffixIcon: _maxAmount.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: '清除最大金额',
                              onPressed: () {
                                _maxAmountController.clear();
                                setState(() => _maxAmount = '');
                                _reload();
                              },
                            ),
                    ),
                    onChanged: (value) => _onAmountChanged(value, isMin: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        DropdownButton<T>(
          value: safeValue,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: items
              .map((item) => DropdownMenuItem<T>(value: item, child: Text('$item')))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSummary() {
    if (_loading || _error != null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('共 $_total 条记录', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          Text(
            _bills.length < _total ? '已显示 ${_bills.length} 条' : '',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
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
            OutlinedButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_bills.isEmpty) {
      final hasFilter = _hasFilter;
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          // 给右下角的“记一笔”按钮留出空间，避免遮住内容
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            const SizedBox(height: 80),
            EmptyView(
              icon: hasFilter ? Icons.search_off : Icons.receipt_long_outlined,
              title: hasFilter ? '没有找到相关账单' : '还没有记账记录',
              subtitle: hasFilter
                  ? '换个关键词或调整筛选条件试试'
                  : '点击右下角「记一笔」，或从微信/支付宝导入账单',
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('清除筛选条件'),
                ),
              ),
            ],
          ],
        ),
      );
    }
    final rows = _buildRows();
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: rows.length + 1,
        itemBuilder: (context, index) {
          if (index == rows.length) {
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text('正在加载更多…', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            }
            if (_bills.length >= _total) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '已经到底了',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ),
              );
            }
            // 还没到底且当前不在加载：提示继续下滑加载
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('上滑加载更多', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            );
          }
          final row = rows[index];
          if (row.label != null) {
            return _buildDateHeader(row.label!, row.summary ?? '');
          }
          final bill = row.bill!;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Dismissible(
              key: ValueKey('bill-${bill.id}'),
              direction: DismissDirection.endToStart,
              background: _buildDeleteBackground(),
              // 用确认框的返回值决定是否真的移除，避免误滑直接删掉数据
              confirmDismiss: (_) => _confirmAndDelete(bill),
              child: Card(
                child: BillTile(
                  bill: bill,
                  showDate: false,
                  onTap: () => _openDetail(bill),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 把账单按天铺平成「日期标题 + 账单」的行序列
  List<_BillRow> _buildRows() {
    final rows = <_BillRow>[];
    for (final group in BillGrouping.group(_bills)) {
      rows.add(_BillRow.header(Formatters.groupLabel(group.date), _daySummary(group)));
      for (final bill in group.bills) {
        rows.add(_BillRow.bill(bill));
      }
    }
    return rows;
  }

  Widget _buildDateHeader(String label, String summary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.brown.shade400,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            summary,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  /// 左滑露出的删除背景
  Widget _buildDeleteBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: Brand.expense,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: Colors.white, size: 20),
          SizedBox(width: 6),
          Text('删除', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// 分组标题右侧的当天收支合计
  String _daySummary(BillDateGroup group) {
    final parts = <String>[];
    if (group.expense != '0.00') {
      parts.add('支出 ¥${group.expense}');
    }
    if (group.income != '0.00') {
      parts.add('收入 ¥${group.income}');
    }
    return parts.join(' · ');
  }
}

/// 列表行：日期标题或一条账单
class _BillRow {
  const _BillRow.header(this.label, this.summary) : bill = null;

  const _BillRow.bill(this.bill) : label = null, summary = null;

  final String? label;
  final String? summary;
  final Bill? bill;
}
