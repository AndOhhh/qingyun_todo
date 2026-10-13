import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/services/notification_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repositories/test_support.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 通知同步计划（纯函数）的口径测试：排期 / 补发 / 静默三类互不越界。
void main() {
  final now = DateTime(2026, 10, 11, 12, 0);

  Todo task({
    int id = 1,
    required DateTime due,
    bool notified = false,
    bool completed = false,
    String? time,
  }) {
    return Todo(
      id: id,
      title: 't$id',
      remindDate: DateUtil.dateOnly(due),
      remindTime: time ?? DateUtil.formatTime(due),
      isCompleted: completed,
      isNotified: notified,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('到期在未来 → 排期（无论 is_notified）', () {
    final future = task(id: 1, due: now.add(const Duration(hours: 2)));
    final plan = NotificationService.computePlan(
      dueTasks: <Todo>[future],
      now: now,
    );
    expect(plan.toSchedule.map((t) => t.id), <int>[1]);
    expect(plan.toFireNow, isEmpty);
    expect(plan.toMarkSilent, isEmpty);
  });

  test('已到期 + 未通知 + 窗口内 → 立即补发', () {
    final recent = task(id: 2, due: now.subtract(const Duration(hours: 3)));
    final plan = NotificationService.computePlan(
      dueTasks: <Todo>[recent],
      now: now,
    );
    expect(plan.toFireNow.map((t) => t.id), <int>[2]);
    expect(plan.toSchedule, isEmpty);
  });

  test('已到期 + 未通知 + 超出 24h 窗口 → 静默标记，不补发', () {
    final old = task(id: 3, due: now.subtract(const Duration(hours: 30)));
    final plan = NotificationService.computePlan(
      dueTasks: <Todo>[old],
      now: now,
    );
    expect(plan.toMarkSilent, <int>[3]);
    expect(plan.toFireNow, isEmpty);
  });

  test('已到期 + 已通知（排期时已置位）→ 什么都不做，防重复', () {
    final notified = task(
      id: 4,
      due: now.subtract(const Duration(minutes: 30)),
      notified: true,
    );
    final plan = NotificationService.computePlan(
      dueTasks: <Todo>[notified],
      now: now,
    );
    expect(plan.isEmpty, isTrue);
  });

  test('无提醒时间 / 缺 id 的任务被忽略（调用方已过滤，此处双保险）', () {
    final noTime = Todo(
      id: 5,
      title: '全天',
      remindDate: DateUtil.dateOnly(now),
      remindTime: null,
      createdAt: now,
      updatedAt: now,
    );
    final noId = Todo(
      title: '未落库',
      remindDate: DateUtil.dateOnly(now),
      remindTime: '09:00',
      createdAt: now,
      updatedAt: now,
    );
    final plan = NotificationService.computePlan(
      dueTasks: <Todo>[noTime, noId],
      now: now,
    );
    expect(plan.isEmpty, isTrue);
  });

  test('混合场景：三类各归其位', () {
    final plan = NotificationService.computePlan(
      dueTasks: <Todo>[
        task(id: 10, due: now.add(const Duration(days: 1))),
        task(id: 11, due: now.subtract(const Duration(minutes: 5))),
        task(id: 12, due: now.subtract(const Duration(days: 2))),
        task(
          id: 13,
          due: now.subtract(const Duration(minutes: 5)),
          notified: true,
        ),
      ],
      now: now,
    );
    expect(plan.toSchedule.map((t) => t.id), <int>[10]);
    expect(plan.toFireNow.map((t) => t.id), <int>[11]);
    expect(plan.toMarkSilent, <int>[12]);
  });

  test('remindAt 解析：日期 + 时间组合为本地时刻', () {
    final t = task(id: 20, due: DateTime(2026, 10, 11, 9, 30));
    expect(t.remindAt, DateTime(2026, 10, 11, 9, 30));
    expect(
      Todo(
        title: 'x',
        remindDate: DateTime(2026, 10, 11),
        createdAt: now,
        updatedAt: now,
      ).remindAt,
      isNull,
    );
  });
  group('未初始化时的降级行为', () {
    test('init 失败（测试环境无插件）→ available=false 且 reconcile 为空操作', () async {
      sqfliteFfiInit();
      final store = await TestStore.create();
      final now = DateTime.now();
      final id = await store.tasks.insert(
        Todo(
          title: '带提醒时间',
          remindDate: DateUtil.dateOnly(now),
          remindTime: '09:00',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final service = NotificationService(store.tasks);
      await service.init(); // 测试环境插件缺失 → 降级
      expect(service.isAvailable, isFalse);

      await service.reconcile(); // 不得抛异常、不得写库
      final task = (await store.tasks.findById(id))!;
      expect(task.isNotified, isFalse);

      final health = await service.checkHealth();
      expect(health.blocker, NotificationBlocker.unavailable);
      expect(health.pendingCount, 0);
      await store.dispose();
    });
  });
}
