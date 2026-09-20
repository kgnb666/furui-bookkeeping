import 'package:flutter/material.dart';

import 'package:campus_ledger/pages/bill_list_page.dart';
import 'package:campus_ledger/pages/home_page.dart';
import 'package:campus_ledger/pages/profile_page.dart';
import 'package:campus_ledger/pages/statistics_page.dart';

/// 底部导航：首页 / 账单 / 统计 / 我的
class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _index = 0;

  // 切换到某个页签时通知对应页面刷新数据，避免看到过期内容
  final ValueNotifier<int> _homeRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _billRefresh = ValueNotifier<int>(0);
  // 首页记完账、账单页删改之后，切到统计页也要看到最新数据
  final ValueNotifier<int> _statisticsRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _homeRefresh.dispose();
    _billRefresh.dispose();
    _statisticsRefresh.dispose();
    super.dispose();
  }

  void _onSelect(int index) {
    setState(() => _index = index);
    if (index == 0) {
      _homeRefresh.value++;
    } else if (index == 1) {
      _billRefresh.value++;
    } else if (index == 2) {
      _statisticsRefresh.value++;
    }
  }

  /// 账单发生变化（新增 / 修改 / 删除 / 导入）后，通知首页与统计页重新取数
  void _onBillsChanged() {
    _homeRefresh.value++;
    _statisticsRefresh.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(
            refresh: _homeRefresh,
            onOpenBills: () => _onSelect(1),
            onOpenStatistics: () => _onSelect(2),
            onBillsChanged: _onBillsChanged,
          ),
          BillListPage(refresh: _billRefresh, onBillsChanged: _onBillsChanged),
          StatisticsPage(refresh: _statisticsRefresh),
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: '账单'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: '统计'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
