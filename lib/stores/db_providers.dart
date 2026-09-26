import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'package:qingyun_todo/repositories/periodic_completion.dart';
import 'package:qingyun_todo/repositories/periodic_generator.dart';
import 'package:qingyun_todo/repositories/periodic_item_repository.dart';
import 'package:qingyun_todo/repositories/periodic_repository.dart';
import 'package:qingyun_todo/repositories/task_repository.dart';
import 'package:qingyun_todo/utils/db_helper.dart';

/// 基础设施 provider：DB 单例 + 各 Repository（docs/04 §2 分层）。
///
/// 依赖方向：`pages → stores → repositories → db_helper`，
/// 页面**不得** import `db_helper`，SQL 只允许出现在 `repositories/`。

/// SQLite 单例；测试中用 `overrideWithValue` 注入 ffi 版本
final Provider<DbHelper> dbHelperProvider = Provider<DbHelper>(
  (ref) => DbHelper.instance,
);

/// 库是否就绪（首次 await 会触发建库建表）
final FutureProvider<Database> databaseProvider = FutureProvider<Database>(
  (ref) => ref.watch(dbHelperProvider).database,
);

final Provider<PeriodicGenerator> periodicGeneratorProvider =
    Provider<PeriodicGenerator>(
  (ref) => PeriodicGenerator(ref.watch(dbHelperProvider)),
);

final Provider<PeriodicCompletion> periodicCompletionProvider =
    Provider<PeriodicCompletion>(
  (ref) => PeriodicCompletion(
    ref.watch(dbHelperProvider),
    ref.watch(periodicGeneratorProvider),
  ),
);

final Provider<TaskRepository> taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(
    ref.watch(dbHelperProvider),
    completion: ref.watch(periodicCompletionProvider),
  ),
);

final Provider<PeriodicRepository> periodicRepositoryProvider =
    Provider<PeriodicRepository>(
  (ref) => PeriodicRepository(
    ref.watch(dbHelperProvider),
    generator: ref.watch(periodicGeneratorProvider),
    completion: ref.watch(periodicCompletionProvider),
  ),
);

final Provider<PeriodicItemRepository> periodicItemRepositoryProvider =
    Provider<PeriodicItemRepository>(
  (ref) => PeriodicItemRepository(
    ref.watch(dbHelperProvider),
    generator: ref.watch(periodicGeneratorProvider),
  ),
);
