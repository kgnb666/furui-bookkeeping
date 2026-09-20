import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/models/insight.dart';
import 'package:campus_ledger/services/insight_service.dart';
import 'package:campus_ledger/utils/categories.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/utils/money.dart';
import 'package:campus_ledger/widgets/smart_recommend_card.dart';

/// 账单表单的数据。快速记账与完整编辑共用同一份数据结构与校验。
class BillFormData {
  BillFormData({
    required this.type,
    required this.amount,
    required this.category,
    required this.billDate,
    this.merchant = '',
    this.remark = '',
  });

  final int type;
  final String amount;
  final String category;

  /// yyyy-MM-dd
  final String billDate;
  final String merchant;
  final String remark;
}

/// 账单表单：金额、收支类型、分类、日期、商户、备注。
///
/// [quickMode] 为 true 时隐藏商户与备注（收在「更多选项」里），用于快速记账；
/// 保存动作由外层页面负责，表单只负责收集数据与校验，避免两套表单逻辑。
class BillForm extends StatefulWidget {
  const BillForm({
    super.key,
    this.bill,
    this.quickMode = false,
    required this.onSubmit,
    required this.submitLabel,
    this.submitting = false,
    this.errorText,
    this.footer,
  });

  /// 编辑时传入原账单，新增时为 null
  final Bill? bill;
  final bool quickMode;

  /// 校验通过后回调，由外层决定是新增还是修改
  final Future<void> Function(BillFormData data) onSubmit;
  final String submitLabel;
  final bool submitting;
  final String? errorText;

  /// 表单下方的额外内容（例如编辑页的「删除这笔账单」）
  final Widget? footer;

  @override
  State<BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<BillForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  final _remarkController = TextEditingController();

  late int _type;
  late String _category;
  late DateTime _date;
  bool _showMore = false;

  /// 智能推荐：只作为建议，用户点「使用推荐」才会改变分类
  CategoryRecommend? _recommend;
  bool _recommendLoading = false;
  bool _recommendApplied = false;
  int _recommendRequest = 0;
  Timer? _recommendDebounce;

