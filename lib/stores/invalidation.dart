import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/stores/periodic_store.dart';
import 'package:qingyun_todo/stores/todo_store.dart';

/// 失效函数签名。
///
/// `WidgetRef.invalidate` 与 `ProviderContainer.invalidate` 的签名完全一致
/// （都是 `void Function(ProviderOrFamily)`），所以页面内的 `ref.invalidate`
/// 与脱离 Widget 的延迟回调（如 5 秒撤销、页面已 pop）里的 `container.invalidate`
/// 可以共用同一套失效矩阵，不需要重复实现。
typedef InvalidateFn = void Function(ProviderOrFamily provider);

/// **失效矩阵**（docs/07 §A.1）：写操作后必须失效哪些读 provider。
///
/// 本项目最容易踩的 bug 就是漏写 `invalidate` 导致页面显示旧数据，
/// 因此统一收敛到下面三个函数，**禁止在各调用点零散手写 invalidate**。

/// 待办（`tasks`）发生写操作后调用。
///
/// [periodicId] 非空表示该待办是周期实例：轮数与本轮进度会变，
/// 需要连带失效周期列表与该周期详情（TC-08 / TC-09）。
void invalidateAfterTaskWrite(InvalidateFn invalidate, {int? periodicId}) {
  invalidate(todoGroupsProvider);
  invalidate(todayProgressProvider);
  invalidate(todoDetailProvider);
  if (periodicId != null) {
    invalidate(periodicListProvider);
    invalidate(periodicDetailProvider(periodicId));
    invalidate(periodicInstancesProvider(periodicId));
  }
}

/// 周期或周期项发生写操作后调用：待办页与周期页必须同步刷新（docs/07 D4）
void invalidateAfterPeriodicWrite(InvalidateFn invalidate) {
  invalidate(periodicListProvider);
  invalidate(periodicDetailProvider);
  invalidate(periodicItemProvider);
  invalidate(periodicInstancesProvider);
  invalidate(periodicItemInstanceCountProvider);
  invalidate(todoGroupsProvider);
  invalidate(todayProgressProvider);
  invalidate(todoDetailProvider);
}

/// 生成引擎跑过之后调用：只影响待办侧数据
void invalidateAfterGenerate(InvalidateFn invalidate) {
  invalidate(todoGroupsProvider);
  invalidate(todayProgressProvider);
  invalidate(periodicInstancesProvider);
  invalidate(periodicListProvider);
}
