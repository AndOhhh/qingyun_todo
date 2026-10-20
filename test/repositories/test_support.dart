import 'package:qingyun_todo/repositories/periodic_completion.dart';
import 'package:qingyun_todo/repositories/periodic_generator.dart';
import 'package:qingyun_todo/repositories/periodic_item_repository.dart';
import 'package:qingyun_todo/repositories/periodic_repository.dart';
import 'package:qingyun_todo/repositories/task_repository.dart';
import 'package:qingyun_todo/utils/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用 `sqflite_common_ffi` 建**内存库**直测 Repository（docs/04 §7：真库直测，
/// 不经 provider，无需真机）。每个测试用例独立一套，互不污染。
///
/// [noIsolate] 为 true 时使用 `databaseFactoryFfiNoIsolate`：
/// 默认的 `databaseFactoryFfi` 把数据库跑在**独立 isolate** 上，其完成事件
/// 不是 microtask，在 `testWidgets` 的 fake-async 环境里永远不会到达，
/// 会让页面停在 loading 态。Widget 测试必须用同 isolate 版本。
class TestStore {
  TestStore._(this.db) {
    generator = PeriodicGenerator(db);
    completion = PeriodicCompletion(db, generator);
    tasks = TaskRepository(db, completion: completion);
    periodics = PeriodicRepository(
      db,
      generator: generator,
      completion: completion,
    );
    items = PeriodicItemRepository(db, generator: generator);
  }

  final DbHelper db;
  late final PeriodicGenerator generator;
  late final PeriodicCompletion completion;
  late final TaskRepository tasks;
  late final PeriodicRepository periodics;
  late final PeriodicItemRepository items;

  static Future<TestStore> create({bool noIsolate = false}) async {
    sqfliteFfiInit();
    final db = DbHelper(
      factory: noIsolate ? databaseFactoryFfiNoIsolate : databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await db.database; // 触发建表
    return TestStore._(db);
  }

  Future<void> dispose() => db.close();
}
