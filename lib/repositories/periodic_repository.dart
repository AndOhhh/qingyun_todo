import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/repositories/periodic_completion.dart';
import 'package:qingyun_todo/repositories/periodic_item_repository.dart';
import 'package:qingyun_todo/repositories/periodic_generator.dart';
import 'package:qingyun_todo/utils/app_exception.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 周期配置 DAO（docs/04 §4.2）。
///
/// 删除周期为**条件删除**（Q5 / docs/02 §7.3）：未完成实例物理删除，
/// 已完成实例断开关联后保留为孤儿历史记录，周期项模板级联删除。
class PeriodicRepository {
  PeriodicRepository(
    this._dbHelper, {
    required this.generator,
    required this.completion,
  });

  final DbHelper _dbHelper;
  final PeriodicGenerator generator;
  final PeriodicCompletion completion;

  Future<Database> get _db => _dbHelper.database;

  // ---------------------------------------------------------------- 写入

  /// 新增周期（事务：周期 + 初始周期项 + 首次生成实例）
  Future<int> insert(
    Periodic periodic, {
    List<PeriodicItem> items = const <PeriodicItem>[],
  }) async {
    validateForSave(periodic);
    final rule = periodic.rule;
    for (final item in items) {
      PeriodicItemRepository.validateDayOffset(
        item.dayOffset,
        rule,
        title: item.title,
      );
    }
    final db = await _db;
    return db.transaction<int>((txn) async {
      final now = DateTime.now();
      final id = await txn.insert(
        Periodic.table,
        periodic.copyWith(createdAt: now, updatedAt: now).toMap(),
      );
      for (final item in items) {
        await txn.insert(
          PeriodicItem.table,
          item
              .copyWith(periodicId: id, createdAt: now, updatedAt: now)
              .toMap(),
        );
      }
      await generator.regenerateAndSync(id, executor: txn);
      return id;
    });
  }

