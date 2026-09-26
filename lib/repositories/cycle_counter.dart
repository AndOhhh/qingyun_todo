import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/utils/date_util.dart';

/// 轮次计数（`periodic_configs.completed_count`）的**绝对重算**（FR-15 / Q13）。
///
/// 独立成类，供 `TaskRepository` / `PeriodicCompletion` / `PeriodicGenerator`
/// 复用而不产生循环依赖。
class CycleCounter {
  const CycleCounter._();

  /// 已完结轮数 = **拥有至少 1 条实例、且没有未完成实例**的轮次数量。
  ///
  /// 采用绝对重算而非 docs/04 §4.2 的 `±1` 增减，因为：
  /// - 天然幂等，重复触发不会累加；
  /// - 同时满足 TC-08（完成最后一项 +1）、TC-09（取消完成回退）、
  ///   TC-10（删掉唯一未完成项也算完结，docs/02 §7.4）；
  /// - 被物理删除的实例自然退出判定，符合 Q5「删除同时从分子分母消失」；
  /// - `CHECK (completed_count >= 0)` 永不被突破。
  ///
  /// 必须在事务内调用（含写操作）。返回重算后的值。
  static Future<int> sync(DatabaseExecutor executor, int periodicId) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COUNT(*) AS finished FROM (
        SELECT cycle_index FROM tasks
        WHERE periodic_id = ? AND cycle_index IS NOT NULL
        GROUP BY cycle_index
        HAVING SUM(CASE WHEN is_completed = 0 THEN 1 ELSE 0 END) = 0
      )
      ''',
      <Object?>[periodicId],
    );
    final finished = (rows.first['finished'] as num?)?.toInt() ?? 0;
    await executor.update(
      'periodic_configs',
      <String, Object?>{
        'completed_count': finished,
        'updated_at': DateUtil.formatTimestamp(DateTime.now()),
      },
      where: 'id = ?',
      whereArgs: <Object?>[periodicId],
    );
    return finished;
  }
}
