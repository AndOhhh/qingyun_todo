import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/stores/db_providers.dart';

/// 待办页读数据 provider（docs/07 §A.1：一律 `FutureProvider`，自带三态）。
///
/// 写操作**不建 provider**：页面直接 `ref.read(taskRepositoryProvider).xxx()`，
/// 完成后调用 `stores/invalidation.dart` 的统一失效函数。

/// 待办页主数据源：逾期 / 今天 / 明天 / 后续 / 已完成 五组（含周期实例）
final FutureProvider<TodoGroups> todoGroupsProvider =
    FutureProvider<TodoGroups>(
  (ref) => ref.watch(taskRepositoryProvider).queryGrouped(),
);

/// 今日进度卡：**仅** `remind_date = today`，含周期实例（修 R5）
final FutureProvider<TodayProgressData> todayProgressProvider =
    FutureProvider<TodayProgressData>(
  (ref) => ref.watch(taskRepositoryProvider).countTodayProgress(),
);

/// 单条待办（编辑页 / 删除撤销用）
final FutureProviderFamily<Todo?, int> todoDetailProvider =
    FutureProvider.family<Todo?, int>(
  (ref, id) => ref.watch(taskRepositoryProvider).findById(id),
);
