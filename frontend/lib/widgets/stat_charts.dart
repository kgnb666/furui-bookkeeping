import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:campus_ledger/models/statistics.dart';
import 'package:campus_ledger/utils/money.dart';

/// 分类支出环形图（数值用整数分，避免浮点误差）
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.categories});

  final List<CategoryStat> categories;

  /// 品牌色板：暖橙为主，账本绿与色相邻近色搭配，保证分类之间可区分
  static const List<Color> _colors = [
    Color(0xFFF5A524),
    Color(0xFF2E7D6F),
    Color(0xFFF7BE5B),
    Color(0xFF4E9F8F),
    Color(0xFFD64545),
    Color(0xFFE0A458),
    Color(0xFF8E7CC3),
    Color(0xFF5B8DEF),
    Color(0xFFB0BEC5),
    Color(0xFF9E9E9E),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < categories.length; i++) {
      final stat = categories[i];
      final value = Money.toCents(stat.amount).toDouble();
      if (value <= 0) {
        continue;
      }
      sections.add(PieChartSectionData(
        value: value,
        color: _colors[i % _colors.length],
        radius: 58,
        title: stat.percentage >= 8 ? '${stat.percentage.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
      ));
    }
    if (sections.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 180,
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: 38,
          sectionsSpace: 2,
        ),
      ),
    );
  }
}

/// 每日支出折线图
class DailyExpenseChart extends StatelessWidget {
  const DailyExpenseChart({super.key, required this.daily});

  final List<DailyStat> daily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = <FlSpot>[];
    var maxCents = 0;
    for (var i = 0; i < daily.length; i++) {
      final cents = Money.toCents(daily[i].expense);
      spots.add(FlSpot((i + 1).toDouble(), cents.toDouble()));
      if (cents > maxCents) {
        maxCents = cents;
      }
    }
    // 全部为 0 时给一个默认的纵轴高度，避免图表报错
    final maxY = maxCents == 0 ? 100.0 : maxCents * 1.2;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 1,
          maxX: daily.isEmpty ? 1 : daily.length.toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (value, meta) => Text(
                  Money.fromCents(value.round()),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  final day = value.round();
                  if (day < 1 || day > daily.length) {
                    return const SizedBox.shrink();
                  }
                  return Text('$day', style: const TextStyle(fontSize: 10, color: Colors.grey));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              barWidth: 2,
              color: theme.colorScheme.primary,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
