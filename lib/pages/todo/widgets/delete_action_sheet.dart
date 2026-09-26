import 'package:flutter/cupertino.dart';

import 'package:qingyun_todo/models/periodic.dart';
import 'package:qingyun_todo/models/todo.dart';
import 'package:qingyun_todo/utils/date_util.dart';

/// 周期实例的三级删除范围（Q9 / docs/07 B3-3）
enum PeriodicDeleteScope {
  /// 只删这一次（默认）
  thisOnce,

  /// 删该周期项的未来实例
  futureOfItem,

  /// 删整个周期
  wholePeriodic,
}

/// 三级删除动作表。
///
/// 与「标记完成」完全区分（Q5）：红色危险样式 + 明确的条数说明。
/// 常规待办不走这里，而是走简单的二次确认弹窗。
Future<PeriodicDeleteScope?> showPeriodicDeleteSheet(
  BuildContext context, {
  required Todo task,
  required int futureCount,
  required PeriodicDeleteResult periodicPreview,
}) {
  return showCupertinoModalPopup<PeriodicDeleteScope>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('删除周期待办'),
      message: Text(
        '「${task.title}」 · ${DateUtil.humanDate(task.remindDate)}\n'
        '来自周期·${task.periodicNameSnapshot ?? '未知'}',
        style: const TextStyle(height: 1.45),
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          onPressed: () =>
              Navigator.of(ctx).pop(PeriodicDeleteScope.thisOnce),
          child: const Text('只删这一次', style: TextStyle(fontSize: 17)),
        ),
        CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () =>
              Navigator.of(ctx).pop(PeriodicDeleteScope.futureOfItem),
          child: _TwoLineAction(
            title: '删除该事项的未来待办',
            subtitle: futureCount <= 1
                ? '仅这一次，没有更多未来待办'
                : '共 $futureCount 条未完成（已完成的不动）',
          ),
        ),
        CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () =>
              Navigator.of(ctx).pop(PeriodicDeleteScope.wholePeriodic),
          child: _TwoLineAction(
            title: '删除整个周期',
            subtitle: '删 ${periodicPreview.removedPending} 条未完成 · '
                '保留 ${periodicPreview.keptCompleted} 条已完成',
          ),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('取消'),
      ),
    ),
  );
}

class _TwoLineAction extends StatelessWidget {
  final String title;
  final String subtitle;

  const _TwoLineAction({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(title, style: const TextStyle(fontSize: 17)),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
        ),
      ],
    );
  }
}
