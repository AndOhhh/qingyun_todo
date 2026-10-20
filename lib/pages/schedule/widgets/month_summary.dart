import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_groups.dart';

/// 日程页当月概览（9）：本月 N 项 / 已完成 M / 完成率。
///
/// 直接复用月历标记的聚合结果（`monthMarkersProvider`），不新增查询。
class MonthSummary extends StatelessWidget {
  final Map<String, DayMarkers> markers;

  const MonthSummary({super.key, required this.markers});

  @override
  Widget build(BuildContext context) {
    var total = 0;
    var done = 0;
    for (final marker in markers.values) {
      total += marker.pending + marker.done;
      done += marker.done;
    }
    if (total == 0) return const SizedBox.shrink();
    final rate = ((done / total) * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '本月 $total 项',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1C1E),
                ),
              ),
              const Spacer(),
              Text(
                '已完成 $done',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
              const SizedBox(width: 8),
              Text(
                '$rate%',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF007AFF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 4,
              backgroundColor: const Color(0xFFE5E5EA),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF007AFF)),
            ),
          ),
        ],
      ),
    );
  }
}
