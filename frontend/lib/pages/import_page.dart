import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/pages/import_preview_page.dart';
import 'package:campus_ledger/services/import_service.dart';

/// 导入账单第一步：选择来源 → 选择文件 → 上传解析 → 进入预览
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String? _source;
  String? _fileName;
  List<int>? _fileBytes;
  bool _loading = false;
  String? _error;

  String get _exportHint {
    if (_source == 'WECHAT') {
      return '微信：我 → 服务 → 钱包 → 账单 → 右上角“常见问题” → 下载账单 → 选择“用于个人对账” → 填写邮箱接收。'
          '收到的压缩包解压后，选择其中的 CSV 文件上传。';
    }
    if (_source == 'ALIPAY') {
      return '支付宝：我的 → 账单 → 右上角“…” → 开具交易流水证明 → 申请用途选择“用于个人对账” → 填写邮箱接收。'
          '收到的压缩包解压后，选择其中的 CSV 文件上传。';
    }
    return '请先选择账单来源，再选择从微信或支付宝导出的账单文件。';
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        dialogTitle: '选择账单文件',
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      setState(() {
        _fileName = picked.name;
        _fileBytes = bytes;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = '选择文件失败：$e');
      }
    }
  }

  Future<void> _startImport() async {
    if (_loading) {
      return;
    }
    if (_source == null) {
      setState(() => _error = '请先选择账单来源');
      return;
    }
    if (_fileBytes == null || _fileName == null) {
      setState(() => _error = '请先选择账单文件');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await ImportService.preview(
        source: _source!,
        bytes: _fileBytes!,
        fileName: _fileName!,
      );
      if (!mounted) {
        return;
      }
      final imported = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ImportPreviewPage(preview: preview)),
      );
      if (!mounted) {
        return;
      }
      if (imported == true) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('导入账单')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. 选择账单来源', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _sourceButton(
                              label: '微信',
                              value: 'WECHAT',
                              icon: Icons.chat_bubble_outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _sourceButton(
                              label: '支付宝',
                              value: 'ALIPAY',
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('2. 选择账单文件', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        '支持 CSV 与 Excel(.xlsx)，单个文件不超过 5MB',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _pickFile,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('选择文件'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _fileName ?? '尚未选择文件',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _fileName == null ? Colors.grey.shade600 : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _exportHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _startImport,
                  child: const Text('开始导入'),
                ),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在解析账单，请稍候…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceButton({required String label, required String value, required IconData icon}) {
    final selected = _source == value;
    return OutlinedButton.icon(
      onPressed: _loading
          ? null
          : () => setState(() {
                _source = value;
                _error = null;
              }),
      icon: Icon(icon),
      label: Text(selected ? '$label ✓' : label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      ),
    );
  }
}
