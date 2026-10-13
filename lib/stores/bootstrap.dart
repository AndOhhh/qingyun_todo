import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/routes/index.dart';
import 'package:qingyun_todo/stores/invalidation.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 记录「上一次校准时的日期」，用于跨日校准（docs/07 C4-2）。
///
/// 用日期比对而不是常驻定时器：避免后台每小时唤醒耗电。
final StateProvider<String> lastCalibratedDateProvider = StateProvider<String>(
  (ref) => DateUtil.formatDate(DateUtil.today()),
);

/// App 启动时调用：确保建库完成，并滚动生成窗口内的周期实例。
///
/// **异常不向上抛**（docs/07 C4-6）：生成失败不阻塞 UI，
/// 幂等性保证下一次触发（跨日 / 新建周期 / 完成一轮）可安全重试。
Future<void> bootstrapApp(WidgetRef ref) async {
  try {
    bindNotificationNavigation();
    await ref.read(databaseProvider.future);
    final inserted =
        await ref.read(periodicGeneratorProvider).generateForWindow();
    ref.read(lastCalibratedDateProvider.notifier).state =
        DateUtil.formatDate(DateUtil.today());
    if (inserted > 0) {
      invalidateAfterGenerate(ref.invalidate);
    }
    // FR-19：启动时初始化通知并按当前数据重排（含补发窗口内的到期提醒）
    final notify = ref.read(notificationServiceProvider);
    await notify.init();
    await notify.reconcile();
    await notify.startForegroundWatch();
  } catch (error, stack) {
    debugPrint('[bootstrap] 周期实例生成失败，将在下次触发时重试：$error');
    debugPrintStack(stackTrace: stack);
  }
}

/// 从后台回到前台（`AppLifecycleState.resumed`）时调用：**跨日才重新生成**。
Future<void> recalibrateIfDayChanged(WidgetRef ref) async {
  final today = DateUtil.formatDate(DateUtil.today());
  if (ref.read(lastCalibratedDateProvider) == today) return;
  await bootstrapApp(ref);
}
