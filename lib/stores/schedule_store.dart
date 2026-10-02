import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/models/todo_groups.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 日程页读数据 provider。
///
/// family 的键统一用字符串（`YYYY-MM` / `YYYY-MM-DD`），避免自定义 key 类
/// 还要维护 `==` / `hashCode`。

/// 某月的月历标记：`{YYYY-MM-DD: DayMarkers}`
final FutureProviderFamily<Map<String, DayMarkers>, String>
    monthMarkersProvider =
    FutureProvider.family<Map<String, DayMarkers>, String>(
  (ref, monthKey) =>
      ref.watch(taskRepositoryProvider).queryMonthMarkers(monthKey),
);

/// 某一天（含常规 + 周期实例）的全部待办。
///
/// 排序（5）：未完成在前（提醒时间 → sort_order），**已完成沉底**，
/// 与待办页「已完成」单独分组的阅读习惯保持一致。
final FutureProviderFamily<List<Todo>, String> dayTasksProvider =
    FutureProvider.family<List<Todo>, String>(
  (ref, dateKey) async {
    final tasks = await ref
        .watch(taskRepositoryProvider)
        .queryByDate(DateUtil.parseDate(dateKey));
    return <Todo>[
      ...tasks.where((t) => !t.isCompleted),
      ...tasks.where((t) => t.isCompleted),
    ];
  },
);
