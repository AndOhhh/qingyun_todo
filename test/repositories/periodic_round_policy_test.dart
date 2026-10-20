import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/repositories/periodic_round_policy.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 一轮一期（N13）口径：生成引擎与待办页展示共用的「当前轮」规则。
void main() {
  // 固定「今天」，避免测试随真实日期漂移
  final today = DateTime(2026, 10, 19);

  CycleRule rule({
    IntervalType type = IntervalType.day,
    int value = 2,
    DateTime? start,
  }) =>
      CycleRule(type: type, value: value, startDate: start ?? today);

  RoundInstance done(int k) => RoundInstance(k, isCompleted: true);
  RoundInstance pending(int k) => RoundInstance(k, isCompleted: false);

  group('currentRound：本轮口径', () {
    test('本轮未结束 → 本轮 = 最早的未完成轮次（更晚的实例不推进）', () {
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(),
          instances: <RoundInstance>[pending(0), pending(1), done(2)],
          today: today,
        ),
        0,
      );
      // 第 0 轮已完结、第 1 轮未完成且窗口未走完（每 5 天）→ 本轮 = 1
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(value: 5),
          instances: <RoundInstance>[done(0), pending(1)],
          today: DateUtil.addDays(today, 6),
        ),
        1,
      );
    });

    test('整轮逾期 → 顺延到「今天所在轮」', () {
      // 每 2 天：第 0 轮 = [今天, 今天+1]；推进 10 天 → 今天落在第 5 轮
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(),
          instances: <RoundInstance>[pending(0)],
          today: DateUtil.addDays(today, 10),
        ),
        5,
      );
    });

    test('全部完结 → 下一轮（不早于今天所在轮，且不补历史）', () {
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(),
          instances: <RoundInstance>[done(0)],
          today: today,
        ),
        1,
      );
      // 很晚才补完成：已有最大轮次落后于今天所在轮 → 取今天所在轮
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(value: 7),
          instances: <RoundInstance>[done(0)],
          today: DateUtil.addDays(today, 30),
        ),
        4, // 每 7 天：+30 天落在第 4 轮（+28 ~ +34）
      );
    });

    test('尚无实例 / 起始日在未来 → 第 0 轮', () {
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(),
          instances: const <RoundInstance>[],
          today: today,
        ),
        0,
      );
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: rule(start: DateUtil.addDays(today, 400)),
          instances: const <RoundInstance>[],
          today: today,
        ),
        0,
      );
    });

    test('MONTH：月末锚定轮同样按窗口逾期顺延', () {
      // 每月，起始 1/31；今天 3/1 时第 0 轮（1/31 ~ 2/27）已逾期 → 顺延到第 1 轮
      final monthly = CycleRule(
        type: IntervalType.month,
        value: 1,
        startDate: DateTime(2026, 1, 31),
      );
      expect(
        PeriodicRoundPolicy.currentRound(
          rule: monthly,
          instances: <RoundInstance>[pending(0)],
          today: DateTime(2026, 3, 1),
        ),
        1,
      );
    });
  });

  group('visibleOnTodoPage：待办页只展示本轮', () {
    Todo task({
      required int id,
      int? periodicId,
      int? cycleIndex,
      bool completed = false,
    }) =>
        Todo(
          id: id,
          title: 't$id',
          remindDate: today,
          isCompleted: completed,
          periodicId: periodicId,
          cycleIndex: cycleIndex,
          createdAt: today,
          updatedAt: today,
        );

    Periodic periodic({int id = 7}) => Periodic(
          id: id,
          name: '周期$id',
          startDate: today,
          intervalType: IntervalType.day,
          intervalValue: 2,
        );

    test('常规待办全部保留；周期只保留本轮的未完成项与已完成项', () {
      final tasks = <Todo>[
        task(id: 1), // 常规
        task(id: 2, periodicId: 7, cycleIndex: 0), // 本轮未完成 → 保留
        task(id: 3, periodicId: 7, cycleIndex: 1), // 未来轮次 → 隐藏
        task(id: 4, periodicId: 7, cycleIndex: 0, completed: true), // 历史 → 保留
        task(id: 5, periodicId: 7, cycleIndex: 9, completed: true), // 历史 → 保留
      ];
      final visible = PeriodicRoundPolicy.visibleOnTodoPage(
        tasks: tasks,
        periodics: <Periodic>[periodic()],
        today: today,
      );
      expect(visible.map((t) => t.id), <int?>[1, 2, 4, 5]);
    });

    test('本轮整轮逾期 → 展示顺延后的新一轮，错过的那一轮不再展示', () {
      final tasks = <Todo>[
        task(id: 1, periodicId: 7, cycleIndex: 0), // 逾期轮遗留 → 隐藏
        task(id: 2, periodicId: 7, cycleIndex: 5), // 新一轮（今天所在轮）→ 保留
      ];
      final visible = PeriodicRoundPolicy.visibleOnTodoPage(
        tasks: tasks,
        periodics: <Periodic>[periodic()],
        today: DateUtil.addDays(today, 10),
      );
      expect(visible.map((t) => t.id), <int?>[2]);
    });

    test('周期配置缺失（孤儿历史记录）→ 保守放行，不误伤数据', () {
      final tasks = <Todo>[task(id: 1, periodicId: 99, cycleIndex: 3)];
      final visible = PeriodicRoundPolicy.visibleOnTodoPage(
        tasks: tasks,
        periodics: const <Periodic>[],
        today: today,
      );
      expect(visible.map((t) => t.id), <int?>[1]);
    });
  });
}
