import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/models/cycle_rule.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/stores/db_providers.dart';

/// 周期页读数据 provider（docs/07 §A.1）

/// 周期列表：周期 + 本轮进度 + 下次提醒
final FutureProvider<List<PeriodicListEntry>> periodicListProvider =
    FutureProvider<List<PeriodicListEntry>>(
  (ref) => ref.watch(periodicRepositoryProvider).queryListWithProgress(),
);

/// 周期详情：周期 + 周期项（按天序）+ 统计 + 本轮进度 + 下次提醒
final FutureProviderFamily<PeriodicDetail?, int> periodicDetailProvider =
    FutureProvider.family<PeriodicDetail?, int>(
  (ref, id) => ref.watch(periodicRepositoryProvider).queryDetail(id),
);

/// 单个周期项（周期项编辑页）
final FutureProviderFamily<PeriodicItem?, int> periodicItemProvider =
    FutureProvider.family<PeriodicItem?, int>(
  (ref, id) => ref.watch(periodicItemRepositoryProvider).findById(id),
);

/// 未来 3 轮日期预览（C2-5）：与生成引擎**共用同一套** [CycleRule]，
/// 保证「所见即所得」——预览出来的日期就是将要生成的日期。
final ProviderFamily<List<CyclePreview>, CycleRule> cyclePreviewProvider =
    Provider.family<List<CyclePreview>, CycleRule>(
  (ref, rule) => rule.preview(cycles: 3),
);

/// 某周期已生成的全部实例（详情页「近期实例」区）
final FutureProviderFamily<List<Todo>, int> periodicInstancesProvider =
    FutureProvider.family<List<Todo>, int>(
  (ref, id) => ref.watch(taskRepositoryProvider).queryByPeriodicId(id),
);

/// 某周期项已生成的实例条数（C3-5：提示「改模板不影响已生成实例」）
final FutureProviderFamily<int, int> periodicItemInstanceCountProvider =
    FutureProvider.family<int, int>(
  (ref, id) =>
      ref.watch(periodicItemRepositoryProvider).countGeneratedInstances(id),
);
