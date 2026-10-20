import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/repositories/task_repository.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support.dart';

Todo buildTask({
  String title = '任务',
  DateTime? remindDate,
  String? remindTime,
  bool completed = false,
  int sortOrder = 0,
  TodoPriority priority = TodoPriority.none,
  String? accentColorHex,
}) {
  final now = DateTime.now();
  return Todo(
    title: title,
    remindDate: remindDate ?? DateUtil.today(),
    remindTime: remindTime,
    isCompleted: completed,
    sortOrder: sortOrder,
    priority: priority,
    accentColorHex: accentColorHex,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late TestStore store;
  late TaskRepository tasks;

  setUp(() async {
    store = await TestStore.create();
    tasks = store.tasks;
  });

  tearDown(() async => store.dispose());

  group('建库与约束', () {
    test('PRAGMA foreign_keys = ON（漏了则 SET NULL / CASCADE 全失效）', () async {
      final db = await store.db.database;
      final rows = await db.rawQuery('PRAGMA foreign_keys');
      expect(rows.first.values.first, 1);
    });

    test('4 张表与 7 条索引均已建立', () async {
      final db = await store.db.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      expect(
        tables.map((r) => r['name']).toSet(),
        <String>{
          'periodic_configs',
          'periodic_items',
          'tasks',
          'periodic_skips',
        },
      );
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
      );
      expect(indexes.length, 7);
    });

    test('CHECK 约束拒绝脏值', () async {
      final db = await store.db.database;
      final now = DateUtil.formatTimestamp(DateTime.now());
      Future<void> insert(Map<String, Object?> values) =>
          db.insert('tasks', <String, Object?>{
            'title': 'x',
            'remind_date': DateUtil.formatDate(DateUtil.today()),
            'created_at': now,
            'updated_at': now,
            ...values,
          });
      expect(insert(<String, Object?>{'priority': 'urgent'}), throwsA(isA<DatabaseException>()));
      expect(insert(<String, Object?>{'is_completed': 2}), throwsA(isA<DatabaseException>()));
      expect(insert(<String, Object?>{'source_type': 'UNKNOWN'}), throwsA(isA<DatabaseException>()));
    });
  });

  group('分组查询（Q10 五组）', () {
    test('逾期 / 今天 / 明天 / 后续 / 已完成 正确分桶，逾期实时派生', () async {
      final today = DateUtil.today();
      await tasks.insert(buildTask(title: '逾期项', remindDate: DateUtil.addDays(today, -3)));
      await tasks.insert(buildTask(title: '今天项', remindDate: today, remindTime: '09:00'));
      await tasks.insert(buildTask(title: '明天项', remindDate: DateUtil.addDays(today, 1)));
      await tasks.insert(buildTask(title: '后续项', remindDate: DateUtil.addDays(today, 20)));
      await tasks.insert(
        buildTask(title: '已完成项', remindDate: today, completed: true),
      );

      final groups = await tasks.queryGrouped();
      expect(groups.overdue.map((t) => t.title), <String>['逾期项']);
      expect(groups.today.map((t) => t.title), <String>['今天项']);
      expect(groups.tomorrow.map((t) => t.title), <String>['明天项']);
      expect(groups.later.map((t) => t.title), <String>['后续项']);
      expect(groups.completed.map((t) => t.title), <String>['已完成项']);
      expect(groups.pendingCount, 4);
      expect(groups.totalCount, 5);
      // 逾期是派生值，不入库
      expect(groups.overdue.single.isOverdue, isTrue);
      expect(groups.today.single.isOverdue, isFalse);
      expect(groups.completed.single.isOverdue, isFalse);
    });

    test('今天组内排序：提醒时间升序、NULL 最后，再按 sort_order', () async {
      final today = DateUtil.today();
      await tasks.insert(buildTask(title: '无时间', remindDate: today, sortOrder: 0));
      await tasks.insert(buildTask(title: '20:00', remindDate: today, remindTime: '20:00'));
      await tasks.insert(buildTask(title: '09:00', remindDate: today, remindTime: '09:00'));

      final groups = await tasks.queryGrouped();
      expect(
        groups.today.map((t) => t.title).toList(),
        <String>['09:00', '20:00', '无时间'],
      );
    });

    test('空库返回空分组而不是抛异常', () async {
      final groups = await tasks.queryGrouped();
      expect(groups.isEmpty, isTrue);
      expect(groups.sections.where((s) => !s.isEmpty), isEmpty);
    });
  });

  group('今日进度（TC-18 / 修 R5）', () {
    test('只统计 remind_date = today，不含逾期与未来', () async {
      final today = DateUtil.today();
      await tasks.insert(buildTask(title: '昨天', remindDate: DateUtil.addDays(today, -1)));
      await tasks.insert(buildTask(title: '今天1', remindDate: today));
      await tasks.insert(buildTask(title: '今天2', remindDate: today, completed: true));
      await tasks.insert(buildTask(title: '下周', remindDate: DateUtil.addDays(today, 7)));

      final progress = await tasks.countTodayProgress();
      expect(progress.total, 2);
      expect(progress.done, 1);
      expect(progress.remaining, 1);
      expect(progress.rate, 0.5);
      expect(progress.allDone, isFalse);
    });

    test('今天没有任务时 total = 0 且不会除零', () async {
      final progress = await tasks.countTodayProgress();
      expect(progress.total, 0);
      expect(progress.rate, 0);
      expect(progress.allDone, isFalse);
    });
  });

  group('完成 / 取消完成', () {
    test('toggleComplete 写 completed_at，取消完成置 NULL', () async {
      final id = await tasks.insert(buildTask(title: '待办'));
      await tasks.toggleComplete(id);
      var loaded = (await tasks.findById(id))!;
      expect(loaded.isCompleted, isTrue);
      expect(loaded.completedAt, isNotNull);

      await tasks.toggleComplete(id);
      loaded = (await tasks.findById(id))!;
      expect(loaded.isCompleted, isFalse);
      expect(loaded.completedAt, isNull);
    });

    test('to: 显式指定目标状态，重复调用幂等', () async {
      final id = await tasks.insert(buildTask());
      await tasks.toggleComplete(id, to: true);
      final first = (await tasks.findById(id))!.completedAt;
      await tasks.toggleComplete(id, to: true);
      expect((await tasks.findById(id))!.completedAt, first);
    });

    test('update 保留 created_at 并刷新 updated_at', () async {
      final id = await tasks.insert(buildTask(title: '原标题'));
      final before = (await tasks.findById(id))!;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await tasks.update(before.copyWith(title: '新标题'));
      final after = (await tasks.findById(id))!;
      expect(after.title, '新标题');
      expect(after.createdAt, before.createdAt);
      expect(
        after.updatedAt!.isAfter(before.updatedAt!),
        isTrue,
        reason: 'updated_at 应被刷新',
      );
    });
  });

  group('硬删除与撤销（Q5 / TC-13 / TC-14）', () {
    test('deleteById 物理删除并从统计分母中消失', () async {
      final today = DateUtil.today();
      final id = await tasks.insert(buildTask(title: '要删的', remindDate: today));
      await tasks.insert(buildTask(title: '留下的', remindDate: today));
      expect((await tasks.countTodayProgress()).total, 2);

      final snapshot = await tasks.deleteById(id);
      expect(snapshot, isNotNull);
      expect(snapshot!.title, '要删的');
      expect(await tasks.findById(id), isNull);
      // 删除 ≠ 完成：分母同步减少
      expect((await tasks.countTodayProgress()).total, 1);
    });

    test('restore 按原 id 恢复，completed_at / sort_order 完全一致', () async {
      final id = await tasks.insert(buildTask(title: '已完成', completed: true, sortOrder: 7));
      await tasks.toggleComplete(id, to: true);
      final snapshot = (await tasks.findById(id))!;

      await tasks.deleteById(id);
      expect(await tasks.findById(id), isNull);

      await tasks.restore(snapshot);
      final restored = (await tasks.findById(id))!;
      expect(restored.id, id);
      expect(restored.title, snapshot.title);
      expect(restored.isCompleted, isTrue);
      expect(restored.completedAt, snapshot.completedAt);
      expect(restored.sortOrder, 7);
    });

    test('deleteByIds 事务内批量删除并返回全部快照', () async {
      final a = await tasks.insert(buildTask(title: 'A'));
      final b = await tasks.insert(buildTask(title: 'B'));
      final c = await tasks.insert(buildTask(title: 'C'));
      final snapshots = await tasks.deleteByIds(<int>[a, c]);
      expect(snapshots.map((t) => t.title).toSet(), <String>{'A', 'C'});
      expect(await tasks.findById(b), isNotNull);
      expect(await tasks.deleteByIds(<int>[]), isEmpty);
    });

    test('删除不存在的 id 返回 null，不抛异常', () async {
      expect(await tasks.deleteById(999999), isNull);
    });
  });

  group('日程页月历标记（FR-16）', () {
    test('queryMonthMarkers 按月聚合 未完成 / 已完成，跨月不串', () async {
      final today = DateUtil.today();
      final thisMonth = DateUtil.monthKey(today);
      await tasks.insert(buildTask(title: '今天未完成', remindDate: today));
      await tasks.insert(
        buildTask(title: '今天已完成', remindDate: today, completed: true),
      );
      await tasks.insert(
        buildTask(
          title: '下月',
          remindDate: DateUtil.addMonthsCalendar(today, 1),
        ),
      );

      final markers = await tasks.queryMonthMarkers(thisMonth);
      final todayKey = DateUtil.formatDate(today);
      expect(markers[todayKey], isNotNull);
      expect(markers[todayKey]!.pending, 1);
      expect(markers[todayKey]!.done, 1);
      expect(markers[todayKey]!.hasPending, isTrue);
      expect(markers[todayKey]!.allDone, isFalse);
      // 下月的数据不落在本月结果里
      expect(markers.length, 1);

      final allDone = await tasks.queryMonthMarkers(
        DateUtil.monthKey(DateUtil.addMonthsCalendar(today, 1)),
      );
      expect(allDone.values.single.allDone, isFalse);
      expect(allDone.values.single.pending, 1);
    });

    test('空月返回空 Map', () async {
      expect(
        await tasks.queryMonthMarkers('2000-01'),
        isEmpty,
      );
    });
  });

  group('其他查询', () {
    test('queryByDate / queryOverdue / queryOrphanPeriodic', () async {
      final today = DateUtil.today();
      await tasks.insert(buildTask(title: '今天', remindDate: today));
      await tasks.insert(buildTask(title: '逾期', remindDate: DateUtil.addDays(today, -2)));
      await tasks.insert(buildTask(title: '未来', remindDate: DateUtil.addDays(today, 5)));

      expect((await tasks.queryByDate(today)).map((t) => t.title), <String>['今天']);
      expect((await tasks.queryOverdue()).map((t) => t.title), <String>['逾期']);
      expect(await tasks.queryOrphanPeriodic(), isEmpty);
    });

    test('reorder 按给定顺序写 sort_order', () async {
      final a = await tasks.insert(buildTask(title: 'A'));
      final b = await tasks.insert(buildTask(title: 'B'));
      await tasks.reorder(<int>[b, a]);
      expect((await tasks.findById(b))!.sortOrder, 0);
      expect((await tasks.findById(a))!.sortOrder, 1);
    });

    test('markNotified 置位 is_notified', () async {
      final id = await tasks.insert(buildTask(remindTime: '09:00'));
      await tasks.markNotified(id);
      expect((await tasks.findById(id))!.isNotified, isTrue);
    });
  });

  group('模型映射', () {
    test('toMap / fromMap 往返保留全部字段', () async {
      final id = await tasks.insert(
        buildTask(
          title: '完整字段',
          remindTime: '09:30',
          priority: TodoPriority.high,
          accentColorHex: '#5856D6',
          sortOrder: 3,
        ),
      );
      final loaded = (await tasks.findById(id))!;
      expect(loaded.title, '完整字段');
      expect(loaded.remindTime, '09:30');
      expect(loaded.priority, TodoPriority.high);
      expect(loaded.accentColorHex, '#5856D6');
      expect(loaded.sortOrder, 3);
      expect(loaded.sourceType, TaskSourceType.regular);
      expect(loaded.isPeriodic, isFalse);
      expect(loaded.periodicTagLabel, isNull);
      expect(loaded.isOrphanPeriodic, isFalse);
    });
  });
}
