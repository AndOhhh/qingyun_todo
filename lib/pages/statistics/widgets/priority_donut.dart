import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/pages/statistics/widgets/stat_card.dart';

/// A2 优先级分布环形图（用各级规范色）+ 图例
class PriorityDonut extends StatelessWidget {
  final List<PrioritySlice> slices;

  const PriorityDonut({super.key, required this.slices});

  @override
  Widget build(BuildContext context) {
    final visible = slices.where((s) => s.total > 0).toList(growable: false);
    if (visible.isEmpty) return const ChartEmpty();
    final total = visible.fold<int>(0, (a, s) => a + s.total);

    return Row(
      children: <Widget>[
        SizedBox(
          width: 120,
          height: 120,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 34,
              sections: <PieChartSectionData>[
                for (final s in visible)
                  PieChartSectionData(
                    value: s.total.toDouble(),
                    color: s.priority.donutColor,
                    radius: 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '共 $total 项',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const SizedBox(height: 8),
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: s.priority.donutColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.priority.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF636366),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${s.total}（完成 ${s.done}）',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 无优先级时的兜底色（`TodoPriority.none.color` 为主色蓝，环形图里改用灰，
/// 避免与图表主色混淆）
extension PriorityDonutColor on TodoPriority {
  Color get donutColor =>
      this == TodoPriority.none ? const Color(0xFFC7C7CC) : color;
}
