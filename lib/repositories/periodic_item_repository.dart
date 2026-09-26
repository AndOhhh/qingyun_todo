import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/repositories/cycle_counter.dart';
import 'package:qingyun_todo/repositories/periodic_generator.dart';
import 'package:qingyun_todo/repositories/periodic_skips.dart';
import 'package:qingyun_todo/utils/app_exception.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 周期项（模板）DAO（docs/04 §4.3）。
///
/// 改动**不追溯**已生成实例（Q8）：修改模板只影响之后生成的实例。
class PeriodicItemRepository {
  PeriodicItemRepository(this._dbHelper, {required this.generator});

  final DbHelper _dbHelper;
  final PeriodicGenerator generator;

  Future<Database> get _db => _dbHelper.database;

  /// `day_offset` 校验：`0 <= day_offset < minCycleLength`（docs/02 §7.2）。
  ///
  /// MONTH 取 28、YEAR 取 365 作为最短轮长度，避免 2 月 / 平年失效（TC-05）。
  /// 越界抛 [ValidationException]，由 UI 直接展示 [ValidationException.fullMessage]。
  ///
  /// [title] 仅用于让提示文案更明确（周期整体校验时带上事项标题）。
  static void validateDayOffset(
    int dayOffset,
    CycleRule rule, {
    String? title,
  }) {
    final subject = (title == null || title.isEmpty) ? '' : '「$title」';
    if (dayOffset < 0) {
      throw ValidationException('$subject天序不能为负数');
    }
    final min = rule.minCycleLength;
    if (dayOffset >= min) {
      throw ValidationException(
        '$subject安排在「第 ${dayOffset + 1} 天」，超出周期长度',
        details: <String>[
          '${rule.label}一轮最短只有 $min 天，可选范围为第 1 ~ 第 $min 天。',
        ],
      );
    }
  }

  /// 新增周期项：校验天序 → 落库 → 重新生成窗口内实例并校准轮数
  Future<int> insert(PeriodicItem item) async {
    final periodicId = item.periodicId;
    if (periodicId == null) {
      throw ArgumentError.notNull('item.periodicId（周期项必须归属某个周期）');
    }
    final db = await _db;
    return db.transaction<int>((txn) async {
      final rule = await _requireRule(txn, periodicId);
      validateDayOffset(item.dayOffset, rule, title: item.title);
      final now = DateTime.now();
      final id = await txn.insert(
        PeriodicItem.table,
        item.copyWith(createdAt: now, updatedAt: now).toMap(),
      );
      await generator.regenerateAndSync(periodicId, executor: txn);
      return id;
    });
  }

