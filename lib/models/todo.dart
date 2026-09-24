import 'package:flutter/material.dart';

/// 待办优先级
enum TodoPriority {
  none,
  low,
  medium,
  high;

  Color get color {
    switch (this) {
      case TodoPriority.high:
        return const Color(0xFFFF3B30);
      case TodoPriority.medium:
        return const Color(0xFFFF9500);
      case TodoPriority.low:
        return const Color(0xFF8E8E93);
      case TodoPriority.none:
        return Colors.transparent;
    }
  }
}

/// Todo 数据模型（VO）
class Todo {
  final String id;
  final String title;
  final String? note;
  final DateTime? dueDate;
  final bool isPeriodic;
  final bool isOverdue;
  final int subDone;
  final int subTotal;
  final TodoPriority priority;
  bool done;
  final Color accentColor;

  Todo({
    required this.id,
    required this.title,
    this.note,
    this.dueDate,
    this.isPeriodic = false,
    this.isOverdue = false,
    this.subDone = 0,
    this.subTotal = 0,
    this.priority = TodoPriority.none,
    this.done = false,
    this.accentColor = const Color(0xFF007AFF),
  });

  /// 截止日期的展示文案：今天 / 明天 / 昨天 / N 天后 / M/D
  String get dueDateLabel {
    final d = dueDate;
    if (d == null) return '';
    final now = DateTime.now();
    final diff = d.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '明天';
    if (diff == -1) return '昨天';
    if (diff > 0 && diff < 7) return '$diff 天后';
    return '${d.month}/${d.day}';
  }
}