  /// 更新周期规则。
  ///
  /// - **Q12**：缩短周期导致已有周期项越界时抛 [ValidationException]，阻止保存；
  /// - **Q8**：已生成实例的日期不变，新规则只影响尚未生成的轮次。
  Future<int> update(Periodic periodic) async {
    final id = periodic.id;
    if (id == null) {
      throw ArgumentError.notNull('periodic.id（update 必须携带主键）');
    }
    validateForSave(periodic);
    final conflicts = await validateIntervalChange(periodic);
    if (conflicts.isNotEmpty) {
      throw ValidationException(
        '缩短周期后有 ${conflicts.length} 个事项超出新的周期长度',
        details: conflicts
            .map((i) => '第 ${i.dayOffset + 1} 天的「${i.title}」超出新的周期长度'
                '（${periodic.intervalLabel}一轮最短 ${periodic.minCycleLength} 天）')
            .toList(growable: false),
      );
    }
    final db = await _db;
    return db.transaction<int>((txn) async {
      final affected = await txn.update(
        Periodic.table,
        periodic.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      await generator.regenerateAndSync(id, executor: txn);
      return affected;
    });
  }

  /// 启停周期（FR-14）：暂停后停止生成新实例，已有实例保留；
  /// 重新启用时补生成当前窗口内的实例。
  Future<void> setActive(int id, bool active) async {
    final db = await _db;
    await db.transaction<void>((txn) async {
      await txn.update(
        Periodic.table,
        <String, Object?>{
          'is_active': active ? 1 : 0,
          'updated_at': DateUtil.formatTimestamp(DateTime.now()),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (active) {
        await generator.regenerateAndSync(id, executor: txn);
      }
    });
  }

  /// 保存前校验：名称非空、`interval_value >= 1`、终止日期不早于起始日
  void validateForSave(Periodic periodic) {
    if (periodic.name.trim().isEmpty) {
      throw const ValidationException('请填写周期名称');
    }
    if (periodic.intervalValue < 1) {
      throw const ValidationException('周期数量必须大于 0');
    }
    final end = periodic.endDate;
    if (end != null &&
        DateUtil.dateOnly(end).isBefore(DateUtil.dateOnly(periodic.startDate))) {
      throw const ValidationException('终止日期不能早于起始日期');
    }
  }

  /// **Q12**：返回按新规则会越界的周期项；非空则调用方必须阻止保存（TC-06）
  Future<List<PeriodicItem>> validateIntervalChange(Periodic periodic) async {
    final id = periodic.id;
    if (id == null) return const <PeriodicItem>[];
    final items = await queryItems(id);
    final min = periodic.minCycleLength;
    return items.where((i) => i.dayOffset >= min).toList(growable: false);
  }

  /// 删除前的影响面统计（不执行删除），用于确认弹窗文案（docs/07 C6-2）
  Future<PeriodicDeleteResult> previewDelete(int id) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(CASE WHEN is_completed = 0 THEN 1 ELSE 0 END), 0) AS pending,
             COALESCE(SUM(is_completed), 0) AS done
      FROM tasks WHERE periodic_id = ?
      ''',
      <Object?>[id],
    );
    final row = rows.first;
    return PeriodicDeleteResult(
      removedPending: (row['pending'] as num?)?.toInt() ?? 0,
      keptCompleted: (row['done'] as num?)?.toInt() ?? 0,
    );
  }

  /// 条件删除周期（docs/02 §7.3 两步 SQL，事务内）：
  /// ① 删未完成实例 ② 删周期本体 → 周期项 CASCADE，
  /// 剩余已完成实例的 `periodic_id` / `periodic_item_id` 自动 SET NULL，
  /// `cycle_index` 与 `periodic_name_snapshot` 保留（TC-11）。
  ///
  /// ⚠️ 依赖 `PRAGMA foreign_keys = ON`（[DbHelper] 已在 `onConfigure` 中开启）。
  Future<PeriodicDeleteResult> deleteById(int id) async {
    final db = await _db;
    return db.transaction<PeriodicDeleteResult>((txn) async {
      final removed = await txn.rawDelete(
        'DELETE FROM tasks WHERE periodic_id = ? AND is_completed = 0',
        <Object?>[id],
      );
      final keptRows = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM tasks WHERE periodic_id = ?',
        <Object?>[id],
      );
      final kept = (keptRows.first['c'] as num?)?.toInt() ?? 0;
      await txn.delete(
        Periodic.table,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return PeriodicDeleteResult(removedPending: removed, keptCompleted: kept);
    });
  }

  /// 轮次计数联动（docs/04 §4.2 的 `onInstanceCompleted` / `onInstanceUncompleted`）
  Future<void> onInstanceCompleted(Todo task) =>
      completion.onInstanceCompleted(task);

  Future<void> onInstanceUncompleted(Todo task) =>
      completion.onInstanceUncompleted(task);

  // ---------------------------------------------------------------- 读取

  Future<Periodic?> findById(int id, {DatabaseExecutor? executor}) async {
    final e = executor ?? await _db;
    final rows = await e.query(
      Periodic.table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Periodic.fromMap(rows.first);
  }

  /// 周期列表（C1-5：启用在前，其次按创建时间倒序）
  Future<List<Periodic>> queryAll({bool onlyActive = false}) async {
    final db = await _db;
    final rows = await db.query(
      Periodic.table,
      where: onlyActive ? 'is_active = 1' : null,
      orderBy: 'is_active DESC, created_at DESC, id DESC',
    );
    return rows.map(Periodic.fromMap).toList(growable: false);
  }

  Future<List<PeriodicItem>> queryItems(
    int periodicId, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? await _db;
    final rows = await e.query(
      PeriodicItem.table,
      where: 'periodic_id = ?',
      whereArgs: <Object?>[periodicId],
      orderBy: 'day_offset ASC, sort_order ASC, id ASC',
    );
    return rows.map(PeriodicItem.fromMap).toList(growable: false);
  }

  /// 周期列表页数据：3 条聚合查询组装（周期 + 本轮进度 + 下次提醒）
  Future<List<PeriodicListEntry>> queryListWithProgress() async {
    final db = await _db;
    final periodicRows = await db.query(
      Periodic.table,
      orderBy: 'is_active DESC, created_at DESC, id DESC',
    );
    if (periodicRows.isEmpty) return const <PeriodicListEntry>[];
    final periodics = periodicRows.map(Periodic.fromMap).toList(growable: false);

    // ① 所有 (周期, 轮次) 的进度
    final cycleRows = await db.rawQuery(
      '''
      SELECT periodic_id, cycle_index,
             COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done
      FROM tasks
      WHERE periodic_id IS NOT NULL AND cycle_index IS NOT NULL
      GROUP BY periodic_id, cycle_index
      ''',
    );
    final stats = <int, List<_CycleStat>>{};
    for (final row in cycleRows) {
      final pid = (row['periodic_id'] as num).toInt();
      stats.putIfAbsent(pid, () => <_CycleStat>[]).add(
            _CycleStat(
              cycleIndex: (row['cycle_index'] as num).toInt(),
              total: (row['total'] as num?)?.toInt() ?? 0,
              done: (row['done'] as num?)?.toInt() ?? 0,
            ),
          );
    }

    // ② 每个周期最近一条未完成实例（docs/02 §8.8）
    final nextRows = await db.query(
      Todo.table,
      where: 'periodic_id IS NOT NULL AND is_completed = 0 AND remind_date >= ?',
      whereArgs: <Object?>[DateUtil.formatDate(DateUtil.today())],
      orderBy: 'remind_date ASC, '
          'CASE WHEN remind_time IS NULL THEN 1 ELSE 0 END, remind_time ASC',
    );
    final nextRemind = <int, Todo>{};
    for (final row in nextRows) {
      final task = Todo.fromMap(row);
      nextRemind.putIfAbsent(task.periodicId!, () => task);
    }

    return periodics
        .map(
          (p) => PeriodicListEntry(
            periodic: p,
            currentCycle: _pickCurrentCycle(stats[p.id] ?? const <_CycleStat>[]),
            nextRemind: nextRemind[p.id],
          ),
        )
        .toList(growable: false);
  }

  /// 「当前轮」= 最早一个仍有未完成实例的轮；全部完成则取最后一轮
  static CycleProgress? _pickCurrentCycle(List<_CycleStat> stats) {
    if (stats.isEmpty) return null;
    final sorted = stats.toList()..sort((a, b) => a.cycleIndex.compareTo(b.cycleIndex));
    for (final s in sorted) {
      if (s.done < s.total) {
        return CycleProgress(cycleIndex: s.cycleIndex, done: s.done, total: s.total);
      }
    }
    final last = sorted.last;
    return CycleProgress(cycleIndex: last.cycleIndex, done: last.done, total: last.total);
  }

  /// 本轮进度 `x/y`（docs/02 §8.7）；该周期尚无实例时返回 null
  Future<CycleProgress?> queryCurrentCycleProgress(int id) async {
    final db = await _db;
    final pending = await db.rawQuery(
      '''
      SELECT cycle_index FROM tasks
      WHERE periodic_id = ? AND cycle_index IS NOT NULL AND is_completed = 0
      ORDER BY remind_date ASC LIMIT 1
      ''',
      <Object?>[id],
    );
    int? cycleIndex;
    if (pending.isNotEmpty) {
      cycleIndex = (pending.first['cycle_index'] as num).toInt();
    } else {
      final maxRows = await db.rawQuery(
        'SELECT MAX(cycle_index) AS mx FROM tasks '
        'WHERE periodic_id = ? AND cycle_index IS NOT NULL',
        <Object?>[id],
      );
      final mx = maxRows.first['mx'];
      cycleIndex = mx == null ? null : (mx as num).toInt();
    }
    if (cycleIndex == null) return null;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done '
      'FROM tasks WHERE periodic_id = ? AND cycle_index = ?',
      <Object?>[id, cycleIndex],
    );
    final row = rows.first;
    return CycleProgress(
      cycleIndex: cycleIndex,
      done: (row['done'] as num?)?.toInt() ?? 0,
      total: (row['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// 下一条未完成实例（周期卡片副标题，docs/02 §8.8）
  Future<Todo?> queryNextRemind(int id) async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: 'periodic_id = ? AND is_completed = 0 AND remind_date >= ?',
      whereArgs: <Object?>[id, DateUtil.formatDate(DateUtil.today())],
      orderBy: 'remind_date ASC, '
          'CASE WHEN remind_time IS NULL THEN 1 ELSE 0 END, remind_time ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : Todo.fromMap(rows.first);
  }

  /// 周期详情聚合（周期 + 周期项 + 统计 + 本轮进度 + 下次提醒）；
  /// 周期已不存在时返回 null（页面据此退出详情页）
  Future<PeriodicDetail?> queryDetail(int id) async {
    final db = await _db;
    final periodic = await findById(id);
    if (periodic == null) return null;
    final items = await queryItems(id);
    final statRows = await db.rawQuery(
      'SELECT COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done '
      'FROM tasks WHERE periodic_id = ?',
      <Object?>[id],
    );
    final stat = statRows.first;
    final progress = await queryCurrentCycleProgress(id);
    final next = await queryNextRemind(id);
    return PeriodicDetail(
      periodic: periodic,
      items: items,
      totalInstances: (stat['total'] as num?)?.toInt() ?? 0,
      completedInstances: (stat['done'] as num?)?.toInt() ?? 0,
      currentCycle: progress,
      nextRemind: next,
    );
  }

  /// 孤儿历史记录：来源周期已删除、但仍保留的已完成实例（docs/02 §8.9）
  Future<List<Todo>> queryOrphanPeriodic() async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: "source_type = 'PERIODIC' AND periodic_id IS NULL",
      orderBy: 'remind_date DESC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }
}

/// 轮次进度中间态（仅供 [PeriodicRepository._pickCurrentCycle] 使用）
class _CycleStat {
  final int cycleIndex;
  final int total;
  final int done;

  const _CycleStat({
    required this.cycleIndex,
    required this.total,
    required this.done,
  });
}
