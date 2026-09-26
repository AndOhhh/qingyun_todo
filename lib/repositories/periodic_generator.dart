import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/repositories/cycle_counter.dart';
import 'package:qingyun_todo/repositories/periodic_skips.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 周期实例生成引擎（FR-13，算法见 docs/04 §5）。
///
/// 关键性质：
/// - **幂等**：`UNIQUE(periodic_item_id, cycle_index)` + `ON CONFLICT DO NOTHING`，
///   同一窗口连续触发两次行数不变（TC-07）；
/// - **不补生成历史**：窗口下限恒为「今天」，从今天所在轮起算（Q1）；
/// - **短月份跳过**：`day_offset >= cycleLength(k)` 的项在该轮不生成（docs/02 §7.2）；
/// - **模板修改不追溯**：已存在的实例保持原日期，新规则只影响尚未生成的轮次（Q8）。
class PeriodicGenerator {
  PeriodicGenerator(this._dbHelper);

  final DbHelper _dbHelper;

  /// 预生成窗口天数：今天 → 今天 + 30 天
  static const int kWindowDays = 30;

  /// 单次生成的轮次上限，防御异常规则导致的死循环
  static const int kMaxCyclesPerRun = 2000;

  Future<Database> get _db => _dbHelper.database;

  /// 触发时机①④：App 启动 / 跨日校准 —— 为**所有启用中**的周期滚动生成窗口内实例。
  ///
  /// 返回新增行数。异常不吞（docs/04 §3.2）：由 store 层兜底，
  /// 幂等性保证下次触发可安全重试（docs/07 C4-6）。
  Future<int> generateForWindow({
    DateTime? today,
    DatabaseExecutor? executor,
  }) {
    final from = DateUtil.dateOnly(today ?? DateUtil.today());
    return _run(
      from: from,
      to: DateUtil.addDays(from, kWindowDays),
      executor: executor,
    );
  }

