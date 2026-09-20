import 'package:flutter/material.dart';

import 'package:campus_ledger/models/api_exception.dart';
import 'package:campus_ledger/models/user.dart';
import 'package:campus_ledger/pages/change_password_page.dart';
import 'package:campus_ledger/pages/edit_profile_page.dart';
import 'package:campus_ledger/pages/export_page.dart';
import 'package:campus_ledger/pages/import_history_page.dart';
import 'package:campus_ledger/pages/login_page.dart';
import 'package:campus_ledger/services/auth_service.dart';
import 'package:campus_ledger/utils/brand.dart';

/// 我的：资料、修改密码、导入记录、关于、退出登录
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user = AuthService.currentUser;
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final user = await AuthService.loadProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _user = user;
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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新输入用户名和密码。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await AuthService.logout();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: Brand.name,
      applicationVersion: Brand.version,
      applicationIcon: Image.asset(
        'assets/brand/app_icon_rounded.png',
        width: 40,
        height: 40,
        filterQuality: FilterQuality.medium,
      ),
      children: const [
        Text('${Brand.englishName}\n${Brand.slogan}'),
        SizedBox(height: 12),
        Text('课程设计项目：支持手动记账、微信/支付宝账单导入、收支统计与预算管理。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        (user != null && user.nickname.isNotEmpty)
                            ? user.nickname.substring(0, 1)
                            : '账',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _loading ? '加载中…' : (user?.nickname ?? '-'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user == null ? '' : '@${user.username}',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                          ),
                          if (_error != null)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: theme.colorScheme.error),
                                  ),
                                ),
                                TextButton(onPressed: _load, child: const Text('重试')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('个人资料'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final changed = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => const EditProfilePage()),
                      );
                      if (changed == true) {
                        await _load();
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('修改密码'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('导入记录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ImportHistoryPage()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('数据导出'),
                    subtitle: const Text('导出自己的账单为 CSV / Excel / JSON'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ExportPage()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('关于'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showAbout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.logout, color: theme.colorScheme.error),
                title: Text('退出登录', style: TextStyle(color: theme.colorScheme.error)),
                onTap: _logout,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
