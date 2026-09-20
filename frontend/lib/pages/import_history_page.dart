import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/import_preview.dart';
import 'package:campus_ledger/services/import_service.dart';
import 'package:campus_ledger/utils/formatters.dart';
import 'package:campus_ledger/widgets/empty_view.dart';

/// 导入历史：只读列表，本阶段不做回滚
class ImportHistoryPage extends StatefulWidget {
  const ImportHistoryPage({super.key});

  @override
  State<ImportHistoryPage> createState() => _ImportHistoryPageState();
}

class _ImportHistoryPageState extends State<ImportHistoryPage> {
  List<ImportBatch>? _batches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final batches = await ImportService.batches();
      if (!mounted) {
        return;
      }
      setState(() => _batches = batches);
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入记录')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
    final batches = _batches;
    if (batches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (batches.isEmpty) {
      return const EmptyView(
        icon: Icons.history,
        title: '暂无导入记录',
        subtitle: '在账单页点击右上角“导入账单”开始导入',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: batches.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final batch = batches[index];
          return ListTile(
            leading: CircleAvatar(
              child: Icon(batch.source == 'WECHAT' ? Icons.chat_bubble_outline : Icons.account_balance_wallet_outlined),
            ),
            title: Text('${batch.sourceName} · ${batch.fileName}'),
            subtitle: Text(
              '${Formatters.dateTime(batch.createdAt)}　共 ${batch.totalCount} 条',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: Text(
              '导入 ${batch.importedCount}\n重复 ${batch.duplicateCount}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}
