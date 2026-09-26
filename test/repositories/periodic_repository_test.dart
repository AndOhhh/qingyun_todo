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

  group('生成引擎 · 基本规则', () {
    test('TC-01：每 2 天 + 第 1 天喝牛奶 / 第 2 天喝豆浆，日期序列与 docs/01 §4.4 一致', () async {
      final id = await store.periodics.insert(
        buildPeriodic(name: '隔天喝饮品计划', value: 2),
        items: <PeriodicItem>[
          buildItem(dayOffset: 0, title: '喝牛奶', remindTime: '09:00'),
          buildItem(dayOffset: 1, title: '喝豆浆', remindTime: '09:00'),
        ],
      );
      final instances = await instancesOf(id);
      // 窗口 = 今天 ~ 今天+30（含端点共 31 天）；每 2 天一轮 → 16 轮，
      // 第 16 轮的第 2 天（+31）超出窗口，故 16 × 2 - 1 = 31 条
      expect(instances.length, 31);
      final head = instances.take(4).toList();
      expect(
        head.map((t) => '${DateUtil.formatDate(t.remindDate)} ${t.title}'),
        <String>[
          '${DateUtil.formatDate(today)} 喝牛奶',
          '${DateUtil.formatDate(DateUtil.addDays(today, 1))} 喝豆浆',
          '${DateUtil.formatDate(DateUtil.addDays(today, 2))} 喝牛奶',
          '${DateUtil.formatDate(DateUtil.addDays(today, 3))} 喝豆浆',
        ],
      );
      // 轮次与来源信息完整，快照名写入
      expect(head[0].cycleIndex, 0);
      expect(head[2].cycleIndex, 1);
      expect(head[0].sourceType, TaskSourceType.periodic);
      expect(head[0].periodicNameSnapshot, '隔天喝饮品计划');
      expect(head[0].isPeriodic, isTrue);
      expect(head[0].periodicTagLabel, '周期·隔天喝饮品计划');
      expect(head[0].remindTime, '09:00');
    });

    test('TC-07：同一窗口连续触发两次，实例行数不变（幂等）', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 3),
        items: <PeriodicItem>[buildItem(dayOffset: 0), buildItem(dayOffset: 2)],
      );
      final first = (await instancesOf(id)).length;
      await store.generator.generateForWindow();
      await store.generator.generateForWindow();
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
      final instances = await instancesOf(id);
      expect(instances.length, 3); // today / +1 / +2
      expect(DateUtil.formatDate(instances.last.remindDate),
          DateUtil.formatDate(DateUtil.addDays(today, 2)));
    });

    test('TC-21：暂停后不再生成新实例，已有实例保留；启用后恢复生成', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
      final before = (await instancesOf(id)).length;
      expect(before, greaterThan(0));

      await store.periodics.setActive(id, false);
      expect((await store.periodics.findById(id))!.isActive, isFalse);

      // 暂停期间即便把窗口拉长到 200 天，也一条都不生成；已有实例保留
      await store.generator.generateForPeriodicId(
        id,
        from: today,
        to: DateUtil.addDays(today, 200),
      );
      expect((await instancesOf(id)).length, before);

      // 重新启用后恢复生成
      await store.periodics.setActive(id, true);
      expect((await store.periodics.findById(id))!.isActive, isTrue);
      await store.generator.generateForPeriodicId(
        id,
        from: today,
        to: DateUtil.addDays(today, 200),
      );
      expect((await instancesOf(id)).length, greaterThan(before));
    });

    test('TC-20 / Q8：修改规则不追溯已生成实例，新规则只对尚未生成的轮次生效', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      String fmt(int offset) =>
          DateUtil.formatDate(DateUtil.addDays(today, offset));
      final beforeDates = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toSet();
      expect(beforeDates.contains(fmt(2)), isTrue);

      final periodic = (await store.periodics.findById(id))!;
      await store.periodics.update(periodic.copyWith(intervalValue: 3));

      // 已生成窗口内的实例日期**一条都没变**（不追溯）
      final afterDates = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toSet();
      expect(afterDates, beforeDates);

      // 新规则从「尚未生成的轮次」开始生效：窗口拉长到 200 天后，
      // 第 17 轮（index 16）起按每 3 天推进（+48 / +51 …），而不是每 2 天
      await store.generator.generateForPeriodicId(
        id,
        from: today,
        to: DateUtil.addDays(today, 200),
      );
      final extended = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .toSet();
      expect(extended.contains(fmt(2)), isTrue, reason: '旧实例保留');
      expect(extended.contains(fmt(48)), isTrue, reason: 'DAY/3 的第 17 轮 = +48 天');
      expect(extended.contains(fmt(51)), isTrue);
      expect(extended.contains(fmt(50)), isFalse, reason: '不再是每 2 天');
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
        from: DateTime(2026, 12, 1),
        to: DateTime(2027, 2, 28),
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
      await store.generator.generateForPeriodicId(
        id,
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 5, 1),
      );
      // 只看 2026-01 ~ 2026-04 区间（insert 时还会按真实「今天」补生成窗口内实例）
      final dates = (await instancesOf(id))
          .map((t) => DateUtil.formatDate(t.remindDate))
          .where((d) => d.compareTo('2026-05-01') < 0)
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
      final id = await store.periodics.insert(
        buildPeriodic(startDate: DateUtil.addDays(today, 400)),
        items: <PeriodicItem>[buildItem(dayOffset: 0)],
      );
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
      final instances = await instancesOf(id);
      final keep = instances.firstWhere((t) => t.title == '读书');
      await store.tasks.toggleComplete(keep.id!, to: true);

      final itemId = keep.periodicItemId!;
      final preview = await store.items.previewDelete(itemId);
      expect(preview.keptCompleted, 1);
      expect(preview.removedPending, greaterThan(0));

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
        buildPeriodic(value: 1),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final instances = await instancesOf(id);
      expect(instances.length, greaterThan(3));
      // 把明天那条标记完成，它不应被「删未来实例」清掉
      await store.tasks.toggleComplete(instances[1].id!, to: true);

      final itemId = instances[0].periodicItemId!;
      final removed = await store.items.deleteFutureInstances(
        itemId,
        fromDate: DateUtil.addDays(today, 1),
      );
      final after = await instancesOf(id);
      expect(removed, instances.length - 2); // 今天 + 已完成的明天 保留
      expect(after.length, 2);
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
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final instances = await instancesOf(id);
      final target = instances[1];
      await store.tasks.deleteById(target.id!);

      await store.generator.generateForWindow();
      await store.generator.generateForWindow();

      final after = await instancesOf(id);
      expect(after.length, instances.length - 1);
      expect(after.any((t) => t.id == target.id), isFalse);
      expect(after.any((t) => t.cycleIndex == target.cycleIndex), isFalse);
    });

    test('撤销删除后墓碑清除：按原 id 回来且不会被重复生成', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 2),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final instances = await instancesOf(id);
      final target = instances[1];
      final snapshot = (await store.tasks.deleteById(target.id!))!;
      await store.tasks.restore(snapshot);

      expect((await store.tasks.findById(target.id!))!.title, '打卡');
      await store.generator.generateForWindow();
      final after = await instancesOf(id);
      expect(after.length, instances.length);
      expect(after.where((t) => t.cycleIndex == target.cycleIndex).length, 1);
    });

    test('删除未来实例后不会被生成回来，已完成实例保留', () async {
      final id = await store.periodics.insert(
        buildPeriodic(value: 1),
        items: <PeriodicItem>[buildItem(dayOffset: 0, title: '打卡')],
      );
      final instances = await instancesOf(id);
      await store.tasks.toggleComplete(instances[1].id!, to: true);
      final itemId = instances[0].periodicItemId!;

      final removed = await store.items.deleteFutureInstances(
        itemId,
        fromDate: DateUtil.addDays(today, 1),
      );
      expect(removed, instances.length - 2);

      await store.generator.generateForWindow();
      final after = await instancesOf(id);
      expect(after.length, 2, reason: '今天 1 条 + 已完成的明天 1 条');
      expect(after.any((t) => t.id == instances[1].id && t.isCompleted), isTrue);
    });
  });
}
