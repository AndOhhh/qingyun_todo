import 'package:flutter/cupertino.dart';

/// 弹窗中的一个动作按钮
class DialogAction {
  final String label;

  /// 红色危险样式
  final bool isDestructive;

  /// 加粗默认样式
  final bool isDefault;

  const DialogAction(
    this.label, {
    this.isDestructive = false,
    this.isDefault = false,
  });
}

/// iOS 风格多动作弹窗，返回被点击动作的下标；点遮罩关闭返回 null。
Future<int?> showActionDialog(
  BuildContext context, {
  required String title,
  String? content,
  required List<DialogAction> actions,
}) {
  return showCupertinoDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: (content == null || content.isEmpty)
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(content, style: const TextStyle(height: 1.4)),
            ),
      actions: <Widget>[
        for (var i = 0; i < actions.length; i++)
          CupertinoDialogAction(
            isDestructiveAction: actions[i].isDestructive,
            isDefaultAction: actions[i].isDefault,
            onPressed: () => Navigator.of(ctx).pop(i),
            child: Text(actions[i].label),
          ),
      ],
    ),
  );
}

/// 二次确认弹窗（docs/07 B3-1）：返回 true 表示用户确认执行
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? content,
  String confirmText = '确定',
  String cancelText = '取消',
  bool isDestructive = false,
}) async {
  final result = await showActionDialog(
    context,
    title: title,
    content: content,
    actions: <DialogAction>[
      DialogAction(cancelText),
      DialogAction(confirmText, isDestructive: isDestructive),
    ],
  );
  return result == 1;
}
