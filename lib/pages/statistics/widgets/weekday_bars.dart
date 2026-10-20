import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/pages/statistics/widgets/stat_card.dart';

/// A3 星期分布柱状图：一周中哪天任务最集中（按 `remind_date`）
class WeekdayBars extends StatelessWidget {
  final List<WeekdayBar> bars;

  const WeekdayBars({super.key, required this.bars});

  static const Color _kBlue = Color(0xFF007AFF);
  static const List<String> _labels = <String>[
    '一', '二', '三', '四', '五', '六', '日',
  ];

  @override
  Widget build(BuildContext context) {
    final maxCount = bars.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    if (maxCount == 0) return const ChartEmpty();
    final peak = bars.reduce((a, b) => b.count > a.count ? b : a);

    return Column(
      children: <Widget>[
        SizedBox(
          height: 130,
          child: BarChart(
            BarChartData(
              maxY: (maxCount * 1.25).toDouble(),
              minY: 0,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(enabled: false),
              barGroups: <BarChartGroupData>[
                for (var i = 0; i < bars.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: <BarChartRodData>[
                      BarChartRodData(
                        toY: bars[i].count.toDouble(),
                        color: bars[i].weekday == peak.weekday
                            ? _kBlue
                            : _kBlue.withValues(alpha: 0.45),
                        width: 16,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            for (final label in _labels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFAEAEB2),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '最集中在周${_labels[peak.weekday - 1]}（${peak.count} 项）',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF8E8E93)),
          ),
        ),
      ],
    );
  }
}
