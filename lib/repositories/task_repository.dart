import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/repositories/cycle_counter.dart';
import 'package:qingyun_todo/repositories/periodic_completion.dart';
import 'package:qingyun_todo/repositories/periodic_round_policy.dart';
import 'package:qingyun_todo/repositories/periodic_skips.dart';
import 'package:qingyun_todo/utils/date_util.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 待办任务 DAO（docs/04 §4.1）。SQL 只允许出现在 `repositories/`（docs/04 §2）。
///
/// **完成 ≠ 删除**（Q5）：
/// - [toggleComplete] 保留记录并写 `completed_at`，计入统计分母与分子；
/// - [deleteById] 物理移除，从列表与**所有统计分母**中同时消失。
class TaskRepository {
  TaskRepository(this._dbHelper, {this.completion});

  final DbHelper _dbHelper;

  /// 周期实例完成 / 取消完成的轮次联动；常规待办为 null 分支，不触发
  final PeriodicCompletion? completion;

  Future<Database> get _db => _dbHelper.database;

  /// 待办页主查询排序（docs/02 §8.1）：未完成在前，日期升序，提醒时间 NULL 最后
  static const String listOrderBy =
      'is_completed ASC, remind_date ASC, '
      'CASE WHEN remind_time IS NULL THEN 1 ELSE 0 END, remind_time ASC, '
      'sort_order ASC';

  // ---------------------------------------------------------------- 写入

  /// 新增常规待办，返回自增 id；`created_at` / `updated_at` 由本层统一写入
  Future<int> insert(Todo task) async {
    final db = await _db;
    final now = DateTime.now();
    return db.insert(
      Todo.table,
      task.copyWith(createdAt: now, updatedAt: now).toMap(),
    );
  }

