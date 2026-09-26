import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qingyun_todo/components/confirm_dialog.dart';
import 'package:qingyun_todo/constants/routes.dart';
import 'package:qingyun_todo/logic/app_actions.dart';
import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/periodic_item.dart';
import 'package:qingyun_todo/stores/db_providers.dart';
import 'package:qingyun_todo/stores/invalidation.dart';

/// 周期 / 周期项写操作的统一入口（与 `todo_actions.dart` 对称）。
///
/// 删除周期为**条件删除**（Q5 / docs/02 §7.3）：未完成实例物理删除，
/// 已完成实例断开关联后保留为孤儿历史记录，并优先引导用户改用「暂停」。

/// 打开周期新增 / 编辑页
Future<dynamic> openPeriodicEdit(BuildContext context, {int? periodicId}) =>
    Navigator.of(context).pushNamed(
      RouteConstants.periodicEditPath(id: periodicId),
    );

/// 打开周期详情页（周期项管理）
Future<dynamic> openPeriodicDetail(BuildContext context, int periodicId) =>
    Navigator.of(context).pushNamed(
      RouteConstants.periodicDetailPath(periodicId),
    );

/// 打开周期项新增 / 编辑页
Future<dynamic> openPeriodicItemEdit(
  BuildContext context, {
  int? itemId,
  int? periodicId,
  int dayOffset = 0,
}) =>
    Navigator.of(context).pushNamed(
      RouteConstants.periodicItemEditPath(
        id: itemId,
        periodicId: periodicId,
        dayOffset: dayOffset,
      ),
    );

/// 删除整个周期（C6-2 / C6-3）：确认文案含「删 N 条未完成 / 保留 M 条已完成」，
/// 并提供「暂停并保留」这条更温和的退路。
Future<void> requestDeletePeriodic(
  BuildContext context, {
  required int periodicId,
  required String periodicName,
  PeriodicDeleteResult? preview,
  ProviderContainer? container,
  ScaffoldMessengerState? messenger,
  VoidCallback? onDeleted,
}) async {
  final scope = container ?? ProviderScope.containerOf(context, listen: false);
  final bar = messenger ?? ScaffoldMessenger.maybeOf(context);
  final result = preview ??
      await scope.read(periodicRepositoryProvider).previewDelete(periodicId);
  if (!context.mounted) return;

  final choice = await showActionDialog(
    context,
    title: '删除周期',
    content: result.describe(periodicName),
    actions: const <DialogAction>[
      DialogAction('取消'),
      DialogAction('暂停并保留'),
      DialogAction('删除', isDestructive: true),
    ],
  );
  if (choice == null || choice == 0 || !context.mounted) return;

  // 只想停止提醒 → 引导到「暂停」（保留全部已有待办）
  if (choice == 1) {
    try {
      await scope.read(periodicRepositoryProvider).setActive(periodicId, false);
      invalidateAfterPeriodicWrite(scope.invalidate);
      if (context.mounted) {
        showFeedback(context, '已暂停「$periodicName」，待办全部保留');
      }
    } catch (error) {
      if (context.mounted) await showActionError(context, error);
    }
    return;
  }

  try {
    final deleted =
        await scope.read(periodicRepositoryProvider).deleteById(periodicId);
    invalidateAfterPeriodicWrite(scope.invalidate);
    onDeleted?.call();
    _showBar(
      bar,
      '已删除周期「$periodicName」，保留 ${deleted.keptCompleted} 条已完成记录',
    );
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
  }
}

/// 暂停 / 启用周期（C6-1）
Future<void> togglePeriodicActive(
  BuildContext context,
  WidgetRef ref,
  Periodic periodic,
) async {
  try {
    await ref
        .read(periodicRepositoryProvider)
        .setActive(periodic.id!, !periodic.isActive);
    invalidateAfterPeriodicWrite(ref.invalidate);
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
  }
}

/// 删除周期项（C3-6）：条件删除，确认文案含「删 N 条 / 保留 M 条」
Future<void> requestDeletePeriodicItem(
  BuildContext context,
  WidgetRef ref,
  PeriodicItem item, {
  VoidCallback? onDeleted,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final ItemDeleteResult preview;
  try {
    preview = await container
        .read(periodicItemRepositoryProvider)
        .previewDelete(item.id!);
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
    return;
  }
  if (!context.mounted) return;

  final confirmed = await showConfirmDialog(
    context,
    title: '删除事项',
    content: '删除「${item.title}」将移除 ${preview.removedPending} 条未完成待办；'
        '已完成的 ${preview.keptCompleted} 条会作为历史记录保留。是否继续？',
    confirmText: '删除',
    isDestructive: true,
  );
  if (!confirmed || !context.mounted) return;

  try {
    final result =
        await container.read(periodicItemRepositoryProvider).deleteById(item.id!);
    invalidateAfterPeriodicWrite(container.invalidate);
    onDeleted?.call();
    if (context.mounted) {
      showFeedback(
        context,
        '已删除事项「${item.title}」'
        '${result.keptCompleted > 0 ? '，保留 ${result.keptCompleted} 条已完成记录' : ''}',
      );
    }
  } catch (error) {
    if (context.mounted) await showActionError(context, error);
  }
}

/// 轻提示 SnackBar（与 `todo_actions.dart` 中的撤销条样式一致）
void _showBar(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 3),
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
