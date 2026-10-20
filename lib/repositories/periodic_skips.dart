import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/utils/date_util.dart';

/// `periodic_skips` 墓碑表读写（见 `db_helper.dart` 中该表的 DDL 注释）。
///
/// 存在意义：生成引擎以 `(periodic_item_id, cycle_index)` 为幂等键，
/// 实例被**硬删除**后该键随之空出，下一次窗口生成会把用户刚删掉的待办
/// 又写回来。此表让「删除这一次 / 删除未来实例」真正生效。
class PeriodicSkips {
  const PeriodicSkips._();

  static const String table = 'periodic_skips';

  /// 用户主动删除单条实例
  static const String reasonUserDeleted = 'USER_DELETED';

  /// 用户删除某周期项的未来实例
  static const String reasonFutureDeleted = 'FUTURE_DELETED';

  /// 记录一条墓碑；`itemId` / `cycleIndex` 任一为空则忽略（常规待办无需记录）
  static Future<void> record(
    DatabaseExecutor executor, {
    required int? itemId,
    required int? cycleIndex,
    String reason = reasonUserDeleted,
  }) async {
    if (itemId == null || cycleIndex == null) return;
    await executor.insert(
      table,
      <String, Object?>{
        'periodic_item_id': itemId,
        'cycle_index': cycleIndex,
        'reason': reason,
        'created_at': DateUtil.formatTimestamp(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 撤销删除时移除墓碑，使该实例重新回到生成规则管辖（TC-14）
  static Future<void> remove(
    DatabaseExecutor executor, {
    required int? itemId,
    required int? cycleIndex,
  }) async {
    if (itemId == null || cycleIndex == null) return;
    await executor.delete(
      table,
      where: 'periodic_item_id = ? AND cycle_index = ?',
      whereArgs: <Object?>[itemId, cycleIndex],
    );
  }

  /// 某周期下全部墓碑键，形如 `itemId:cycleIndex`（生成时一次性取回）
  static Future<Set<String>> loadKeys(
    DatabaseExecutor executor,
    int periodicId,
  ) async {
    final rows = await executor.rawQuery(
      '''
      SELECT s.periodic_item_id AS item_id, s.cycle_index AS cycle_index
      FROM periodic_skips s
      JOIN periodic_items i ON i.id = s.periodic_item_id
      WHERE i.periodic_id = ?
      ''',
      <Object?>[periodicId],
    );
    return <String>{
      for (final r in rows)
        '${(r['item_id'] as num).toInt()}:${(r['cycle_index'] as num).toInt()}',
    };
  }
}
