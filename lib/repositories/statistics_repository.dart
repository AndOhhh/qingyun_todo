import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/statistics_models.dart';
import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 统计只读聚合 DAO（docs/04 §4.4、docs/05）。
///
/// 约定：
/// - 每个指标**一条聚合 SQL**，不在 Dart 侧遍历全表（万级任务性能）；
/// - 完成率按 `remind_date` 归属，完成趋势按 `completed_at` 归属（docs/05 §1）；
/// - 硬删除的记录天然不在任何分母分子中（物理删除）；
/// - 孤儿周期记录（`source_type='PERIODIC' AND periodic_id IS NULL`）计入 M6。
class StatisticsRepository {
  StatisticsRepository(this._dbHelper);

  final DbHelper _dbHelper;

  Future<Database> get _db => _dbHelper.database;

  // ------------------------------------------------------------ M1 / M2

  /// 区间完成率（按 `remind_date` 归属，闭区间）
  Future<RateStat> completionRate(String from, String to) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done
      FROM tasks WHERE remind_date BETWEEN ? AND ?
      ''',
      <Object?>[from, to],
    );
    final row = rows.first;
    return RateStat(
      total: (row['total'] as num?)?.toInt() ?? 0,
      done: (row['done'] as num?)?.toInt() ?? 0,
    );
  }

  /// 本周点阵：周一 ~ 周日每天 (total, done)
  Future<List<WeekDayCell>> weekCells(DateTime today) async {
    final monday = DateUtil.addDays(
      DateUtil.dateOnly(today),
      -((today.weekday - 1) % 7),
    );
    final from = DateUtil.formatDate(monday);
    final to = DateUtil.formatDate(DateUtil.addDays(monday, 6));
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT remind_date, COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done
      FROM tasks WHERE remind_date BETWEEN ? AND ?
      GROUP BY remind_date
      ''',
      <Object?>[from, to],
    );
    final byDate = <String, Map<String, int>>{
      for (final r in rows)
        r['remind_date'] as String: <String, int>{
          'total': (r['total'] as num?)?.toInt() ?? 0,
          'done': (r['done'] as num?)?.toInt() ?? 0,
        },
    };
    return <WeekDayCell>[
      for (var i = 0; i < 7; i++)
        () {
          final date = DateUtil.addDays(monday, i);
          final key = DateUtil.formatDate(date);
          final cell = byDate[key];
          return WeekDayCell(
            date: date,
            total: cell?['total'] ?? 0,
            done: cell?['done'] ?? 0,
          );
        }(),
    ];
  }

  // ------------------------------------------------------------ M3

  /// 连续打卡天数：按 `date(completed_at)` 去重后从今天（今天未完成则从昨天）回溯
  Future<int> currentStreak() async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT substr(completed_at, 1, 10) AS d
      FROM tasks WHERE completed_at IS NOT NULL
      ORDER BY d DESC LIMIT 400
      ''',
    );
    final days = <DateTime>{
      for (final r in rows) DateUtil.parseDate(r['d'] as String),
    };
    final today = DateUtil.today();
    var cursor = days.contains(today) ? today : DateUtil.addDays(today, -1);
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = DateUtil.addDays(cursor, -1);
    }
    return streak;
  }

  // ------------------------------------------------------------ M4 / M5

  /// 逾期任务数（实时派生口径）
  Future<int> countOverdue() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks '
      'WHERE is_completed = 0 AND remind_date < ?',
      <Object?>[DateUtil.formatDate(DateUtil.today())],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 待处理总数
  Future<int> countPending() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE is_completed = 0',
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------------ M6

  /// 周期任务完成率：**仅已到期实例**（remind_date <= today），
  /// 含孤儿历史记录（判定依据 source_type，而非 periodic_id）
  Future<RateStat> periodicDueRate() async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done
      FROM tasks
      WHERE source_type = 'PERIODIC' AND remind_date <= ?
      ''',
      <Object?>[DateUtil.formatDate(DateUtil.today())],
    );
    final row = rows.first;
    return RateStat(
      total: (row['total'] as num?)?.toInt() ?? 0,
      done: (row['done'] as num?)?.toInt() ?? 0,
    );
  }

  // ------------------------------------------------------------ A1

  /// 完成趋势（按 `completed_at` 归属，缺失补 0）
  Future<List<TrendPoint>> completionTrend({
    required String from,
    required String to,
    required TrendGranularity granularity,
  }) async {
    final db = await _db;
    switch (granularity) {
      case TrendGranularity.hour:
        final rows = await db.rawQuery(
          '''
          SELECT CAST(substr(completed_at, 12, 2) AS INTEGER) AS h, COUNT(*) AS c
          FROM tasks
          WHERE completed_at IS NOT NULL AND substr(completed_at, 1, 10) = ?
          GROUP BY h
          ''',
          <Object?>[from],
        );
        final byHour = <int, int>{
          for (final r in rows)
            (r['h'] as num?)?.toInt() ?? 0: (r['c'] as num?)?.toInt() ?? 0,
        };
        return <TrendPoint>[
          for (var h = 0; h < 24; h++)
            TrendPoint(label: '$h', count: byHour[h] ?? 0),
        ];

      case TrendGranularity.day:
        final rows = await db.rawQuery(
          '''
          SELECT substr(completed_at, 1, 10) AS d, COUNT(*) AS c
          FROM tasks
          WHERE completed_at IS NOT NULL
            AND substr(completed_at, 1, 10) BETWEEN ? AND ?
          GROUP BY d
          ''',
          <Object?>[from, to],
        );
        final byDate = <String, int>{
          for (final r in rows)
            r['d'] as String: (r['c'] as num?)?.toInt() ?? 0,
        };
        final points = <TrendPoint>[];
        var cursor = DateUtil.parseDate(from);
        final end = DateUtil.parseDate(to);
        while (!cursor.isAfter(end)) {
          final key = DateUtil.formatDate(cursor);
          points.add(TrendPoint(
            label: '${cursor.month}/${cursor.day}',
            count: byDate[key] ?? 0,
          ));
          cursor = DateUtil.addDays(cursor, 1);
        }
        return points;

      case TrendGranularity.month:
        final rows = await db.rawQuery(
          '''
          SELECT substr(completed_at, 1, 7) AS m, COUNT(*) AS c
          FROM tasks WHERE completed_at IS NOT NULL
          GROUP BY m ORDER BY m
          ''',
        );
        if (rows.isEmpty) return const <TrendPoint>[];
        final byMonth = <String, int>{
          for (final r in rows)
            r['m'] as String: (r['c'] as num?)?.toInt() ?? 0,
        };
        // 从首个有记录的月零填充到当前月（跨度受数据约束，不会无限展开）
        final first = DateUtil.parseDate('${rows.first['m']}-01');
        final now = DateUtil.today();
        final points = <TrendPoint>[];
        var cursor = DateTime(first.year, first.month, 1);
        while (!cursor.isAfter(DateTime(now.year, now.month, 1))) {
          final key = DateUtil.monthKey(cursor);
          points.add(TrendPoint(label: key, count: byMonth[key] ?? 0));
          cursor = DateTime(cursor.year, cursor.month + 1, 1);
        }
        return points;
    }
  }

  // ------------------------------------------------------------ A2 / A3

  /// 优先级分布：范围内（按 `remind_date`）任务的优先级构成
  Future<List<PrioritySlice>> priorityDistribution(String from, String to) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT priority, COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done
      FROM tasks WHERE remind_date BETWEEN ? AND ?
      GROUP BY priority
      ''',
      <Object?>[from, to],
    );
    final byPriority = <TodoPriority, PrioritySlice>{
      for (final r in rows)
        TodoPriority.fromDbName(r['priority'] as String?): PrioritySlice(
          priority: TodoPriority.fromDbName(r['priority'] as String?),
          total: (r['total'] as num?)?.toInt() ?? 0,
          done: (r['done'] as num?)?.toInt() ?? 0,
        ),
    };
    // 固定顺序返回，空优先级也占位（环形图图例稳定）
    return <PrioritySlice>[
      for (final p in TodoPriority.values)
        byPriority[p] ?? PrioritySlice(priority: p, total: 0, done: 0),
    ];
  }

  /// 星期分布：范围内任务按提醒日是星期几聚合（1=周一 … 7=周日）
  Future<List<WeekdayBar>> weekdayDistribution(String from, String to) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT CAST(strftime('%w', remind_date) AS INTEGER) AS w, COUNT(*) AS c
      FROM tasks WHERE remind_date BETWEEN ? AND ?
      GROUP BY w
      ''',
      <Object?>[from, to],
    );
    final bySundayIndex = <int, int>{
      for (final r in rows)
        (r['w'] as num?)?.toInt() ?? 0: (r['c'] as num?)?.toInt() ?? 0,
    };
    return <WeekdayBar>[
      // strftime %w：0=周日；转成 1=周一 … 7=周日
      for (var weekday = 1; weekday <= 7; weekday++)
        WeekdayBar(
          weekday: weekday,
          count: bySundayIndex[weekday % 7] ?? 0,
        ),
    ];
  }

  /// 范围内任务总数（图表空态判断）
  Future<int> countInRange(String from, String to) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE remind_date BETWEEN ? AND ?',
      <Object?>[from, to],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------------ A7

  /// 月历热力图：某月每天的实际完成数（按 `completed_at` 归属）
  Future<Map<String, int>> completionHeatmap(String monthKey) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT substr(completed_at, 1, 10) AS d, COUNT(*) AS c
      FROM tasks
      WHERE completed_at IS NOT NULL AND substr(completed_at, 1, 7) = ?
      GROUP BY d
      ''',
      <Object?>[monthKey],
    );
    return <String, int>{
      for (final r in rows)
        r['d'] as String: (r['c'] as num?)?.toInt() ?? 0,
    };
  }
}
