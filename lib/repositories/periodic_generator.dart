import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/repositories/cycle_counter.dart';
import 'package:qingyun_todo/repositories/periodic_round_policy.dart';
import 'package:qingyun_todo/repositories/periodic_skips.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 周期实例生成引擎（FR-13）—— **一轮一期** 口径（N13）。
///
/// 与原「滚动铺满 30 天窗口」的差别：那时一次就把未来十几轮全部写库，
/// 待办页「后续」分组因此堆满同一周期的未来项。现在只保证每个周期
/// **当前轮**（见 [PeriodicRoundPolicy]）的实例存在：
///
/// - **本轮未结束** → 不生成任何后续轮次；
/// - **本轮全部完成** → 生成下一轮（`PeriodicCompletion` 触发，见触发时机③）；
/// - **本轮整轮逾期** → 顺延生成「今天所在轮」，错过那一轮的遗留实例保留在库中
///   （不再补历史轮次，也不删用户数据）；
/// - **旧口径遗留清理**：晚于本轮的未完成实例在生成时删除，让已升级的库自动收敛
///   到一轮一期（已完成的实例作为历史保留）。
///
/// - **规则/日期变更重建**（N14）：起始日 / 间隔 / 事项天序-提醒时间变更时，
///   未完成计划按新规则从「今天所在轮」重建（[rebuildPending]）——否则旧实例会把
///   「本轮」钉在旧规则的轮次号上，新规则算出的「今天该做的事」永远生成不出来；
///
/// 其它不变的性质：
/// - **幂等**：`UNIQUE(periodic_item_id, cycle_index)` + `ON CONFLICT DO NOTHING`；
/// - **不补生成历史**：任何轮次只写 `remind_date >= today` 的项（Q1）；
/// - **短月份跳过**：`day_offset >= cycleLength(k)` 的项在该轮不生成（docs/02 §7.2）；
/// - **模板修改不追溯**：已存在的实例保持原日期，新规则只影响本轮尚未生成的项（Q8）。
class PeriodicGenerator {
  PeriodicGenerator(this._dbHelper);

  final DbHelper _dbHelper;

  /// [rebuildPending] 顺延探测上限：防御异常历史数据导致的死循环
  static const int kRebuildProbeLimit = 400;

  Future<Database> get _db => _dbHelper.database;

  /// 触发时机①④：App 启动 / 跨日校准 —— 为**所有启用中**的周期对齐本轮实例。
  ///
  /// 返回新增行数。异常不吞（docs/04 §3.2）：由 store 层兜底，
  /// 幂等性保证下次触发可安全重试（docs/07 C4-6）。
  Future<int> generateCurrentRounds({
    DateTime? today,
    DatabaseExecutor? executor,
  }) =>
      _run(today: today, executor: executor);

  /// 触发时机②③：新建 / 修改周期或周期项后、本轮完结后 —— 对齐该周期的本轮实例。
  Future<int> generateForPeriodicId(
    int periodicId, {
    DateTime? today,
    DatabaseExecutor? executor,
  }) =>
      _run(
        today: today,
        executor: executor,
        periodicIds: <int>[periodicId],
      );

