import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/repositories/cycle_counter.dart';
import 'package:qingyun_todo/repositories/periodic_generator.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 周期实例「完成 / 取消完成」的联动：轮次完结判定 + `completed_count` 同步（FR-15）。
///
/// 独立成类是为了让 [TaskRepository] 与 `PeriodicRepository` 都能复用，
/// 同时避免两个 Repository 互相依赖形成环。
class PeriodicCompletion {
  PeriodicCompletion(this._dbHelper, this._generator);

  final DbHelper _dbHelper;
  final PeriodicGenerator _generator;

  /// 实例被标记完成：重算轮数，并在生成窗口内补出后续轮次（docs/02 §7.4）
  Future<void> onInstanceCompleted(Todo task, [Transaction? txn]) =>
      _run(task, txn, regenerate: true);

  /// 实例被取消完成：重算轮数（Q13 要求回退 `completed_count`，且不小于 0）
  Future<void> onInstanceUncompleted(Todo task, [Transaction? txn]) =>
      _run(task, txn, regenerate: false);

  Future<void> _run(
    Todo task,
    Transaction? txn, {
    required bool regenerate,
  }) async {
    final periodicId = task.periodicId;
    if (periodicId == null || task.cycleIndex == null) return;

    Future<void> action(DatabaseExecutor e) async {
      final cycleIndex = task.cycleIndex!;
      // 先判定「该轮是否已无未完成实例」，再重算轮数（顺序不影响结果，但便于短路）
      final cycleFinished = regenerate && await _isCycleFinished(e, periodicId, cycleIndex);
      await CycleCounter.sync(e, periodicId);
      if (cycleFinished) {
        // 本轮完结 → 对齐到下一轮（一轮一期：只生成当前轮，FR-15 / TC-08）
        await _generator.generateForPeriodicId(periodicId, executor: e);
      }
    }

    if (txn != null) {
      await action(txn);
      return;
    }
    final db = await _dbHelper.database;
    await db.transaction<void>(action);
  }

  /// 该轮是否已无未完成实例（被手动删除的实例不参与判定，docs/02 §7.4）
  static Future<bool> _isCycleFinished(
    DatabaseExecutor e,
    int periodicId,
    int cycleIndex,
  ) async {
    final rows = await e.rawQuery(
      'SELECT COUNT(*) AS c FROM tasks '
      'WHERE periodic_id = ? AND cycle_index = ? AND is_completed = 0',
      <Object?>[periodicId, cycleIndex],
    );
    return ((rows.first['c'] as num?)?.toInt() ?? 0) == 0;
  }
}
