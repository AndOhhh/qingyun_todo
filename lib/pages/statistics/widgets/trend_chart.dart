import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/pages/statistics/widgets/stat_card.dart';

/// A1 完成趋势折线图（按 `completed_at` 归属）。
///
/// 轴标签极简处理：fl_chart 不画刻度文字，改用图表下方一行
/// 「首 / 中 / 末」标签，避免窄屏拥挤。
class TrendChart extends StatelessWidget {
  final List<TrendPoint> points;

  const TrendChart({super.key, required this.points});

  static const Color _kBlue = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const ChartEmpty();
    final maxY = points.fold<int>(0, (m, p) => p.count > m ? p.count : m);
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].count.toDouble()),
    ];
    final labels = <String>[
      points.first.label,
      if (points.length > 2) points[points.length ~/ 2].label,
      if (points.length > 1) points.last.label,
    ];

    return Column(
      children: <Widget>[
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble().clamp(1, double.infinity),
              minY: 0,
              maxY: (maxY < 1 ? 1 : maxY).toDouble(),
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
              ),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: LineTouchData(enabled: false),
              lineBarsData: <LineChartBarData>[
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  color: _kBlue,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: points.length <= 31),
                  belowBarData: BarAreaData(
                    show: true,
                    color: _kBlue.withValues(alpha: 0.10),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            for (final label in labels)
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: Color(0xFFAEAEB2)),
              ),
          ],
        ),
      ],
    );
  }
}
