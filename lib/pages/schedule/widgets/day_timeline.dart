import 'package:flutter/material.dart';

import 'package:qingyun_todo/components/todo_tag.dart';
import 'package:qingyun_todo/models/todo.dart';

/// 当日时间轴（2a）：0–24h 轨道 + 每个带提醒时间的任务一个刻度点。
///
/// 数据模型只有**单个提醒时间点**（无结束时间），因此这里画刻度点而非区间条；
/// 「全天」（无 `remind_time`）的任务在轨道左侧以独立标签呈现，不占时间位置。
/// 等 schema 支持时间段后（待确认项 2b），可把刻度点升级为区间条。
class DayTimeline extends StatelessWidget {
  final List<Todo> tasks;

  const DayTimeline({super.key, required this.tasks});

  static const List<int> _hourLabels = <int>[0, 6, 12, 18, 24];

  static const Color _kRed = Color(0xFFFF3B30);
  static const Color _kBlue = Color(0xFF007AFF);
  static const Color _kGreen = Color(0xFF34C759);
  static const Color _kMuted = Color(0xFF8E8E93);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final timed = tasks.where((t) => t.remindTime != null).toList(growable: false);
    final allDayCount = tasks.length - timed.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (allDayCount > 0) ...<Widget>[
                TodoTag(text: '全天 $allDayCount', color: _kMuted),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SizedBox(
                    height: 10,
                    child: Stack(
                      children: <Widget>[
                        // 轨道
                        Positioned.fill(
                          top: 2,
                          bottom: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5E5EA),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        for (final task in timed)
                          Positioned(
                            left: _offsetX(task.remindTime!, constraints.maxWidth),
                            top: 1,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _dotColor(task, today),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.2),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final hour in _hourLabels)
                Text(
                  '$hour',
                  style: const TextStyle(fontSize: 9.5, color: _kMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// `HH:mm` → 0~1 的位置比例
  static double fractionOf(String time) {
    final parts = time.split(':');
    final minutes =
        (int.tryParse(parts[0]) ?? 0) * 60 + (parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0);
    return (minutes / (24 * 60)).clamp(0.0, 1.0);
  }

  double _offsetX(String time, double width) =>
      (fractionOf(time) * (width - 8)).clamp(0.0, width - 8);

  Color _dotColor(Todo task, DateTime today) {
    if (task.isCompleted) return _kGreen;
    if (task.remindDate.isBefore(today)) return _kRed;
    return _kBlue;
  }
}
