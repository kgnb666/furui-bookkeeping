import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/services/bill_service.dart';
import 'package:campus_ledger/widgets/bill_form.dart';

/// 快速记账：只保留金额、收支类型、分类、日期，商户与备注收在「更多选项」。
/// 表单组件与完整编辑页共用（BillForm），不重复实现校验与保存逻辑。
class QuickAddPage extends StatefulWidget {
  const QuickAddPage({super.key});

  @override
  State<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends State<QuickAddPage> {
  bool _saving = false;
  String? _error;

  Future<void> _save(BillFormData data) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await BillService.create(
        type: data.type,
        amount: data.amount,
        category: data.category,
        billDate: data.billDate,
        merchant: data.merchant,
        remark: data.remark,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记账成功')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('快速记账'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '3 秒记一笔',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: BillForm(
          quickMode: true,
          submitting: _saving,
          submitLabel: '保存',
          errorText: _error,
          onSubmit: _save,
        ),
      ),
    );
  }
}