  /// 生成 + 轮数校准：新建 / 修改周期或周期项后调用（docs/07 C4-2）。
  ///
  /// 校准是必要的：新增周期项可能给「本轮」补出未完成实例（该轮不再算完结），
  /// 删除周期项则可能让某一轮变成完结。重算幂等，可安全反复调用。
  Future<void> regenerateAndSync(
    int periodicId, {
    DateTime? today,
    DatabaseExecutor? executor,
  }) async {
    Future<void> action(DatabaseExecutor e) async {
      await generateForPeriodicId(periodicId, today: today, executor: e);
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
    DateTime? today,
    DatabaseExecutor? executor,
    List<int>? periodicIds,
  }) async {
    final day = DateUtil.dateOnly(today ?? DateUtil.today());

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
        if (endDate != null && DateUtil.dateOnly(endDate).isBefore(day)) continue;
        final items = await _loadItems(e, periodic.id!);
        if (items.isEmpty) continue;

        final instances = await _loadInstances(e, periodic.id!);
        final ceiling = PeriodicRoundPolicy.currentRound(
          rule: periodic.rule,
          instances: instances,
          today: day,
        );

        inserted += await _insertCycle(
          periodic: periodic,
          items: items,
          cycleIndex: ceiling,
          existing: await _existingKeys(e, periodic.id!),
          skipped: await PeriodicSkips.loadKeys(e, periodic.id!),
          from: day,
          executor: e,
        );
        // 旧口径遗留：晚于本轮的未完成实例不再属于「当期」，删除收敛
        await _pruneAfterCycle(e, periodic.id!, ceiling);
      }
      return inserted;
    }

    if (executor != null) return action(executor);
    final db = await _db;
    return db.transaction<int>(action);
  }

  /// 写入某一轮的全部实例；[from] 之前（补记）与整体到期后的项跳过
  Future<int> _insertCycle({
    required Periodic periodic,
    required List<PeriodicItem> items,
    required int cycleIndex,
    required Set<String> existing,
    required Set<String> skipped,
    required DatabaseExecutor executor,
    DateTime? from,
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
      // Q1：不补生成已过去的日期
      if (from != null && remindDate.isBefore(from)) continue;
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

  /// 删除晚于本轮 ceiling 的未完成实例（旧「30 天窗口」口径的遗留）。
  ///
  /// 已完成实例属于历史，一律保留；早于本轮的未完成实例（错过的那一轮）同样保留，
  /// 由 [PeriodicRoundPolicy.visibleOnTodoPage] 决定是否展示。
  Future<void> _pruneAfterCycle(
    DatabaseExecutor e,
    int periodicId,
    int ceiling,
  ) async {
    await e.delete(
      'tasks',
      where: 'periodic_id = ? AND cycle_index IS NOT NULL '
          'AND is_completed = 0 AND cycle_index > ?',
      whereArgs: <Object?>[periodicId, ceiling],
    );
  }

  /// 规则 / 日期类变更后按新规则**重建未完成计划**（N14）。
  ///
  /// 为什么需要：「模板修改不追溯」只对**历史**（已完成实例）成立。待办计划
  /// 尚未发生，若继续沿用旧实例上的日期与轮次号，「本轮」会被钉在旧编号上，
  /// 新规则算出的「今天该做的事」永远生成不出来（实测：改过起始日/间隔后，
  /// 当天显示的是旧规则那一项）。
  ///
  /// 口径：
  /// - 计划落点 = 「今天所在轮」，并跳过已整体完成的轮次（历史已做完则不倒退）；
  /// - 删除该周期（或 [onlyItemId] 指定事项）的**全部未完成实例**后重建当前轮；
  ///   已完成实例原样保留为历史；
  /// - [onlyItemId] 非空 = 事项改了天序 / 提醒时间；为空 = 周期起始日或间隔变了。
  Future<int> rebuildPending(
    int periodicId, {
    int? onlyItemId,
    DateTime? today,
    DatabaseExecutor? executor,
  }) async {
    final day = DateUtil.dateOnly(today ?? DateUtil.today());

    Future<int> action(DatabaseExecutor e) async {
      final periodic = await _loadPeriodic(e, periodicId);
      if (periodic == null || !periodic.isActive) return 0;
      final endDate = periodic.endDate;
      if (endDate != null && DateUtil.dateOnly(endDate).isBefore(day)) return 0;
      final items = await _loadItems(e, periodicId);
      if (items.isEmpty) return 0;

      // 落点：今天所在轮；已被历史整体完成的轮次顺延跳过（防御上限见 kRebuildProbeLimit）
      var ceiling = math.max(0, periodic.rule.cycleIndexOf(day));
      for (var probe = 0;
          probe < kRebuildProbeLimit &&
              await _isCycleFullyCompleted(e, periodicId, ceiling);
          probe++) {
        ceiling++;
      }

      final where = StringBuffer('periodic_id = ? AND is_completed = 0');
      final args = <Object?>[periodicId];
      if (onlyItemId != null) {
        where.write(' AND periodic_item_id = ?');
        args.add(onlyItemId);
      }
      await e.delete(
        'tasks',
        where: where.toString(),
        whereArgs: args,
      );

      final inserted = await _insertCycle(
        periodic: periodic,
        items: items,
        cycleIndex: ceiling,
        existing: await _existingKeys(e, periodicId),
        skipped: await PeriodicSkips.loadKeys(e, periodicId),
        from: day,
        executor: e,
      );
      await _pruneAfterCycle(e, periodicId, ceiling);
      return inserted;
    }

    if (executor != null) return action(executor);
    final db = await _db;
    return db.transaction<int>(action);
  }

  /// 该轮是否「有实例且全部完成」（与 CycleCounter 的完结口径一致）
  Future<bool> _isCycleFullyCompleted(
    DatabaseExecutor e,
    int periodicId,
    int cycleIndex,
  ) async {
    final rows = await e.rawQuery(
      'SELECT COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done '
      'FROM tasks WHERE periodic_id = ? AND cycle_index = ?',
      <Object?>[periodicId, cycleIndex],
    );
    final total = (rows.first['total'] as num?)?.toInt() ?? 0;
    final done = (rows.first['done'] as num?)?.toInt() ?? 0;
    return total > 0 && done == total;
  }

  /// 该周期已有实例的 (轮次, 完成态)
  Future<List<RoundInstance>> _loadInstances(
    DatabaseExecutor e,
    int periodicId,
  ) async {
    final rows = await e.query(
      'tasks',
      columns: <String>['cycle_index', 'is_completed'],
      where: 'periodic_id = ? AND cycle_index IS NOT NULL',
      whereArgs: <Object?>[periodicId],
    );
    return <RoundInstance>[
      for (final r in rows)
        RoundInstance(
          (r['cycle_index'] as num).toInt(),
          isCompleted: ((r['is_completed'] as num?)?.toInt() ?? 0) == 1,
        ),
    ];
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

  Future<List<PeriodicItem>> _loadItems(DatabaseExecutor e, int periodicId) async {
    final rows = await e.query(
      'periodic_items',
      where: 'periodic_id = ?',
      whereArgs: <Object?>[periodicId],
      orderBy: 'day_offset ASC, sort_order ASC, id ASC',
    );
    return rows.map(PeriodicItem.fromMap).toList(growable: false);
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
}
