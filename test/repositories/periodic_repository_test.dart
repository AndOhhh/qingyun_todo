import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/interval_type.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/app_exception.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support.dart';

Periodic buildPeriodic({
  String name = '测试周期',
  DateTime? startDate,
  IntervalType type = IntervalType.day,
  int value = 1,
  bool isActive = true,
  DateTime? endDate,
}) =>
    Periodic(
      name: name,
      startDate: startDate ?? DateUtil.today(),
      intervalType: type,
      intervalValue: value,
      isActive: isActive,
      endDate: endDate,
    );

PeriodicItem buildItem({
  required int dayOffset,
  String title = '事项',
  String? remindTime,
  TodoPriority priority = TodoPriority.none,
  int sortOrder = 0,
}) =>
    PeriodicItem(
      dayOffset: dayOffset,
      title: title,
      remindTime: remindTime,
      priority: priority,
      sortOrder: sortOrder,
    );

void main() {
  late TestStore store;
  final today = DateUtil.today();

  setUp(() async {
    store = await TestStore.create();
  });

  tearDown(() async => store.dispose());

  /// 取某周期全部实例，按日期升序
  Future<List<Todo>> instancesOf(int periodicId) async {
    final list = await store.tasks.queryByPeriodicId(periodicId);
    return list;
  }

  /// 手工写入一条「旧口径遗留」实例（绕过生成引擎，用于迁移与展示口径测试）
  Future<void> insertLegacyInstance({
    required int periodicId,
    required int itemId,
    required int cycleIndex,
    required DateTime date,
    bool completed = false,
    String title = '打卡',
  }) async {
    final db = await store.db.database;
    final now = DateUtil.formatTimestamp(DateTime.now());
    await db.insert('tasks', <String, Object?>{
      'title': title,
      'remind_date': DateUtil.formatDate(date),
      'is_completed': completed ? 1 : 0,
      'completed_at': completed ? now : null,
      'source_type': 'PERIODIC',
      'periodic_id': periodicId,
      'periodic_item_id': itemId,
      'cycle_index': cycleIndex,
      'periodic_name_snapshot': '测试周期',
      'sort_order': 0,
      'is_notified': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  group('生成引擎 · 基本规则', () {
    test('TC-01：每 2 天 + 第 1 天喝牛奶 / 第 2 天喝豆浆，只生成本轮（一轮一期）', () async {
      final id = await store.periodics.insert(
        buildPeriodic(name: '隔天喝饮品计划', value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '喝牛奶', remindTime: '09:00'),
          buildItem(dayOffset: 1, title: '喝豆浆', remindTime: '09:00'),
        ],
      );
      final instances = await instancesOf(id);
      // 一轮一期（N13）：只生成「今天所在轮」，不再一次铺满 30 天窗口
      expect(instances.length, 2);
      final head = instances;
      expect(
        head.map((t) => '${DateUtil.formatDate(t.remindDate)} ${t.title}'),
        <String>[
          '${DateUtil.formatDate(today)} 喝牛奶',
          '${DateUtil.formatDate(DateUtil.addDays(today, 1))} 喝豆浆',
        ],
      );
      // 同一轮：两条实例的 cycleIndex 必须一致
      expect(head[0].cycleIndex, 0);
      expect(head[1].cycleIndex, 0);
      expect(head[0].sourceType, TaskSourceType.periodic);
      expect(head[0].periodicNameSnapshot, '隔天喝饮品计划');
      expect(head[0].isPeriodic, isTrue);
      expect(head[0].periodicTagLabel, '周期·隔天喝饮品计划');
      expect(head[0].remindTime, '09:00');
    });

    test('一轮一期：连续触发多次不会生成后续轮次', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      expect((await instancesOf(id)).length, 1);
      // 同一天反复触发：本轮未完成就不推进任何轮次
      await store.generator.generateCurrentRounds();
      await store.generator.generateForPeriodicId(id);
      await store.generator.generateCurrentRounds();
      expect(
        (await instancesOf(id)).length,
        1,
        reason: '本轮未完成前不生成任何后续轮次',
      );
    });

    test('TC-07：同一口径连续触发两次，实例行数不变（幂等）', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 3),
        items: <PeriodicItem>[buildItem(dayOffset: 0), buildItem(dayOffset: 2)],
      );
      final first = (await instancesOf(id)).length;
      await store.generator.generateCurrentRounds();
      await store.generator.generateCurrentRounds();
      await store.generator.generateForPeriodicId(id);
      expect((await instancesOf(id)).length, first);
    });

    test('唯一索引拒绝重复的 (periodic_item_id, cycle_index)', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      final instance = (await instancesOf(id)).first;
      final db = await store.db.database;
      await expectLater(
        db.insert('tasks', instance.toMap()),
        throwsA(isA<DatabaseException>()),
      );
      // existsInstance 幂等判断同样生效
      expect(
        await store.tasks.existsInstance(instance.periodicItemId!, instance.cycleIndex!),
        isTrue,
      );
      expect(
        await store.tasks.existsInstance(instance.periodicItemId!, 999),
        isFalse,
      );
    });

    test('Q1：起始日在过去时不补生成历史实例', () async {
      final id = await store.periodics.insert(
        buildPeriodic(startDate: DateUtil.addDays(today, -10)),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      final instances = await instancesOf(id);
      expect(instances, isNotEmpty);
      expect(
        instances.where((t) => t.remindDate.isBefore(today)),
        isEmpty,
        reason: '不得补生成今天之前的实例',
      );
      expect(instances.first.remindDate, today);
    });

    test('end_date 截断：终止日之后不再生成', () async {
      final id = await store.periodics.insert(
        buildPeriodic(endDate: DateUtil.addDays(today, 2)),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      // 一轮一期：先只生成今天这一轮
      expect(await instancesOf(id), hasLength(1));

      // 次日推进：本轮逾期 → 顺延生成「今天+1」那一轮
      await store.generator.generateCurrentRounds(
        today: DateUtil.addDays(today, 1),
      );
      var instances = await instancesOf(id);
      expect(instances, hasLength(2));
      expect(
        DateUtil.formatDate(instances.last.remindDate),
        DateUtil.formatDate(DateUtil.addDays(today, 1)),
      );

      // 越过终止日：整周期到期，不再生成
      await store.generator.generateCurrentRounds(
        today: DateUtil.addDays(today, 3),
      );
      instances = await instancesOf(id);
      expect(instances, hasLength(2), reason: '终止日之后不再生成');
    });

    test('TC-21：暂停后不再生成新实例，已有实例保留；启用后恢复生成', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      final before = (await instancesOf(id)).length;
      expect(before, 1);

      await store.periodics.setActive(id, false);
      expect((await store.periodics.findById(id))!.isActive, isFalse);

      // 暂停期间即便跨到下一轮，也一条都不生成；已有实例保留
      await store.generator.generateForPeriodicId(
        id,
        today: DateUtil.addDays(today, 2),
      );
      expect((await instancesOf(id)).length, before);

      // 重新启用后恢复生成（本轮已逾期 → 顺延到新一轮）
      await store.periodics.setActive(id, true);
      expect((await store.periodics.findById(id))!.isActive, isTrue);
      await store.generator.generateForPeriodicId(
        id,
        today: DateUtil.addDays(today, 2),
      );
      expect((await instancesOf(id)).length, greaterThan(before));
    });

    test('TC-20 / Q8：修改规则不追溯已生成实例，新规则从下一轮生效', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      String fmt(int offset) =>
          DateUtil.formatDate(DateUtil.addDays(today, offset));
      final beforeDates = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toSet();
      expect(beforeDates, <String>{fmt(0)});

      final periodic = (await store.periodics.findById(id))!;
      await store.periodics.update(periodic.copyWith(intervalValue: 3));

      // 已生成实例的日期**一条都没变**（不追溯）
      final afterDates = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toSet();
      expect(afterDates, beforeDates);

      // 本轮完成 → 下一轮按新规则（每 3 天）推算：今天+3，而不是今天+2
      final only = (await instancesOf(id)).single;
      await store.tasks.toggleComplete(only.id!, to: true);
      final next = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toSet();
      expect(next.contains(fmt(0)), isTrue, reason: '旧实例保留');
      expect(next.contains(fmt(3)), isTrue, reason: 'DAY/3 的下一轮 = +3 天');
      expect(next.contains(fmt(2)), isFalse, reason: '不再按每 2 天推进');
    });
  });

  group('一轮一期（N13）：生成与展示口径', () {
    test('改间隔后加项：计划按新规则重建，今天显示新规则下该做的那一项（用户实测场景）', () async {
      // 1) 先用「每天」建周期（起始昨天）+ 豆浆（第 1 天）→ 旧编号把它放在第 1 轮
      final id = await store.periodics.insert(
        buildPeriodic(startDate: DateUtil.addDays(today, -1), value: 1),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '豆浆')],
      );
      var instances = await instancesOf(id);
      expect(instances.single.cycleIndex, 1, reason: '每天：今天所在轮是第 1 轮');
      expect(
        DateUtil.formatDate(instances.single.remindDate),
        DateUtil.formatDate(today),
      );

      // 2) 改成「每 2 天」→ 未完成计划按新规则重建：第 0 轮 = 昨天 ~ 今天，
      //    豆浆落在昨天（早于今天不补生成），旧编号实例被清理
      final periodic = (await store.periodics.findById(id))!;
      await store.periodics.update(periodic.copyWith(intervalValue: 2));
      expect(await instancesOf(id), isEmpty);

      // 3) 加「胡辣汤」（第 2 天）→ 落在今天、第 0 轮（正是用户期望的结果）
      await store.items.insert(
        buildItem(dayOffset: 1, title: '胡辣汤').copyWith(periodicId: id),
      );
      instances = await instancesOf(id);
      expect(instances, hasLength(1));
      expect(instances.single.title, '胡辣汤');
      expect(instances.single.cycleIndex, 0);
      expect(
        DateUtil.formatDate(instances.single.remindDate),
        DateUtil.formatDate(today),
      );
    });

    test('改起始日 → 未完成计划重建，已完成实例保留为历史', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final done = (await instancesOf(id)).single;
      await store.tasks.toggleComplete(done.id!, to: true);
      // 本轮完成 → 生成下一轮（+2）
      expect(await instancesOf(id), hasLength(2));

      // 起始日往前挪一天：今天所在轮变为第 0 轮（含今天）
      final periodic = (await store.periodics.findById(id))!;
      await store.periodics.update(
        periodic.copyWith(startDate: DateUtil.addDays(today, -1)),
      );

      final instances = await instancesOf(id);
      // 已完成那条原样保留；未完成的旧编号实例被清理，
      // 计划顺延到「第 0 轮已完成」之后的下一轮（不补生成过去的日期）
      expect(instances.any((t) => t.id == done.id && t.isCompleted), isTrue);
      final pending = instances.where((t) => !t.isCompleted).toList();
      expect(pending, hasLength(1));
      expect(pending.single.cycleIndex, 1, reason: '第 0 轮已整体完成 → 计划顺延');
      expect(
        DateUtil.formatDate(pending.single.remindDate),
        DateUtil.formatDate(DateUtil.addDays(today, 1)),
        reason: '新规则第 1 轮 = 明天起（昨天/今天不补生成）',
      );
    });

    test('事项改天序 → 该事项未完成实例按新天序重建，其余事项不受影响', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '豆浆'),
          buildItem(dayOffset: 1, title: '胡辣汤'),
        ],
      );
      final instances = await instancesOf(id);
      final keep = instances.firstWhere((t) => t.title == '豆浆');
      var target = instances.firstWhere((t) => t.title == '胡辣汤');
      expect(
        DateUtil.formatDate(target.remindDate),
        DateUtil.formatDate(DateUtil.addDays(today, 1)),
      );

      // 把「胡辣汤」从天 2 改到天 1
      final item = (await store.items.findById(target.periodicItemId!))!;
      await store.items.update(item.copyWith(dayOffset: 0));

      final after = await instancesOf(id);
      expect(after.any((t) => t.id == keep.id), isTrue, reason: '豆浆实例不追溯');
      target = after.firstWhere((t) => t.title == '胡辣汤');
      expect(
        DateUtil.formatDate(target.remindDate),
        DateUtil.formatDate(today),
        reason: '胡辣汤按新天序落在今天',
      );
      expect(target.cycleIndex, 0);
    });
    test('完成本轮最后一项 → 生成下一轮，且未完成轮次有且只有一轮', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '第 1 天'),
          buildItem(dayOffset: 1, title: '第 2 天'),
        ],
      );
      var instances = await instancesOf(id);
      expect(instances.map((t) => t.cycleIndex).toSet(), <int>{0});

      // 只完成第 1 项：本轮未结束 → 不生成下一轮
      await store.tasks.toggleComplete(instances[0].id!, to: true);
      expect(
        (await instancesOf(id)).map((t) => t.cycleIndex).toSet(),
        <int>{0},
      );

      // 完成最后一项：本轮完结 → 生成下一轮（+2 / +3）
      await store.tasks.toggleComplete(instances[1].id!, to: true);
      instances = await instancesOf(id);
      final pendingRounds = instances
          .where((t) => !t.isCompleted)
          .map((t) => t.cycleIndex)
          .toSet();
      expect(pendingRounds, <int>{1}, reason: '未完成轮次有且只有一轮');
      expect(
        instances
            .where((t) => t.cycleIndex == 1)
            .map((t) => DateUtil.formatDate(t.remindDate)),
        containsAll(<String>[
          DateUtil.formatDate(DateUtil.addDays(today, 2)),
          DateUtil.formatDate(DateUtil.addDays(today, 3)),
        ]),
      );
    });

    test('本轮整轮逾期 → 生成顺延到新一轮，错过那一轮的实例保留在库中', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      expect((await instancesOf(id)).single.cycleIndex, 0);

      // 推进 6 天：第 0 轮（今天 ~ +1）整轮逾期 → 生成「今天所在轮」（第 3 轮）
      await store.generator.generateCurrentRounds(
        today: DateUtil.addDays(today, 6),
      );
      final instances = await instancesOf(id);
      expect(instances.map((t) => t.cycleIndex).toSet(), <int>{0, 3});
      expect(
        DateUtil.formatDate(instances.last.remindDate),
        DateUtil.formatDate(DateUtil.addDays(today, 6)),
      );
      // 错过那一轮不删（非破坏性），只是不进待办页
      expect(instances.first.isCompleted, isFalse);
      expect(instances.first.cycleIndex, 0);
    });

    test('旧口径遗留：晚于本轮的未完成实例在生成时清理，已完成实例作为历史保留', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final itemId = (await instancesOf(id)).single.periodicItemId!;
      // 模拟旧「30 天窗口」口径留下的未来轮次
      await insertLegacyInstance(
        periodicId: id,
        itemId: itemId,
        cycleIndex: 1,
        date: DateUtil.addDays(today, 2),
        title: '第 1 轮遗留',
      );
      await insertLegacyInstance(
        periodicId: id,
        itemId: itemId,
        cycleIndex: 2,
        date: DateUtil.addDays(today, 4),
        title: '第 2 轮遗留',
      );
      await insertLegacyInstance(
        periodicId: id,
        itemId: itemId,
        cycleIndex: 3,
        date: DateUtil.addDays(today, 6),
        title: '已完成遗留',
        completed: true,
      );
      expect(await instancesOf(id), hasLength(4));

      await store.generator.generateCurrentRounds();
      final rounds = (await instancesOf(id))
          .map((t) => '${t.cycleIndex}:${t.isCompleted ? 1 : 0}')
          .toList();
      expect(
        rounds,
        <String>['0:0', '3:1'],
        reason: '本轮保留；未来未完成轮被清理；未来已完成轮作为历史保留',
      );
    });

    test('待办页口径：未来轮次与错过的一轮都不展示，只展示本轮', () async {
      // A：本轮（今天 / 明天）+ 手工塞入的未来轮次
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '第 1 天'),
          buildItem(dayOffset: 1, title: '第 2 天'),
        ],
      );
      final itemId = (await instancesOf(id)).first.periodicItemId!;
      await insertLegacyInstance(
        periodicId: id,
        itemId: itemId,
        cycleIndex: 1,
        date: DateUtil.addDays(today, 2),
        title: '第 1 天',
      );

      var groups = await store.tasks.queryGrouped();
      var visible = <String>[
        for (final g in groups.sections) for (final t in g.items) t.title,
      ];
      expect(visible.where((t) => t == '第 1 天').length, 1,
          reason: '未来轮次不进待办页');
      expect(visible.where((t) => t == '第 2 天').length, 1);

      // B：起始日 10 天前（本轮 = 今天所在轮），外加一条错过轮的遗留实例
      final oldId = await store.periodics.insert(
        buildPeriodic(value: 2, startDate: DateUtil.addDays(today, -10)),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final current = (await instancesOf(oldId)).single;
      expect(
        DateUtil.formatDate(current.remindDate),
        DateUtil.formatDate(today),
      );
      await insertLegacyInstance(
        periodicId: oldId,
        itemId: current.periodicItemId!,
        cycleIndex: 0,
        date: DateUtil.addDays(today, -10),
      );

      groups = await store.tasks.queryGrouped();
      visible = <String>[
        for (final g in groups.sections) for (final t in g.items) t.title,
      ];
      expect(visible.where((t) => t == '打卡').length, 1,
          reason: '错过的那一轮不展示');
      expect(
        groups.overdue.where((t) => t.isPeriodic),
        isEmpty,
        reason: '逾期遗留轮不进入待办页（常规逾期待办不受影响）',
      );
    });
  });

  group('生成引擎 · 短月份跳过', () {
    test('TC-04：每月周期 + day_offset=28，2 月轮次跳过该项', () async {
      final id = await store.periodics.insert(
        buildPeriodic(
          name: '每月账单',
          startDate: DateTime(2026, 12, 1),
          type: IntervalType.month,
        ),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '交房租')],
      );
      // docs/02 §7.4 示例 2 的场景。注意：正常 UI 路径下 MONTH 的 day_offset
      // 上限是 27（见 TC-05），这里直接用 SQL 写入以单独验证**生成引擎**的跳过规则。
      final db = await store.db.database;
      final now = DateUtil.formatTimestamp(DateTime.now());
      await db.insert('periodic_items', <String, Object?>{
        'periodic_id': id,
        'day_offset': 28,
        'title': '月末盘点',
        'priority': 'none',
        'sort_order': 0,
        'created_at': now,
        'updated_at': now,
      });
      await store.generator.generateForPeriodicId(
        id,
        today: DateTime(2026, 12, 1),
      );
      await store.generator.generateForPeriodicId(
        id,
        today: DateTime(2027, 1, 1),
      );
      await store.generator.generateForPeriodicId(
        id,
        today: DateTime(2027, 2, 1),
      );
      final instances = await instancesOf(id);
      final byTitle = <String, List<String>>{};
      for (final t in instances) {
        byTitle
            .putIfAbsent(t.title, () => <String>[])
            .add(DateUtil.formatDate(t.remindDate));
      }
      expect(byTitle['交房租'], <String>['2026-12-01', '2027-01-01', '2027-02-01']);
      // 2027-02 只有 28 天，day_offset=28 不存在 → 跳过
      expect(byTitle['月末盘点'], <String>['2026-12-29', '2027-01-29']);
    });

    test('TC-02 / TC-03：MONTH 日号锚定与月末收敛落到真实实例日期', () async {
      final id = await store.periodics.insert(
        buildPeriodic(
          startDate: DateTime(2026, 1, 31),
          type: IntervalType.month,
        ),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '还款')],
      );
      // 一轮一期：逐轮推进（1/31 → 2/28 → 3/31 → 4/30），
      // 每个「今天」都落在目标轮的第 1 天，从而把该轮生成出来。
      for (final day in <DateTime>[
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]) {
        await store.generator.generateForPeriodicId(id, today: day);
      }
      final dates = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toList();
      expect(
        dates,
        <String>['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
        reason: '2 月收敛到 28 日、4 月收敛到 30 日，且不得漂移到 3 月 3 日',
      );
    });
  });

  group('day_offset 校验（Q12）', () {
    test('TC-05：每月周期下新增 day_offset=28 的周期项被拒，提示含上限 28', () async {
      final id = await store.periodics.insert(
        buildPeriodic(type: IntervalType.month),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      try {
        await store.items.insert(
          buildItem(dayOffset: 28, title: '月末盘点').copyWith(periodicId: id),
        );
        fail('应当抛出 ValidationException');
      } on ValidationException catch (e) {
        expect(e.message, contains('超出周期长度'));
        expect(e.fullMessage, contains('28'));
      }
    });

    test('每 2 天周期下 day_offset=2 被拒', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      expect(
        store.items.insert(
          buildItem(dayOffset: 2).copyWith(periodicId: id),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('TC-06：每 3 天含 day_offset=2 的项，改为每 2 天时阻止保存并列出冲突项', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 3),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '喝牛奶'),
          buildItem(dayOffset: 2, title: '喝豆浆'),
        ],
      );
      final periodic = (await store.periodics.findById(id))!;
      final conflicts =
          await store.periodics.validateIntervalChange(periodic.copyWith(intervalValue: 2));
      expect(conflicts.map((i) => i.title), <String>['喝豆浆']);

      try {
        await store.periodics.update(periodic.copyWith(intervalValue: 2));
        fail('应当阻止保存');
      } on ValidationException catch (e) {
        expect(e.details, isNotEmpty);
        expect(e.details.first, contains('喝豆浆'));
        expect(e.details.first, contains('第 3 天'));
      }
      // 保存被阻止 → 规则未变
      expect((await store.periodics.findById(id))!.intervalValue, 3);
    });

    test('新增周期时携带越界周期项同样被拒（事务不留下半个周期）', () async {
      expect(
        store.periodics.insert(
          buildPeriodic(value: 2),
          items: <PeriodicItem>[buildItem(dayOffset: 5)],
        ),
        throwsA(isA<ValidationException>()),
      );
      expect(await store.periodics.queryAll(), isEmpty);
    });

    test('名称为空 / interval_value < 1 / 终止日早于起始日 均被拒', () async {
      expect(
        store.periodics.insert(buildPeriodic(name: '  ')),
        throwsA(isA<ValidationException>()),
      );
      expect(
        store.periodics.insert(buildPeriodic().copyWith(intervalValue: 0)),
        throwsA(isA<ValidationException>()),
      );
      expect(
        store.periodics.insert(
          buildPeriodic(endDate: DateUtil.addDays(today, -1)),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('轮次与计数（FR-15）', () {
    test('TC-08：完成第 1 个不变，完成第 2 个后 +1 且生成下一轮', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 40),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: 'A'),
          buildItem(dayOffset: 1, title: 'B'),
        ],
      );
      final instances = await instancesOf(id);
      expect(instances.length, 2, reason: '40 天一轮，窗口内只有第 1 轮');

      await store.tasks.toggleComplete(instances[0].id!, to: true);
      expect((await store.periodics.findById(id))!.completedCount, 0);
      expect((await instancesOf(id)).length, 2);

      await store.tasks.toggleComplete(instances[1].id!, to: true);
      expect((await store.periodics.findById(id))!.completedCount, 1);
      final after = await instancesOf(id);
      expect(after.length, 4, reason: '完结后应生成下一轮（+40 / +41 天）');
      expect(
        after.map((t) => t.cycleIndex).toSet(),
        <int>{0, 1},
      );
      expect(
        DateUtil.formatDate(after[2].remindDate),
        DateUtil.formatDate(DateUtil.addDays(today, 40)),
      );
    });

    test('TC-09：取消完成其中一条，completed_count 回退', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 40),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: 'A'),
          buildItem(dayOffset: 1, title: 'B'),
        ],
      );
      final instances = await instancesOf(id);
      await store.tasks.toggleComplete(instances[0].id!, to: true);
      await store.tasks.toggleComplete(instances[1].id!, to: true);
      expect((await store.periodics.findById(id))!.completedCount, 1);

      await store.tasks.toggleComplete(instances[1].id!, to: false);
      final periodic = (await store.periodics.findById(id))!;
      expect(periodic.completedCount, 0);
      expect(periodic.completedCount, greaterThanOrEqualTo(0));
    });

    test('TC-10：删除其中 1 个未完成实例后完成另 1 个，视为该轮完结', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 40),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: 'A'),
          buildItem(dayOffset: 1, title: 'B'),
        ],
      );
      final instances = await instancesOf(id);
      await store.tasks.deleteById(instances[1].id!);
      expect((await store.periodics.findById(id))!.completedCount, 0);

      await store.tasks.toggleComplete(instances[0].id!, to: true);
      expect((await store.periodics.findById(id))!.completedCount, 1);
    });

    test('本轮进度 x/y 与「当前轮」定位正确', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: 'A'),
          buildItem(dayOffset: 1, title: 'B'),
        ],
      );
      var progress = await store.periodics.queryCurrentCycleProgress(id);
      expect(progress, isNotNull);
      expect(progress!.cycleIndex, 0);
      expect(progress.label, '0/2');

      final instances = await instancesOf(id);
      await store.tasks.toggleComplete(instances[0].id!, to: true);
      progress = await store.periodics.queryCurrentCycleProgress(id);
      expect(progress!.label, '1/2');
      expect(progress.isFinished, isFalse);

      await store.tasks.toggleComplete(instances[1].id!, to: true);
      progress = await store.periodics.queryCurrentCycleProgress(id);
      // 第 1 轮已完结 → 当前轮推进到第 2 轮
      expect(progress!.cycleIndex, 1);
      expect(progress.label, '0/2');
    });

    test('尚无实例时 queryCurrentCycleProgress 返回 null', () async {
      // 空周期（无周期项）不会生成任何实例
      final id = await store.periodics.insert(buildPeriodic());
      expect(await store.periodics.queryCurrentCycleProgress(id), isNull);
    });
  });

  group('删除语义（Q5 / Q9 / TC-11 / TC-12）', () {
    test('TC-11：删除周期 → 未完成被删、已完成保留并断开关联、周期项清空', () async {
      final id = await store.periodics.insert(
        buildPeriodic(name: '阅读计划', value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '读书'),
          buildItem(dayOffset: 1, title: '摘抄'),
        ],
      );
      final instances = await instancesOf(id);
      await store.tasks.toggleComplete(instances[0].id!, to: true);

      final preview = await store.periodics.previewDelete(id);
      expect(preview.removedPending, instances.length - 1);
      expect(preview.keptCompleted, 1);

      final result = await store.periodics.deleteById(id);
      expect(result.removedPending, instances.length - 1);
      expect(result.keptCompleted, 1);

      // 周期与周期项都没了
      expect(await store.periodics.findById(id), isNull);
      expect(await store.periodics.queryItems(id), isEmpty);

      // 已完成实例保留为孤儿记录
      final kept = (await store.tasks.findById(instances[0].id!))!;
      expect(kept.isCompleted, isTrue);
      expect(kept.periodicId, isNull);
      expect(kept.periodicItemId, isNull);
      expect(kept.cycleIndex, 0, reason: 'cycle_index 保留');
      expect(kept.periodicNameSnapshot, '阅读计划', reason: '名称快照保留');
      expect(kept.sourceType, TaskSourceType.periodic);
      expect(kept.isOrphanPeriodic, isTrue);
    });

    test('TC-12：孤儿记录出现在待办页查询中，标签为「周期·{快照名}」', () async {
      final id = await store.periodics.insert(
        buildPeriodic(name: '阅读计划', value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '读书')],
      );
      final instance = (await instancesOf(id)).first;
      await store.tasks.toggleComplete(instance.id!, to: true);
      await store.periodics.deleteById(id);

      final groups = await store.tasks.queryGrouped();
      final kept = groups.completed.singleWhere((t) => t.id == instance.id);
      expect(kept.periodicTagLabel, '周期·阅读计划');
      expect(kept.periodicId, isNull, reason: '无跳转入口');

      final orphans = await store.tasks.queryOrphanPeriodic();
      expect(orphans.map((t) => t.id), <int?>[instance.id]);
    });

    test('删除周期项走条件删除：未完成实例删、已完成实例保留', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '读书'),
          buildItem(dayOffset: 1, title: '摘抄'),
        ],
      );
      var instances = await instancesOf(id);
      final keep = instances.firstWhere((t) => t.title == '读书');
      await store.tasks.toggleComplete(keep.id!, to: true);
      // 推进到下一轮：让「读书」同时存在已完成（本轮）与未完成（下一轮）实例
      await store.generator.generateCurrentRounds(
        today: DateUtil.addDays(today, 2),
      );
      instances = await instancesOf(id);

      final itemId = keep.periodicItemId!;
      final preview = await store.items.previewDelete(itemId);
      expect(preview.keptCompleted, 1);
      expect(preview.removedPending, 1);

      final result = await store.items.deleteById(itemId);
      expect(result.keptCompleted, 1);

      final kept = (await store.tasks.findById(keep.id!))!;
      expect(kept.periodicItemId, isNull);
      expect(kept.periodicId, id, reason: '周期本体还在，periodic_id 不应被清空');
      expect(kept.cycleIndex, 0);

      // 另一项的实例不受影响
      final remaining = await instancesOf(id);
      expect(remaining.every((t) => t.title != '读书' || t.isCompleted), isTrue);
      expect(remaining.any((t) => t.title == '摘抄'), isTrue);
    });

    test('三级删除之二：deleteFutureInstances 只删未来的未完成实例', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 3),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '第 1 天'),
          buildItem(dayOffset: 1, title: '第 2 天'),
          buildItem(dayOffset: 2, title: '第 3 天'),
        ],
      );
      final instances = await instancesOf(id);
      expect(instances.length, 3, reason: '一轮一期：本轮三条');
      // 把明天那条标记完成，它不应被「删未来实例」清掉
      await store.tasks.toggleComplete(instances[1].id!, to: true);

      final removed = await store.items.deleteFutureInstances(
        instances[2].periodicItemId!,
        fromDate: DateUtil.addDays(today, 2),
      );
      expect(removed, 1);
      final after = await instancesOf(id);
      expect(after.length, 2, reason: '今天 1 条 + 已完成的明天 1 条');
      expect(after.any((t) => t.id == instances[1].id && t.isCompleted), isTrue);
    });

    test('删除单条待办后轮数重算（删掉唯一未完成项也算完结）', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 40),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: 'A')],
      );
      final instance = (await instancesOf(id)).single;
      await store.tasks.deleteById(instance.id!);
      expect((await store.periodics.findById(id))!.completedCount, 0);
    });
  });

  group('列表与详情聚合', () {
    test('queryListWithProgress：启用在前，带本轮进度与下次提醒', () async {
      final a = await store.periodics.insert(
        buildPeriodic(name: '每天喝水'),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '喝水', remindTime: '08:00')],
      );
      final b = await store.periodics.insert(
        buildPeriodic(name: '每周复盘', type: IntervalType.week),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '复盘')],
      );
      await store.periodics.setActive(b, false);

      final list = await store.periodics.queryListWithProgress();
      expect(list.length, 2);
      expect(list.first.periodic.name, '每天喝水', reason: '启用中的排在前面');
      expect(list.first.periodic.intervalLabel, '每天');
      expect(list.last.periodic.intervalLabel, '每周');
      expect(list.first.currentCycle!.label, '0/1');
      expect(list.first.nextRemind!.title, '喝水');
      expect(list.first.nextRemind!.remindTime, '08:00');
      expect(list.last.periodic.isActive, isFalse);
      expect(a, isNot(b));
    });

    test('queryDetail：周期 + 按天序分组的周期项 + 统计', () async {
      final id = await store.periodics.insert(
        buildPeriodic(name: '隔天饮品', value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 1, title: '喝豆浆'),
          buildItem(dayOffset: 0, title: '喝牛奶'),
          buildItem(dayOffset: 0, title: '吃鸡蛋', sortOrder: 1),
        ],
      );
      final detail = (await store.periodics.queryDetail(id))!;
      expect(detail.periodic.name, '隔天饮品');
      expect(detail.items.map((i) => i.title).toList(),
          <String>['喝牛奶', '吃鸡蛋', '喝豆浆']);
      expect(detail.itemsByDay.keys.toList(), <int>[0, 1]);
      expect(detail.itemsByDay[0]!.length, 2);
      expect(detail.dayCount, 2);
      expect(detail.totalInstances, greaterThan(0));
      expect(detail.completionRate, 0);
      expect(detail.currentCycle!.cycleIndex, 0);
      expect(detail.nextRemind, isNotNull);

      await store.tasks.toggleComplete(detail.nextRemind!.id!, to: true);
      final after = (await store.periodics.queryDetail(id))!;
      expect(after.completedInstances, 1);
      expect(after.completionRate, greaterThan(0));
    });

    test('周期不存在时 queryDetail 返回 null', () async {
      expect(await store.periodics.queryDetail(999999), isNull);
    });

    test('空周期（无周期项）不会生成任何实例，详情页可识别', () async {
      final id = await store.periodics.insert(buildPeriodic(name: '空周期'));
      final detail = (await store.periodics.queryDetail(id))!;
      expect(detail.hasNoItems, isTrue);
      expect(detail.totalInstances, 0);
      expect(await instancesOf(id), isEmpty);
    });
  });

  group('删除墓碑：删掉的实例不会被生成引擎复活', () {
    test('删除单条周期实例后重新生成，实例数量不变、原 id 不回来', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '打卡'),
          buildItem(dayOffset: 1, title: '复盘'),
        ],
      );
      final instances = await instancesOf(id);
      expect(instances.length, 2, reason: '一轮一期：本轮两条共用 cycleIndex');
      final target = instances[1];
      await store.tasks.deleteById(target.id!);

      await store.generator.generateCurrentRounds();
      await store.generator.generateCurrentRounds();

      final after = await instancesOf(id);
      expect(after.length, instances.length - 1);
      expect(after.any((t) => t.id == target.id), isFalse);
      expect(
        after.any((t) =>
            t.cycleIndex == target.cycleIndex &&
            t.periodicItemId == target.periodicItemId),
        isFalse,
        reason: '被删的 (周期项, 轮次) 不复活',
      );
    });

    test('撤销删除后墓碑清除：按原 id 回来且不会被重复生成', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '打卡'),
          buildItem(dayOffset: 1, title: '复盘'),
        ],
      );
      final instances = await instancesOf(id);
      final target = instances[1];
      final snapshot = (await store.tasks.deleteById(target.id!))!;
      await store.tasks.restore(snapshot);

      expect((await store.tasks.findById(target.id!))!.title, '复盘');
      await store.generator.generateCurrentRounds();
      final after = await instancesOf(id);
      expect(after.length, instances.length);
      expect(after.where((t) => t.cycleIndex == target.cycleIndex).length, 2);
    });

    test('删除未来实例后不会被生成回来，已完成实例保留', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 3),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '第 1 天'),
          buildItem(dayOffset: 1, title: '第 2 天'),
          buildItem(dayOffset: 2, title: '第 3 天'),
        ],
      );
      final instances = await instancesOf(id);
      expect(instances.length, 3, reason: '一轮一期：本轮三条');
      await store.tasks.toggleComplete(instances[1].id!, to: true);

      final removed = await store.items.deleteFutureInstances(
        instances[2].periodicItemId!,
        fromDate: DateUtil.addDays(today, 2),
      );
      expect(removed, 1);

      await store.generator.generateCurrentRounds();
      final after = await instancesOf(id);
      expect(after.length, 2,
          reason: '今天 1 条 + 已完成的明天 1 条；+2 那条被删且不复活');
      expect(after.any((t) => t.id == instances[1].id && t.isCompleted), isTrue);
    });
  });
}
