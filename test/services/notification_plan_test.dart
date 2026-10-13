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

  group('前台兜底决策 computeForegroundPlan', () {
    Todo due({required int id, required DateTime at, bool notified = true}) {
      return Todo(
        id: id,
        title: 't$id',
        remindDate: DateUtil.dateOnly(at),
        remindTime: DateUtil.formatTime(at),
        isNotified: notified,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('即将到期（<=90s）且 OS 已排期 → 收回排期，由前台接管', () {
      final soon = due(id: 1, at: now.add(const Duration(seconds: 30)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[soon],
        pendingIds: <int>{1},
        shownIds: const <int>{},
        now: now,
      );
      expect(plan.toCancel, <int>[1]);
      expect(plan.toShow, isEmpty);
      expect(plan.assumeDelivered, isEmpty);
    });

    test('已到期 + 本会话未发 + OS 排期仍在（闹钟被 ROM 丢弃）→ 补发并收回', () {
      final late = due(id: 2, at: now.subtract(const Duration(seconds: 40)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[late],
        pendingIds: <int>{2},
        shownIds: const <int>{},
        now: now,
      );
      expect(plan.toShow.map((t) => t.id), <int>[2]);
      expect(plan.toCancel, <int>[2]);
      expect(plan.assumeDelivered, isEmpty);
    });

    test('播种趟：已到期 + OS 排期消失（后台已送达）→ 记为已送达，不补发', () {
      final delivered = due(id: 3, at: now.subtract(const Duration(seconds: 40)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[delivered],
        pendingIds: const <int>{},
        shownIds: const <int>{},
        now: now,
        seeding: true,
      );
      expect(plan.toShow, isEmpty);
      expect(plan.assumeDelivered, <int>[3]);
    });

    test('巡检趟回归（一加13 踩坑）：到期前已被收回排期 → 到期必须补发', () {
      // 90s 前置接管把 OS 排期 cancel 掉了，于是到期时 isPending=false；
      // 旧实现误判为「后台已送达」导致前台永远不响
      final preempted = due(id: 7, at: now.subtract(const Duration(seconds: 10)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[preempted],
        pendingIds: const <int>{},
        shownIds: const <int>{},
        now: now,
      );
      expect(plan.toShow.map((t) => t.id), <int>[7]);
      expect(plan.toCancel, isEmpty);
      expect(plan.assumeDelivered, isEmpty);
    });

    test('播种趟：已到期但 OS 排期仍在（后台被 ROM 丢弃）→ 补发并收回', () {
      final dropped = due(id: 8, at: now.subtract(const Duration(seconds: 30)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[dropped],
        pendingIds: <int>{8},
        shownIds: const <int>{},
        now: now,
        seeding: true,
      );
      expect(plan.toShow.map((t) => t.id), <int>[8]);
      expect(plan.toCancel, <int>[8]);
      expect(plan.assumeDelivered, isEmpty);
    });

    test('本会话已发过 → 跳过，防双发', () {
      final shown = due(id: 4, at: now.subtract(const Duration(seconds: 40)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[shown],
        pendingIds: <int>{4},
        shownIds: const <int>{4},
        now: now,
      );
      expect(plan.toShow, isEmpty);
      expect(plan.toCancel, isEmpty);
    });

    test('到期超过 5 分钟 → 不补发（过期噪音）', () {
      final stale = due(id: 5, at: now.subtract(const Duration(minutes: 6)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[stale],
        pendingIds: <int>{5},
        shownIds: const <int>{},
        now: now,
      );
      expect(plan.toShow, isEmpty);
    });

    test('距到期 > 90s → 不动 OS 排期', () {
      final far = due(id: 6, at: now.add(const Duration(minutes: 10)));
      final plan = NotificationService.computeForegroundPlan(
        tasks: <Todo>[far],
        pendingIds: <int>{6},
        shownIds: const <int>{},
        now: now,
      );
      expect(plan.toCancel, isEmpty);
      expect(plan.toShow, isEmpty);
    });
  });
}
