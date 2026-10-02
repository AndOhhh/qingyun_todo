import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo.dart';

/// 待办页分组种类（docs/07 B1-2，Q10 决策：五组替代旧「待处理 / 已完成」两组）
enum TodoGroupKind { overdue, today, tomorrow, later, completed }

/// 单个分组：标题、标题色、组内条目
class TodoGroup {
  final TodoGroupKind kind;
  final String title;
  final Color color;
  final List<Todo> items;

  /// 是否可折叠（仅「已完成」组）
  final bool collapsible;

  const TodoGroup({
    required this.kind,
    required this.title,
    required this.color,
    required this.items,
    this.collapsible = false,
  });

  bool get isEmpty => items.isEmpty;
  int get count => items.length;
}

/// 待办页分组结果：一次查询取回后在 Dart 侧分桶（docs/02 §8.1）。
///
/// 逾期**不是字段**，一律由 `remind_date < today AND is_completed = 0` 实时派生。
class TodoGroups {
  /// `is_completed = 0 AND remind_date < today`
  final List<Todo> overdue;

  /// `is_completed = 0 AND remind_date = today`
  final List<Todo> today;

  /// `is_completed = 0 AND remind_date = today + 1`
  final List<Todo> tomorrow;

  /// `is_completed = 0 AND remind_date > today + 1`
  final List<Todo> later;

  /// `is_completed = 1`，按 `completed_at DESC`
  final List<Todo> completed;

  const TodoGroups({
    this.overdue = const <Todo>[],
    this.today = const <Todo>[],
    this.tomorrow = const <Todo>[],
    this.later = const <Todo>[],
    this.completed = const <Todo>[],
  });

  static const Color _kOverdueColor = Color(0xFFFF3B30);
  static const Color _kNormalColor = Color(0xFF1C1C1E);
  static const Color _kMutedColor = Color(0xFF8E8E93);

  /// 对查询结果分桶并做组内排序
  factory TodoGroups.from(List<Todo> all) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    final overdue = <Todo>[];
    final todayList = <Todo>[];
    final tomorrowList = <Todo>[];
    final later = <Todo>[];
    final completed = <Todo>[];

    for (final t in all) {
      if (t.isCompleted) {
        completed.add(t);
        continue;
      }
      final d = DateTime(t.remindDate.year, t.remindDate.month, t.remindDate.day);
      if (d.isBefore(today)) {
        overdue.add(t);
      } else if (d == today) {
        todayList.add(t);
      } else if (d == tomorrow) {
        tomorrowList.add(t);
      } else {
        later.add(t);
      }
    }

    // 组内排序（docs/07 B1-2）：日期组按 提醒日期 → 提醒时间(NULL 最后) → sort_order
    int byDateThenTime(Todo a, Todo b) {
      final c = a.remindDate.compareTo(b.remindDate);
      if (c != 0) return c;
      return byTime(a, b);
    }

    overdue.sort(byDateThenTime);
    later.sort(byDateThenTime);
    todayList.sort(byTime);
    tomorrowList.sort(byTime);
    // 已完成：completed_at DESC（无完成时间的排最后）
    completed.sort((a, b) {
      final at = a.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });

    return TodoGroups(
      overdue: overdue,
      today: todayList,
      tomorrow: tomorrowList,
      later: later,
      completed: completed,
    );
  }

  /// 提醒时间升序，NULL 排最后，再按 sort_order
  static int byTime(Todo a, Todo b) {
    final at = a.remindTime;
    final bt = b.remindTime;
    if (at == null && bt != null) return 1;
    if (at != null && bt == null) return -1;
    if (at != null && bt != null) {
      final c = at.compareTo(bt);
      if (c != 0) return c;
    }
    return a.sortOrder.compareTo(b.sortOrder);
  }

  /// 五个分组（含空组，页面自行跳过不渲染）
  List<TodoGroup> get sections => <TodoGroup>[
        TodoGroup(
          kind: TodoGroupKind.overdue,
          title: '逾期',
          color: _kOverdueColor,
          items: overdue,
        ),
        TodoGroup(
          kind: TodoGroupKind.today,
          title: '今天',
          color: _kNormalColor,
          items: today,
        ),
        TodoGroup(
          kind: TodoGroupKind.tomorrow,
          title: '明天',
          color: _kNormalColor,
          items: tomorrow,
        ),
        TodoGroup(
          kind: TodoGroupKind.later,
          title: '后续',
          color: _kMutedColor,
          items: later,
        ),
        TodoGroup(
          kind: TodoGroupKind.completed,
          title: '已完成',
          color: _kMutedColor,
          items: completed,
          collapsible: true,
        ),
      ];

  /// 未完成总数
  int get pendingCount =>
      overdue.length + today.length + tomorrow.length + later.length;

  /// 全部条目（含已完成）
  int get totalCount => pendingCount + completed.length;

  /// 库里一条记录都没有
  bool get isEmpty => totalCount == 0;
}

/// 今日进度数据（仅统计 `remind_date = today`，含周期实例，docs/02 §8.3）
class TodayProgressData {
  final int total;
  final int done;

  const TodayProgressData({required this.total, required this.done});

  static const TodayProgressData empty = TodayProgressData(total: 0, done: 0);

  double get rate => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  int get remaining => total - done > 0 ? total - done : 0;

  bool get allDone => total > 0 && done >= total;
}

/// 日程页：某一天在月历上的标记数据（docs/01 FR-16）
class DayMarkers {
  /// 未完成条数
  final int pending;

  /// 已完成条数
  final int done;

  const DayMarkers({required this.pending, required this.done});

  static const DayMarkers empty = DayMarkers(pending: 0, done: 0);

  bool get isEmpty => pending == 0 && done == 0;

  /// 该日是否仍有未完成（含逾期，逾期由调用方按日期与今天比较判定颜色）
  bool get hasPending => pending > 0;

  bool get allDone => pending == 0 && done > 0;
}