  @override
  void initState() {
    super.initState();
    final bill = widget.bill;
    _type = bill?.type ?? Categories.expense;
    _category = bill?.category ?? Categories.of(_type).first;
    _date = bill == null
        ? DateTime.now()
        : (DateTime.tryParse(bill.billDate) ?? DateTime.now());
    if (bill != null) {
      _amountController.text = bill.amount;
      _merchantController.text = bill.merchant;
      _remarkController.text = bill.remark;
      // 已有商户或备注时直接展开，避免用户以为数据丢了
      _showMore = bill.merchant.isNotEmpty || bill.remark.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _recommendDebounce?.cancel();
    _amountController.dispose();
    _merchantController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  /// 商户/备注输入后延迟 600ms 再请求推荐，避免每敲一个字就查一次
  void _onTextChanged() {
    _recommendDebounce?.cancel();
    _recommendDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        _loadRecommend();
      }
    });
  }

  void _onTypeChanged(int type) {
    setState(() {
      _type = type;
      // 分类必须跟着类型走，否则后端会判定分类不合法
      if (!Categories.of(type).contains(_category)) {
        _category = Categories.of(type).first;
      }
      // 收支类型变了，之前的推荐不再适用
      _recommend = null;
      _recommendApplied = false;
    });
  }

  /// 根据当前填写的商户/备注拉取推荐；没有可依据的文本时清空推荐，
  /// 避免系统凭分类名反推出来一个"看起来像推荐"的结果。
  Future<void> _loadRecommend() async {
    final merchant = _merchantController.text.trim();
    final note = _remarkController.text.trim();
    if (merchant.isEmpty && note.isEmpty) {
      if (mounted) {
        setState(() {
          _recommend = null;
          _recommendLoading = false;
        });
      }
      return;
    }
    final request = ++_recommendRequest;
    setState(() {
      _recommendLoading = true;
      _recommendApplied = false;
    });
    try {
      final result = await InsightService.recommend(
        type: _type,
        merchant: merchant,
        note: note,
      );
      // 只接受最后一次请求的结果，避免快速输入时旧结果覆盖新结果
      if (!mounted || request != _recommendRequest) {
        return;
      }
      setState(() {
        _recommend = result;
        _recommendLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _recommendRequest) {
        return;
      }
      // 推荐失败不影响记账主流程，静默降级为"暂无推荐"
      setState(() {
        _recommend = null;
        _recommendLoading = false;
      });
    }
  }

  /// 应用推荐：只切换分类，仍然需要用户点保存才会写库
  void _applyRecommend() {
    final suggestion = _recommend;
    if (suggestion == null || suggestion.category == null) {
      return;
    }
    if (!Categories.of(_type).contains(suggestion.category)) {
      return;
    }
    setState(() {
      _category = suggestion.category!;
      _recommendApplied = true;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: '选择日期',
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _submit() async {
    if (widget.submitting) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    await widget.onSubmit(BillFormData(
      type: _type,
      amount: _amountController.text.trim(),
      category: _category,
      billDate: Formatters.apiDate(_date),
      merchant: _merchantController.text.trim(),
      remark: _remarkController.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('支出')),
              ButtonSegment(value: 2, label: Text('收入')),
              ButtonSegment(value: 3, label: Text('不计收支')),
            ],
            selected: {_type},
            onSelectionChanged: (selection) => _onTypeChanged(selection.first),
          ),
          const SizedBox(height: 16),
          _buildAmountField(theme),
          const SizedBox(height: 12),
          SmartRecommendCard(
            recommend: _recommend,
            loading: _recommendLoading,
            dismissed: _recommendApplied,
            onApply: _recommend?.hasSuggestion == true ? _applyRecommend : null,
          ),
          const SizedBox(height: 12),
          _buildCategoryChips(theme),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '日期',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(Formatters.fullDate(Formatters.apiDate(_date))),
            ),
          ),
          if (widget.quickMode)
            _buildMoreOptions(theme)
          else ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _merchantController,
              maxLength: 64,
              onChanged: (_) => _onTextChanged(),
              decoration: const InputDecoration(
                labelText: '交易对象 / 商户',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _remarkController,
              maxLength: 255,
              maxLines: 2,
              onChanged: (_) => _onTextChanged(),
              decoration: const InputDecoration(
                labelText: '备注',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          if (widget.errorText != null) ...[
            const SizedBox(height: 12),
            Text(widget.errorText!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: widget.submitting ? null : _submit,
              child: widget.submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.submitLabel),
            ),
          ),
          if (widget.footer != null) ...[
            const SizedBox(height: 12),
            widget.footer!,
          ],
        ],
      ),
    );
  }

  /// 金额输入：大号字 + 自动聚焦，配合快速记账做到"打开就能输入"
  Widget _buildAmountField(ThemeData theme) {
    return TextFormField(
      controller: _amountController,
      autofocus: widget.quickMode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: widget.quickMode
          ? theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)
          : null,
      decoration: InputDecoration(
        labelText: '金额',
        prefixText: '¥ ',
        border: const OutlineInputBorder(),
        hintText: widget.quickMode ? '0.00' : null,
      ),
      validator: Money.validate,
    );
  }

  /// 分类用可点选的 chip，比下拉少一次点击
  Widget _buildCategoryChips(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in Categories.of(_type))
              ChoiceChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
          ],
        ),
      ],
    );
  }

  /// 快速记账把商户与备注收起来，保持主流程只有 4 步
  Widget _buildMoreOptions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showMore = !_showMore),
            icon: Icon(_showMore ? Icons.expand_less : Icons.expand_more, size: 18),
            label: Text(_showMore ? '收起更多选项' : '更多选项（商户 / 备注）'),
          ),
        ),
        if (_showMore) ...[
          TextFormField(
            controller: _merchantController,
            maxLength: 64,
            onChanged: (_) => _onTextChanged(),
            decoration: const InputDecoration(
              labelText: '交易对象 / 商户',
              border: OutlineInputBorder(),
            ),
          ),
          TextFormField(
            controller: _remarkController,
            maxLength: 255,
            maxLines: 2,
            onChanged: (_) => _onTextChanged(),
            decoration: const InputDecoration(
              labelText: '备注',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }
}
