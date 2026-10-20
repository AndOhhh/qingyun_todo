import 'package:flutter_test/flutter_test.dart';
import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/repositories/statistics_repository.dart';
import 'package:qingyun_todo/utils/date_util.dart';

import 'test_support.dart';

/// 统计口径测试（docs/05 §1）：完成率按 remind_date、趋势按 completed_at、
/// 删除不进分母、孤儿周期记录计入 M6、分母为 0 显示 `--`。
void main() {
  late TestStore store;
  late StatisticsRepository stats;
  late DateTime today;

  setUp(() async {
    store = await TestStore.create();
    stats = StatisticsRepository(store.db);
    today = DateUtil.today();
  });

  tearDown(() async => store.dispose());

  String key(DateTime d) => DateUtil.formatDate(d);

  /// 直接写库构造「在指定时刻完成」的记录（toggleComplete 只能写当前时间）
  Future<int> insertCompleted({
    required DateTime remindDate,
    required DateTime completedAt,
    String title = '已完成',
    TaskSourceType sourceType = TaskSourceType.regular,
    int? periodicId,
  }) async {
    final db = await store.db.database;
    return db.insert('tasks', <String, Object?>{
      'title': title,
      'remind_date': key(remindDate),
      'priority': 'none',
      'is_completed': 1,
      'completed_at': DateUtil.formatTimestamp(completedAt),
      'source_type': sourceType.dbName,
      'periodic_id': periodicId,
      'sort_order': 0,
      'is_notified': 0,
      'created_at': DateUtil.formatTimestamp(completedAt),
      'updated_at': DateUtil.formatTimestamp(completedAt),
    });
  }

  Future<int> insertPending({
    required DateTime remindDate,
    TodoPriority priority = TodoPriority.none,
    TaskSourceType sourceType = TaskSourceType.regular,
  }) {
    return store.tasks.insert(
      Todo(
        title: '待办',
        remindDate: remindDate,
        priority: priority,
        sourceType: sourceType,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  group('M1/M2 完成率归属（remind_date）', () {
    test('昨天提醒、今天完成 → 计入昨天而非今天', () async {
      await insertCompleted(
        remindDate: DateUtil.addDays(today, -1),
        completedAt: DateTime.now(),
      );
      final todayRate = await stats.completionRate(key(today), key(today));
      expect(todayRate.total, 0);
      expect(todayRate.rate, isNull);
      expect(todayRate.rateText, '--');

      final yesterdayRate = await stats.completionRate(
        key(DateUtil.addDays(today, -1)),
        key(DateUtil.addDays(today, -1)),
      );
      expect(yesterdayRate.total, 1);
      expect(yesterdayRate.done, 1);
      expect(yesterdayRate.rateText, '100%');
    });

    test('硬删除的记录不进分母（Q5）', () async {
      final id = await insertPending(remindDate: today);
      expect((await stats.completionRate(key(today), key(today))).total, 1);
      await store.tasks.deleteById(id);
      expect((await stats.completionRate(key(today), key(today))).total, 0);
    });
  });

  group('M2 本周点阵', () {
    test('周一起算 7 格，当天统计正确', () async {
      await insertPending(remindDate: today);
      await insertCompleted(remindDate: today, completedAt: DateTime.now());
      final cells = await stats.weekCells(today);
      expect(cells, hasLength(7));
      expect(cells.first.date.weekday, 1, reason: '周一开头');
      final todayCell = cells.singleWhere((c) => c.date == today);
      expect(todayCell.total, 2);
      expect(todayCell.done, 1);
      expect(todayCell.isPartial, isTrue);
    });
  });

  group('M3 连续打卡', () {
    test('无完成记录 → 0', () async {
      expect(await stats.currentStreak(), 0);
    });

    test('今天未完成但昨天完成 → 不断链，从昨天起算', () async {
      await insertCompleted(
        remindDate: DateUtil.addDays(today, -1),
        completedAt: DateUtil.addDays(today, -1),
      );
      expect(await stats.currentStreak(), 1);
    });

    test('今天 + 昨天 + 前天 → 3', () async {
      for (var i = 0; i < 3; i++) {
        await insertCompleted(
          remindDate: DateUtil.addDays(today, -i),
          completedAt: DateUtil.addDays(today, -i),
        );
      }
      expect(await stats.currentStreak(), 3);
    });

    test('同一天多条完成只算一天；中间断链即止', () async {
      await insertCompleted(remindDate: today, completedAt: today);
      await insertCompleted(remindDate: today, completedAt: today);
      await insertCompleted(
        remindDate: DateUtil.addDays(today, -2),
        completedAt: DateUtil.addDays(today, -2),
      );
      expect(await stats.currentStreak(), 1, reason: '昨天缺失 → 断链');
    });
  });

  group('M4/M5', () {
    test('逾期与待处理计数', () async {
      await insertPending(remindDate: DateUtil.addDays(today, -2));
      await insertPending(remindDate: today);
      await insertCompleted(remindDate: DateUtil.addDays(today, -3), completedAt: today);
      expect(await stats.countOverdue(), 1);
      expect(await stats.countPending(), 2);
    });
  });

  group('M6 周期完成率', () {
    test('仅统计已到期实例；孤儿记录计入', () async {
      // 已完成的孤儿记录（来源周期已删除）→ 计入
      await insertCompleted(
        remindDate: DateUtil.addDays(today, -1),
        completedAt: DateUtil.addDays(today, -1),
        sourceType: TaskSourceType.periodic,
      );
      // 已到期的未完成周期实例 → 进分母
      await insertPending(
        remindDate: today,
        sourceType: TaskSourceType.periodic,
      );
      // 未到期（未来）的周期实例 → 不进分母
      await insertPending(
        remindDate: DateUtil.addDays(today, 5),
        sourceType: TaskSourceType.periodic,
      );
      final rate = await stats.periodicDueRate();
      expect(rate.total, 2);
      expect(rate.done, 1);
      expect(rate.rateText, '50%');
    });
  });

  group('A1 完成趋势（completed_at 归属 + 补 0）', () {
    test('day 粒度缺失日期补 0', () async {
      await insertCompleted(
        remindDate: today,
        completedAt: DateUtil.addDays(today, -2),
      );
      await insertCompleted(remindDate: today, completedAt: today);
      final points = await stats.completionTrend(
        from: key(DateUtil.addDays(today, -2)),
        to: key(today),
        granularity: TrendGranularity.day,
      );
      expect(points, hasLength(3));
      expect(points.map((p) => p.count).toList(), <int>[1, 0, 1]);
    });

    test('hour 粒度固定 24 个点', () async {
      await insertCompleted(remindDate: today, completedAt: today);
      final points = await stats.completionTrend(
        from: key(today),
        to: key(today),
        granularity: TrendGranularity.hour,
      );
      expect(points, hasLength(24));
      expect(points.where((p) => p.count > 0).length, 1);
    });

    test('month 粒度从首个有记录的月零填充到当前月', () async {
      await insertCompleted(
        remindDate: today,
        completedAt: DateUtil.addMonths(today, -2),
      );
      final points = await stats.completionTrend(
        from: '0000-01-01',
        to: '9999-12-31',
        granularity: TrendGranularity.month,
      );
      expect(points, hasLength(3));
      expect(points.first.count, 1);
      expect(points[1].count, 0);
    });
  });

  group('A2/A3 分布', () {
    test('优先级分布固定 4 片且顺序稳定', () async {
      await insertPending(remindDate: today, priority: TodoPriority.high);
      await insertPending(remindDate: today, priority: TodoPriority.high);
      final slices = await stats.priorityDistribution(key(today), key(today));
      expect(slices.map((s) => s.priority), TodoPriority.values);
      expect(
        slices.firstWhere((s) => s.priority == TodoPriority.high).total,
        2,
      );
      expect(
        slices.firstWhere((s) => s.priority == TodoPriority.low).total,
        0,
      );
    });

    test('星期分布：周一的任务落在 weekday=1', () async {
      final monday = DateUtil.addDays(today, -((today.weekday - 1) % 7));
      await insertPending(remindDate: monday);
      final bars = await stats.weekdayDistribution(key(monday), key(monday));
      expect(bars, hasLength(7));
      expect(bars[0].count, 1);
      expect(bars[0].weekday, 1);
      expect(bars.where((b) => b.count > 0).length, 1);
    });
  });

  group('A7 热力图', () {
    test('按 completed_at 月份聚合', () async {
      await insertCompleted(remindDate: today, completedAt: today);
      await insertCompleted(remindDate: today, completedAt: today);
      final heat = await stats.completionHeatmap(DateUtil.monthKey(today));
      expect(heat[key(today)], 2);
      expect(
        await stats.completionHeatmap(
          DateUtil.monthKey(DateUtil.addMonths(today, -1)),
        ),
        isEmpty,
      );
    });
  });

  group('StatsRange 边界', () {
    test('本周为周一~周日闭区间；全部为极大区间', () {
      final week = StatsRange.week.bounds(today);
      expect(DateUtil.parseDate(week[0]).weekday, 1);
      expect(DateUtil.parseDate(week[1]).weekday, 7);
      expect(StatsRange.all.bounds(today), <String>['0000-01-01', '9999-12-31']);
      final month = StatsRange.month.bounds(today);
      expect(month[0], key(DateUtil.firstDayOfMonth(today)));
      expect(month[1], key(DateUtil.lastDayOfMonth(today)));
    });
  });
}