  /// 更新周期项（同 [insert] 的天序校验）；已生成实例保持不变（Q8）
  Future<int> update(PeriodicItem item) async {
    final id = item.id;
    final periodicId = item.periodicId;
    if (id == null) {
      throw ArgumentError.notNull('item.id（update 必须携带主键）');
    }
    if (periodicId == null) {
      throw ArgumentError.notNull('item.periodicId');
    }
    final db = await _db;
    return db.transaction<int>((txn) async {
      final rule = await _requireRule(txn, periodicId);
      validateDayOffset(item.dayOffset, rule, title: item.title);
      final affected = await txn.update(
        PeriodicItem.table,
        item.copyWith(updatedAt: DateTime.now()).toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      await generator.regenerateAndSync(periodicId, executor: txn);
      return affected;
    });
  }

  Future<PeriodicItem?> findById(int id, {DatabaseExecutor? executor}) async {
    final e = executor ?? await _db;
    final rows = await e.query(
      PeriodicItem.table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : PeriodicItem.fromMap(rows.first);
  }

  /// 条件删除（docs/02 §7.3）：
  /// ① 删该项**未完成**实例 ② 删模板行；该项**已完成**实例保留，
  /// `periodic_item_id` 由 `ON DELETE SET NULL` 自动置空（TC-11 同族行为）。
  Future<ItemDeleteResult> deleteById(int id) async {
    final db = await _db;
    return db.transaction<ItemDeleteResult>((txn) async {
      final item = await findById(id, executor: txn);
      if (item == null) {
        return const ItemDeleteResult(removedPending: 0, keptCompleted: 0);
      }
      final removed = await txn.rawDelete(
        'DELETE FROM tasks WHERE periodic_item_id = ? AND is_completed = 0',
        <Object?>[id],
      );
      final keptRows = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM tasks WHERE periodic_item_id = ?',
        <Object?>[id],
      );
      final kept = (keptRows.first['c'] as num?)?.toInt() ?? 0;
      await txn.delete(
        PeriodicItem.table,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      final periodicId = item.periodicId;
      if (periodicId != null) {
        await generator.regenerateAndSync(periodicId, executor: txn);
      }
      return ItemDeleteResult(removedPending: removed, keptCompleted: kept);
    });
  }

  /// 删除确认文案用的前置统计（不执行删除）
  Future<ItemDeleteResult> previewDelete(int id) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(CASE WHEN is_completed = 0 THEN 1 ELSE 0 END), 0) AS pending,
             COALESCE(SUM(is_completed), 0) AS done
      FROM tasks WHERE periodic_item_id = ?
      ''',
      <Object?>[id],
    );
    final row = rows.first;
    return ItemDeleteResult(
      removedPending: (row['pending'] as num?)?.toInt() ?? 0,
      keptCompleted: (row['done'] as num?)?.toInt() ?? 0,
    );
  }

  /// 三级删除语义之二（Q9）：删该周期项的**未来**实例，已完成的一律不动。
  ///
  /// 被删掉的轮次会写入墓碑表，因此这里**不能**再触发生成
  /// （否则刚删的实例会被原样写回），只重算轮数即可。
  Future<int> deleteFutureInstances(
    int id, {
    DateTime? fromDate,
  }) async {
    final db = await _db;
    return db.transaction<int>((txn) async {
      final item = await findById(id, executor: txn);
      final from = DateUtil.formatDate(
        DateUtil.dateOnly(fromDate ?? DateUtil.today()),
      );
      final doomed = await txn.query(
        'tasks',
        columns: <String>['cycle_index'],
        where: 'periodic_item_id = ? AND is_completed = 0 AND remind_date >= ?',
        whereArgs: <Object?>[id, from],
      );
      for (final row in doomed) {
        await PeriodicSkips.record(
          txn,
          itemId: id,
          cycleIndex: (row['cycle_index'] as num?)?.toInt(),
          reason: PeriodicSkips.reasonFutureDeleted,
        );
      }
      final removed = await txn.rawDelete(
        'DELETE FROM tasks WHERE periodic_item_id = ? AND is_completed = 0 '
        'AND remind_date >= ?',
        <Object?>[id, from],
      );
      final periodicId = item?.periodicId;
      if (periodicId != null) {
        await CycleCounter.sync(txn, periodicId);
      }
      return removed;
    });
  }

  /// 某周期下的全部周期项，按 `day_offset, sort_order` 升序
  Future<List<PeriodicItem>> queryByPeriodicId(
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

  /// 某一天的周期项（周期管理页分天分组）
  Future<List<PeriodicItem>> queryByDayOffset(
    int periodicId,
    int dayOffset,
  ) async {
    final db = await _db;
    final rows = await db.query(
      PeriodicItem.table,
      where: 'periodic_id = ? AND day_offset = ?',
      whereArgs: <Object?>[periodicId, dayOffset],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(PeriodicItem.fromMap).toList(growable: false);
  }

  /// 同一天内重排：事务内批量写 `sort_order`
  Future<void> reorder(int periodicId, List<int> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final db = await _db;
    await db.transaction<void>((txn) async {
      final batch = txn.batch();
      final now = DateUtil.formatTimestamp(DateTime.now());
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          PeriodicItem.table,
          <String, Object?>{'sort_order': i, 'updated_at': now},
          where: 'id = ? AND periodic_id = ?',
          whereArgs: <Object?>[orderedIds[i], periodicId],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 该周期项**未来**（含今天）的未完成实例数：三级删除动作表的文案数据
  Future<int> countFutureInstances(int itemId, {DateTime? fromDate}) async {
    final db = await _db;
    final from = DateUtil.formatDate(
      DateUtil.dateOnly(fromDate ?? DateUtil.today()),
    );
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE periodic_item_id = ? '
      'AND is_completed = 0 AND remind_date >= ?',
      <Object?>[itemId, from],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// 该周期项是否已生成过实例（周期项编辑页提示「改模板不影响已生成实例」，C3-5）
  Future<int> countGeneratedInstances(int itemId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE periodic_item_id = ?',
      <Object?>[itemId],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<CycleRule> _requireRule(DatabaseExecutor e, int periodicId) async {
    final rows = await e.query(
      Periodic.table,
      where: 'id = ?',
      whereArgs: <Object?>[periodicId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ValidationException('周期不存在或已被删除（id=$periodicId）');
    }
    return Periodic.fromMap(rows.first).rule;
  }
}