  /// 触发时机②：新建 / 修改周期或周期项后，为该周期补生成窗口内实例
  Future<int> generateForPeriodicId(
    int periodicId, {
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) {
    final f = DateUtil.dateOnly(from ?? DateUtil.today());
    return _run(
      from: f,
      to: DateUtil.dateOnly(to ?? DateUtil.addDays(f, kWindowDays)),
      executor: executor,
      periodicIds: <int>[periodicId],
    );
  }

  /// 触发时机③：某一轮全部完成后生成**下一轮**（FR-15 / TC-08）。
  ///
  /// 与窗口生成不同：这里不受 30 天窗口限制（否则「每 40 天」这类长周期
  /// 永远等不到下一轮），但仍遵守 `is_active`、`end_date`，
  /// 且**不补生成已过去的轮次**（Q1）。
  Future<int> generateCycle(
    int periodicId,
    int cycleIndex, {
    DatabaseExecutor? executor,
  }) async {
    Future<int> action(DatabaseExecutor e) async {
      final periodic = await _loadPeriodic(e, periodicId);
      if (periodic == null || !periodic.isActive) return 0;
      final items = await _loadItems(e, periodicId);
      if (items.isEmpty) return 0;
      // 不补生成历史轮次
      if (periodic.rule.cycleStart(cycleIndex).isBefore(DateUtil.today())) return 0;
      return _insertCycle(
        periodic: periodic,
        items: items,
        cycleIndex: cycleIndex,
        existing: await _existingKeys(e, periodicId),
        skipped: await PeriodicSkips.loadKeys(e, periodicId),
        executor: e,
      );
    }

    if (executor != null) return action(executor);
    final db = await _db;
    return db.transaction<int>(action);
  }

  /// 生成窗口内实例 **+ 轮数校准**：新建 / 修改周期或周期项后调用（docs/07 C4-2）。
  ///
  /// 校准是必要的：新增周期项可能给「本轮」补出未完成实例（该轮不再算完结），
  /// 删除周期项则可能让某一轮变成完结。重算幂等，可安全反复调用。
  Future<void> regenerateAndSync(
    int periodicId, {
    DateTime? from,
    DateTime? to,
    DatabaseExecutor? executor,
  }) async {
    Future<void> action(DatabaseExecutor e) async {
      await generateForPeriodicId(periodicId, from: from, to: to, executor: e);
      await CycleCounter.sync(e, periodicId);
    }

    if (executor != null) {
      await action(executor);
      return;
    }
    final db = await _db;
    await db.transaction<void>(action);
  }

  // ---------------------------------------------------------------- 内部

  Future<int> _run({
    required DateTime from,
    required DateTime to,
    DatabaseExecutor? executor,
    List<int>? periodicIds,
  }) async {
    Future<int> action(DatabaseExecutor e) async {
      final String where;
      final List<Object?> args;
      if (periodicIds == null) {
        where = 'is_active = 1';
        args = const <Object?>[];
      } else {
        if (periodicIds.isEmpty) return 0;
        where =
            'is_active = 1 AND id IN (${List.filled(periodicIds.length, '?').join(',')})';
        args = periodicIds;
      }
      final rows = await e.query(
        'periodic_configs',
        where: where,
        whereArgs: args,
      );
      var inserted = 0;
      for (final row in rows) {
        final periodic = Periodic.fromMap(row);
        final endDate = periodic.endDate;
        // 已整体到期的周期直接跳过
        if (endDate != null && DateUtil.dateOnly(endDate).isBefore(from)) continue;
        final items = await _loadItems(e, periodic.id!);
        if (items.isEmpty) continue;
        inserted += await _generateRange(
          periodic: periodic,
          items: items,
          from: from,
          to: to,
          executor: e,
        );
      }
      return inserted;
    }

    if (executor != null) return action(executor);
    final db = await _db;
    return db.transaction<int>(action);
  }

  Future<int> _generateRange({
    required Periodic periodic,
    required List<PeriodicItem> items,
    required DateTime from,
    required DateTime to,
    required DatabaseExecutor executor,
  }) async {
    final rule = periodic.rule;
    final existing = await _existingKeys(executor, periodic.id!);
    final skipped = await PeriodicSkips.loadKeys(executor, periodic.id!);

    // 起始轮次：第一个「本轮最后一天 >= from」的轮（docs/04 §5 的 kStart）
    var maxOffset = 0;
    for (final item in items) {
      if (item.dayOffset > maxOffset) maxOffset = item.dayOffset;
    }

    var inserted = 0;
    var k = rule.firstCycleIndexOnOrAfter(DateUtil.addDays(from, -maxOffset));
    for (var guard = 0; guard < kMaxCyclesPerRun; guard++, k++) {
      if (rule.cycleStart(k).isAfter(to)) break;
      inserted += await _insertCycle(
        periodic: periodic,
        items: items,
        cycleIndex: k,
        existing: existing,
        skipped: skipped,
        from: from,
        to: to,
        executor: executor,
      );
    }
    return inserted;
  }

  /// 写入某一轮的全部实例；[from] / [to] 为空表示不做窗口裁剪
  Future<int> _insertCycle({
    required Periodic periodic,
    required List<PeriodicItem> items,
    required int cycleIndex,
    required Set<String> existing,
    required Set<String> skipped,
    required DatabaseExecutor executor,
    DateTime? from,
    DateTime? to,
  }) async {
    final rule = periodic.rule;
    final cycleStart = rule.cycleStart(cycleIndex);
    final cycleLength = rule.cycleLength(cycleIndex);
    final endDate = periodic.endDate == null
        ? null
        : DateUtil.dateOnly(periodic.endDate!);

    var inserted = 0;
    for (final item in items) {
      // 短月份跳过：该轮没有「第 day_offset + 1 天」
      if (item.dayOffset >= cycleLength) continue;
      final remindDate = DateUtil.addDays(cycleStart, item.dayOffset);
      if (from != null && remindDate.isBefore(from)) continue;
      if (to != null && remindDate.isAfter(to)) continue;
      if (endDate != null && remindDate.isAfter(endDate)) continue;
      final key = '${item.id}:$cycleIndex';
      // 已生成过（幂等）或用户已主动删除过（墓碑）都不再写入
      if (existing.contains(key) || skipped.contains(key)) continue;

      final now = DateUtil.formatTimestamp(DateTime.now());
      await executor.rawInsert(
        '''
        INSERT INTO tasks (
          title, remark, remind_date, remind_time, priority, accent_color,
          is_completed, completed_at, source_type, periodic_id, periodic_item_id,
          cycle_index, periodic_name_snapshot, sort_order, is_notified,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, 0, NULL, 'PERIODIC', ?, ?, ?, ?, ?, 0, ?, ?)
        ON CONFLICT (periodic_item_id, cycle_index) DO NOTHING
        ''',
        <Object?>[
          item.title,
          item.remark,
          DateUtil.formatDate(remindDate),
          item.remindTime,
          item.priority.dbName,
          item.accentColorHex,
          periodic.id,
          item.id,
          cycleIndex,
          // 名称快照：周期改名后不回写，删除周期后仍能显示「周期·xxx」
          periodic.name,
          item.sortOrder,
          now,
          now,
        ],
      );
      existing.add(key);
      inserted++;
    }
    return inserted;
  }

  /// 已存在的 (周期项, 轮次) 组合，一次性取回避免逐行试探
  Future<Set<String>> _existingKeys(DatabaseExecutor e, int periodicId) async {
    final rows = await e.query(
      'tasks',
      columns: <String>['periodic_item_id', 'cycle_index'],
      where: 'periodic_id = ? AND periodic_item_id IS NOT NULL '
          'AND cycle_index IS NOT NULL',
      whereArgs: <Object?>[periodicId],
    );
    return <String>{
      for (final r in rows)
        '${(r['periodic_item_id'] as num).toInt()}:${(r['cycle_index'] as num).toInt()}',
    };
  }

  Future<Periodic?> _loadPeriodic(DatabaseExecutor e, int id) async {
    final rows = await e.query(
      'periodic_configs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Periodic.fromMap(rows.first);
  }

  Future<List<PeriodicItem>> _loadItems(DatabaseExecutor e, int periodicId) async {
    final rows = await e.query(
      'periodic_items',
      where: 'periodic_id = ?',
      whereArgs: <Object?>[periodicId],
      orderBy: 'day_offset ASC, sort_order ASC, id ASC',
    );
    return rows.map(PeriodicItem.fromMap).toList(growable: false);
  }
}