  /// 显式按原 id 写回 —— **仅供撤销删除使用**（docs/04 §3.2）
  Future<void> insertWithId(Todo task, {DatabaseExecutor? executor}) async {
    final id = task.id;
    if (id == null) {
      throw ArgumentError.notNull('task.id（insertWithId 必须携带原主键）');
    }
    final e = executor ?? await _db;
    await e.insert(
      Todo.table,
      task.toMap(withId: true),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 按 id 全量更新，自动刷新 `updated_at`，保留原 `created_at`
  Future<int> update(Todo task) async {
    final id = task.id;
    if (id == null) {
      throw ArgumentError.notNull('task.id（update 必须携带主键）');
    }
    final db = await _db;
    return db.update(
      Todo.table,
      task.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 物理删除并**返回被删快照**（供 SnackBar 5 秒撤销，docs/07 B3-2）
  Future<Todo?> deleteById(int id) async {
    final db = await _db;
    return db.transaction<Todo?>((txn) async {
      final snapshot = await findById(id, executor: txn);
      if (snapshot == null) return null;
      await txn.delete(Todo.table, where: 'id = ?', whereArgs: <Object?>[id]);
      // 墓碑：防止下一次窗口生成把用户删掉的实例又写回来
      await PeriodicSkips.record(
        txn,
        itemId: snapshot.periodicItemId,
        cycleIndex: snapshot.cycleIndex,
      );
      // 删除唯一未完成项也算该轮完结（docs/02 §7.4），故需重算轮数
      final periodicId = snapshot.periodicId;
      if (periodicId != null) {
        await CycleCounter.sync(txn, periodicId);
      }
      return snapshot;
    });
  }

  /// 批量硬删除（事务内），返回快照列表以支持撤销
  Future<List<Todo>> deleteByIds(List<int> ids) async {
    if (ids.isEmpty) return const <Todo>[];
    final db = await _db;
    return db.transaction<List<Todo>>((txn) async {
      final placeholders = List<String>.filled(ids.length, '?').join(',');
      final rows = await txn.query(
        Todo.table,
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
      final snapshots = rows.map(Todo.fromMap).toList();
      await txn.rawDelete(
        'DELETE FROM tasks WHERE id IN ($placeholders)',
        ids,
      );
      for (final snapshot in snapshots) {
        await PeriodicSkips.record(
          txn,
          itemId: snapshot.periodicItemId,
          cycleIndex: snapshot.cycleIndex,
        );
      }
      final periodicIds = snapshots
          .map((t) => t.periodicId)
          .whereType<int>()
          .toSet();
      for (final pid in periodicIds) {
        await CycleCounter.sync(txn, pid);
      }
      return snapshots;
    });
  }

  /// 撤销删除：按原 id、原 `completed_at`、原 `sort_order` 写回（TC-14）；
  /// 同时移除墓碑，使该实例重新受生成规则管辖
  Future<void> restore(Todo task) async {
    final db = await _db;
    await db.transaction<void>((txn) async {
      await insertWithId(task, executor: txn);
      await PeriodicSkips.remove(
        txn,
        itemId: task.periodicItemId,
        cycleIndex: task.cycleIndex,
      );
      final periodicId = task.periodicId;
      if (periodicId != null) {
        await CycleCounter.sync(txn, periodicId);
      }
    });
  }

  /// 切换完成状态：写 `is_completed` + `completed_at`；
  /// 周期实例在**同一事务**内联动轮次计数与下一轮生成（docs/04 §4.1、Q13）。
  ///
  /// [to] 为空表示取反。
  Future<void> toggleComplete(int id, {bool? to}) async {
    final db = await _db;
    await db.transaction<void>((txn) async {
      final task = await findById(id, executor: txn);
      if (task == null) return;
      final target = to ?? !task.isCompleted;
      if (target == task.isCompleted) return;
      await setCompleted(id, target, executor: txn);

      final hook = completion;
      final updated = task.copyWith(isCompleted: target);
      if (hook != null && updated.isPeriodic && updated.periodicId != null) {
        if (target) {
          await hook.onInstanceCompleted(updated, txn);
        } else {
          await hook.onInstanceUncompleted(updated, txn);
        }
      }
    });
  }

  /// 仅写任务自身的完成字段（不含周期联动）；[executor] 用于复用外层事务
  Future<void> setCompleted(
    int id,
    bool completed, {
    DatabaseExecutor? executor,
  }) async {
    final now = DateUtil.formatTimestamp(DateTime.now());
    final values = <String, Object?>{
      'is_completed': completed ? 1 : 0,
      'completed_at': completed ? now : null,
      'updated_at': now,
    };
    final e = executor ?? await _db;
    await e.update(
      Todo.table,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// 拖拽排序：事务内按给定顺序批量写 `sort_order`（Phase 7）
  Future<void> reorder(List<int> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final db = await _db;
    await db.transaction<void>((txn) async {
      final batch = txn.batch();
      final now = DateUtil.formatTimestamp(DateTime.now());
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(
          Todo.table,
          <String, Object?>{'sort_order': i, 'updated_at': now},
          where: 'id = ?',
          whereArgs: <Object?>[orderedIds[i]],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 标记提醒已发出（Phase 6，`is_notified` 防重复通知）
  Future<void> markNotified(int id) async {
    final db = await _db;
    await db.update(
      Todo.table,
      <String, Object?>{
        'is_notified': 1,
        'updated_at': DateUtil.formatTimestamp(DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ---------------------------------------------------------------- 读取

  Future<Todo?> findById(int id, {DatabaseExecutor? executor}) async {
    final e = executor ?? await _db;
    final rows = await e.query(
      Todo.table,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : Todo.fromMap(rows.first);
  }

  /// 待办页主查询：一次取回全部（含周期实例与孤儿记录），Dart 侧分桶
  Future<List<Todo>> queryAll() async {
    final db = await _db;
    final rows = await db.query(Todo.table, orderBy: listOrderBy);
    return rows.map(Todo.fromMap).toList(growable: false);
  }

  /// 分组结果：逾期 / 今天 / 明天 / 后续 / 已完成（Q10）
  ///
  /// **一轮一期（N13）**：周期实例只展示「本轮」，其余轮次的未完成实例不进入
  /// 待办页（规则与生成引擎共用 [PeriodicRoundPolicy]）。
  Future<TodoGroups> queryGrouped() async =>
      TodoGroups.from(await _visibleOnTodoPage(await queryAll()));

  /// 待办页可见性过滤；库里没有周期实例时零额外查询
  Future<List<Todo>> _visibleOnTodoPage(List<Todo> all) async {
    if (!all.any((task) => task.periodicId != null)) return all;
    final db = await _db;
    final rows = await db.query('periodic_configs');
    final periodics = rows.map(Periodic.fromMap).toList(growable: false);
    return PeriodicRoundPolicy.visibleOnTodoPage(
      tasks: all,
      periodics: periodics,
      today: DateUtil.today(),
    );
  }

  /// 日程页：指定日期的全部待办（docs/02 §8.2）
  Future<List<Todo>> queryByDate(DateTime date) async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: 'remind_date = ?',
      whereArgs: <Object?>[DateUtil.formatDate(date)],
      orderBy: 'CASE WHEN remind_time IS NULL THEN 1 ELSE 0 END, '
          'remind_time ASC, sort_order ASC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }

  /// 日程页月历标记：按月聚合每天的 未完成 / 已完成 条数（FR-16）。
  ///
  /// [monthKey] 形如 `YYYY-MM`；逾期不入库，颜色由 UI 按「日期 < 今天」派生。
  Future<Map<String, DayMarkers>> queryMonthMarkers(String monthKey) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT remind_date,
             COALESCE(SUM(CASE WHEN is_completed = 0 THEN 1 ELSE 0 END), 0) AS pending,
             COALESCE(SUM(is_completed), 0) AS done
      FROM tasks
      WHERE remind_date >= ? AND remind_date <= ?
      GROUP BY remind_date
      ''',
      <Object?>['$monthKey-01', '$monthKey-31'],
    );
    return <String, DayMarkers>{
      for (final row in rows)
        row['remind_date'] as String: DayMarkers(
          pending: (row['pending'] as num?)?.toInt() ?? 0,
          done: (row['done'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  /// 逾期任务：`is_completed = 0 AND remind_date < today`（docs/02 §8.4）
  Future<List<Todo>> queryOverdue() async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: 'is_completed = 0 AND remind_date < ?',
      whereArgs: <Object?>[DateUtil.formatDate(DateUtil.today())],
      orderBy: 'remind_date ASC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }

  /// 某周期下的全部实例（周期详情页用）
  Future<List<Todo>> queryByPeriodicId(
    int periodicId, {
    DatabaseExecutor? executor,
  }) async {
    final e = executor ?? await _db;
    final rows = await e.query(
      Todo.table,
      where: 'periodic_id = ?',
      whereArgs: <Object?>[periodicId],
      orderBy: 'remind_date ASC, remind_time ASC, sort_order ASC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }

  /// 孤儿历史记录：来源周期已删除（docs/02 §8.9）
  Future<List<Todo>> queryOrphanPeriodic() async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: "source_type = 'PERIODIC' AND periodic_id IS NULL",
      orderBy: 'remind_date DESC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }

  /// 今日进度：**仅** `remind_date = today`，含周期实例（docs/02 §8.3，修 R5）
  Future<TodayProgressData> countTodayProgress() async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total, COALESCE(SUM(is_completed), 0) AS done
      FROM tasks WHERE remind_date = ?
      ''',
      <Object?>[DateUtil.formatDate(DateUtil.today())],
    );
    final row = rows.first;
    return TodayProgressData(
      total: (row['total'] as num?)?.toInt() ?? 0,
      done: (row['done'] as num?)?.toInt() ?? 0,
    );
  }

  /// 幂等判断：该 (周期项, 轮次) 的实例是否已存在（唯一索引兜底）
  Future<bool> existsInstance(int itemId, int cycleIndex) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks WHERE periodic_item_id = ? AND cycle_index = ?',
      <Object?>[itemId, cycleIndex],
    );
    return ((rows.first['c'] as num?)?.toInt() ?? 0) > 0;
  }

  /// 需要参与通知排期的任务：未完成且带提醒时间（通知服务 reconcile 用）
  Future<List<Todo>> queryRemindable() async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: 'is_completed = 0 AND remind_time IS NOT NULL',
      orderBy: 'remind_date ASC, remind_time ASC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }

  /// 到点待通知的任务（Phase 6）：`提醒时刻 <= now` 且未完成、未通知过
  Future<List<Todo>> queryDueForNotify(DateTime now) async {
    final db = await _db;
    final rows = await db.query(
      Todo.table,
      where: 'is_completed = 0 AND is_notified = 0 AND remind_time IS NOT NULL '
          "AND (remind_date || ' ' || remind_time) <= ?",
      whereArgs: <Object?>[DateUtil.formatTimestamp(now).substring(0, 16)],
      orderBy: 'remind_date ASC, remind_time ASC',
    );
    return rows.map(Todo.fromMap).toList(growable: false);
  }
}
