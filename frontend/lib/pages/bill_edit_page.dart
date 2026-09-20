import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/bill.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/widgets/bill_form.dart';

/// 新增 / 编辑账单。bill 为空表示新增。
/// 表单本体与校验逻辑在 BillForm 中，与快速记账页共用。
/// 来源、去重信息由后端控制，不在表单中出现。
class BillEditPage extends StatefulWidget {
  const BillEditPage({super.key, this.bill});

  final Bill? bill;

  @override
  State<BillEditPage> createState() => _BillEditPageState();
}

class _BillEditPageState extends State<BillEditPage> {
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.bill != null;

  Future<void> _save(BillFormData data) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await BillService.update(
          widget.bill!.id,
          type: data.type,
          amount: data.amount,
          category: data.category,
          billDate: data.billDate,
          merchant: data.merchant,
          remark: data.remark,
        );
      } else {
        await BillService.create(
          type: data.type,
          amount: data.amount,
          category: data.category,
          billDate: data.billDate,
          merchant: data.merchant,
          remark: data.remark,
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? '账单已保存' : '记账成功')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final bill = widget.bill;
    if (bill == null || _saving) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔账单？'),
        content: const Text('删除后无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _saving = true);
    try {
      await BillService.delete(bill.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账单已删除')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑账单' : '记一笔')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BillForm(
              bill: widget.bill,
              submitting: _saving,
              submitLabel: '保存',
              errorText: _error,
              onSubmit: _save,
              footer: _isEdit
                  ? TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除这笔账单'),
                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    )
                  : null,
            ),
            // 来源由系统决定（手动记账 / 微信导入 / 支付宝导入），这里只做展示
            if (_isEdit && widget.bill != null) ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: '来源',
                  border: OutlineInputBorder(),
                  helperText: '来源由系统记录，导入的账单不能改成手动',
                ),
                child: Text(widget.bill!.sourceName.isEmpty ? '手动记录' : widget.bill!.sourceName),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
