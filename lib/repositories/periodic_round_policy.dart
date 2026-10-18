import 'dart:math' as math;

import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 单个已有实例的轮次与完成态 —— 生成引擎与展示层共用的**最小输入**，
/// 避免策略依赖具体查询形态。
class RoundInstance {
  final int cycleIndex;
  final bool isCompleted;

  const RoundInstance(this.cycleIndex, {required this.isCompleted});
}

/// 一轮一期（N13）：周期实例的「当前轮」口径。
///
/// 生成引擎与待办页**共用同一套规则**，避免两边各算一套导致
/// 「生成了一轮、却显示另一轮」。
///
/// 规则：
/// - **本轮** = 最早的未完成轮次；若该轮窗口已整轮走完（逾期），本轮顺延到
///   「今天所在轮」——错过的那一轮不再推进，**也不删除数据**；
/// - **全部完结 / 尚无实例**：本轮 = `max(今天所在轮, 已有最大轮次 + 1)`，
///   即「本轮完成（或整轮逾期）后才生成下一轮」；
/// - **待办页可见性**：每个周期只展示本轮的未完成实例；其他轮次的未完成实例
///   不展示（数据仍留在库里，日程页与统计口径不变）；
///   已完成实例一律保留，进入「已完成」分组作为历史。
class PeriodicRoundPolicy {
  const PeriodicRoundPolicy._();

  /// 单周期的本轮轮次（**纯函数**，单测覆盖）。
  static int currentRound({
    required CycleRule rule,
    required List<RoundInstance> instances,
    required DateTime today,
  }) {
    final day = DateUtil.dateOnly(today);
    // 今天所在轮（周期起始日晚于今天时取第 0 轮）
    final kToday = math.max(0, rule.cycleIndexOf(day));

    int? pendingMin;
    var last = -1;
    for (final instance in instances) {
      if (instance.cycleIndex > last) last = instance.cycleIndex;
      if (!instance.isCompleted &&
          (pendingMin == null || instance.cycleIndex < pendingMin)) {
        pendingMin = instance.cycleIndex;
      }
    }

    final pending = pendingMin;
    if (pending == null) {
      // 没有未完成实例：下一轮（但不早于今天所在轮，避免补生成历史）
      return math.max(kToday, last + 1);
    }
    final end = DateUtil.addDays(
      rule.cycleStart(pending),
      rule.cycleLength(pending) - 1,
    );
    if (end.isBefore(day)) {
      // 整轮逾期：顺延到今天所在轮
      return math.max(kToday, pending + 1);
    }
    return pending;
  }

  /// 每个周期的本轮轮次；只包含「库里有实例」的周期（key = periodicId）
  static Map<int, int> currentRounds({
    required List<Periodic> periodics,
    required List<Todo> tasks,
    required DateTime today,
  }) {
    final byPeriodic = <int, List<RoundInstance>>{};
    for (final task in tasks) {
      final periodicId = task.periodicId;
      final cycleIndex = task.cycleIndex;
      if (periodicId == null || cycleIndex == null) continue;
      byPeriodic
          .putIfAbsent(periodicId, () => <RoundInstance>[])
          .add(RoundInstance(cycleIndex, isCompleted: task.isCompleted));
    }

    final rounds = <int, int>{};
    for (final periodic in periodics) {
      final id = periodic.id;
      if (id == null) continue;
      final instances = byPeriodic[id];
      if (instances == null || instances.isEmpty) continue;
      rounds[id] = currentRound(
        rule: periodic.rule,
        instances: instances,
        today: today,
      );
    }
    return rounds;
  }

  /// 待办页可见性过滤（一轮一期）：非周期实例原样保留；
  /// 周期实例只保留「本轮」的未完成项与全部已完成项。
  static List<Todo> visibleOnTodoPage({
    required List<Todo> tasks,
    required List<Periodic> periodics,
    required DateTime today,
  }) {
    final rounds = currentRounds(
      periodics: periodics,
      tasks: tasks,
      today: today,
    );
    return <Todo>[
      for (final task in tasks)
        if (_isVisible(task, rounds)) task,
    ];
  }

  static bool _isVisible(Todo task, Map<int, int> rounds) {
    final periodicId = task.periodicId;
    if (periodicId == null) return true; // 常规待办
    if (task.isCompleted) return true; // 已完成：历史保留
    final current = rounds[periodicId];
    // 周期配置缺失（孤儿历史记录）时保守放行，不误伤用户数据
    if (current == null) return true;
    return task.cycleIndex == current;
  }
}
