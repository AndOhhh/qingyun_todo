import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/confirm_dialog.dart';
import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/logic/app_actions.dart';
import 'package:qingyun_todo/logic/periodic_actions.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/pages/todo/widgets/delete_action_sheet.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/stores/invalidation.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 待办写操作的**统一入口**：写库 → 按失效矩阵刷新 → UI 反馈。
///
/// 页面只调用这里的函数，不直接碰 Repository，也不手写 `invalidate`
/// （docs/07 §A.1 明确禁止零散 invalidate）。
///
/// 删除与完成在数据、交互、文案、统计口径上全部区分（Q5）：
/// | 维度 | 标记完成 | 删除 |
/// | 手势 | 点圆圈 | 左滑露出红色垃圾桶 |
/// | 确认 | 无，可逆 | 二次确认 + 5 秒撤销 |
/// | 数据 | 保留，写 completed_at | 物理移除 |
/// | 统计 | 计入分母与分子 | 从分母与分子同时消失 |

/// 打开待办编辑页；[taskId] 为空表示新增
Future<void> openTodoEdit(BuildContext context, {int? taskId}) {
  return Navigator.of(context).pushNamed(
    RouteConstants.todoEditPath(id: taskId),
  );
}

/// 勾选 / 取消勾选（绿色圆圈，无需确认、可逆）
Future<void> toggleTodoComplete(
  BuildContext context,
  WidgetRef ref,
  Todo task,
) async {
  final target = !task.isCompleted;
  try {
    await ref.read(taskRepositoryProvider).toggleComplete(task.id!, to: target);
    invalidateAfterTaskWrite(ref.invalidate, periodicId: task.periodicId);
    await HapticFeedback.lightImpact();
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
  }
}

/// 删除待办：常规待办走二次确认；周期实例走三级删除动作表（Q9 / B3-3）。
///
/// [onDeleted] 用于编辑页在删除成功后自行退出页面。
Future<void> requestDeleteTodo(
  BuildContext context,
  WidgetRef ref,
  Todo task, {
  VoidCallback? onDeleted,
}) async {
  // 提前抓取容器与 SnackBar 宿主：删除后页面可能已被 pop，
  // 而撤销回调要在 5 秒后仍然可用
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (task.isPeriodic && task.periodicId != null && task.periodicItemId != null) {
    await _deletePeriodicInstance(
      context,
      task,
      container: container,
      messenger: messenger,
      onDeleted: onDeleted,
    );
    return;
  }

  final confirmed = await showConfirmDialog(
    context,
    title: '删除待办',
    content: '删除后将从列表和统计中永久移除，这与「标记完成」不同。是否继续？',
    confirmText: '删除',
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await _runDelete(
    context,
    container: container,
    messenger: messenger,
    message: '已删除「${task.title}」',
    onDeleted: onDeleted,
    action: () async {
      final snapshot =
          await container.read(taskRepositoryProvider).deleteById(task.id!);
      return snapshot == null ? const <Todo>[] : <Todo>[snapshot];
    },
  );
}

Future<void> _deletePeriodicInstance(
  BuildContext context,
  Todo task, {
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
  VoidCallback? onDeleted,
}) async {
  final periodicId = task.periodicId!;
  final itemId = task.periodicItemId!;

  // 先算影响面再展示（docs/07 C6-2）
  final PeriodicDeleteResult preview;
  final int futureCount;
  try {
    preview = await container
        .read(periodicRepositoryProvider)
        .previewDelete(periodicId);
    futureCount = await container
        .read(periodicItemRepositoryProvider)
        .countFutureInstances(itemId);
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
    return;
  }
  if (!context.mounted) return;

  final scope = await showPeriodicDeleteSheet(
    context,
    task: task,
    futureCount: futureCount,
    periodicPreview: preview,
  );
  if (scope == null || !context.mounted) return;

  switch (scope) {
    case PeriodicDeleteScope.thisOnce:
      await _runDelete(
        context,
        container: container,
        messenger: messenger,
        periodicId: periodicId,
        message: '已删除这一次（${DateUtil.humanDate(task.remindDate)}）',
        onDeleted: onDeleted,
        action: () async {
          final snapshot =
              await container.read(taskRepositoryProvider).deleteById(task.id!);
          return snapshot == null ? const <Todo>[] : <Todo>[snapshot];
        },
      );

    case PeriodicDeleteScope.futureOfItem:
      final ok = await showConfirmDialog(
        context,
        title: '删除未来待办',
        content: futureCount <= 1
            ? '该事项没有其他未来待办，只会删除这一次。是否继续？'
            : '将删除「${task.title}」从今天起共 $futureCount 条未完成待办；'
                '已完成的记录保留为历史。是否继续？',
        confirmText: '删除',
        isDestructive: true,
      );
      if (!ok || !context.mounted) return;
      await _runDelete(
        context,
        container: container,
        messenger: messenger,
        // 批量删除未来实例不做逐条撤销：涉及多条记录与墓碑，撤销语义不清晰
        undoable: false,
        invalidatePeriodic: true,
        message: '已删除 $futureCount 条未来待办',
        onDeleted: onDeleted,
        action: () async {
          await container
              .read(periodicItemRepositoryProvider)
              .deleteFutureInstances(itemId);
          return const <Todo>[];
        },
      );

    case PeriodicDeleteScope.wholePeriodic:
      await requestDeletePeriodic(
        context,
        periodicId: periodicId,
        periodicName: task.periodicNameSnapshot ?? '该周期',
        preview: preview,
        container: container,
        messenger: messenger,
        onDeleted: onDeleted,
      );
  }
}

/// 执行删除 → 刷新 → 提示（[undoable] 时带 5 秒撤销）
Future<void> _runDelete(
  BuildContext context, {
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
  required String message,
  required Future<List<Todo>> Function() action,
  int? periodicId,
  bool invalidatePeriodic = false,
  bool undoable = true,
  VoidCallback? onDeleted,
}) async {
  try {
    final snapshots = await action();
    if (invalidatePeriodic) {
      invalidateAfterPeriodicWrite(container.invalidate);
    } else {
      invalidateAfterTaskWrite(container.invalidate, periodicId: periodicId);
    }
    onDeleted?.call();
    if (undoable && snapshots.isNotEmpty) {
      _showUndoBar(container, messenger, snapshots, message);
    } else {
      _showBar(messenger, message);
    }
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
  }
}

void _showBar(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(
        message,
        style: const TextStyle(fontSize: 13, color: Colors.white),
      ),
    ),
  );
}

void _showUndoBar(
  ProviderContainer container,
  ScaffoldMessengerState? messenger,
  List<Todo> snapshots,
  String message,
) {
  messenger?.showSnackBar(
    SnackBar(
      // B3-2：5 秒撤销窗口
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Text(
        message,
        style: const TextStyle(fontSize: 13, color: Colors.white),
      ),
      action: SnackBarAction(
        label: '撤销',
        textColor: const Color(0xFF0A84FF),
        onPressed: () async {
          try {
            final repo = container.read(taskRepositoryProvider);
            // 逆序恢复，保持原有相对顺序（TC-14：id / completed_at / sort_order 一致）
            for (final snapshot in snapshots.reversed) {
              await repo.restore(snapshot);
            }
            invalidateAfterTaskWrite(
              container.invalidate,
              periodicId: snapshots.first.periodicId,
            );
          } catch (error) {
            debugPrint('[undo] 恢复失败：$error');
          }
        },
      ),
    ),
  );
}
