import 'package:flutter/material.dart';

import 'package:qingyun_todo/components/confirm_dialog.dart';
import 'package:qingyun_todo/utils/app_exception.dart';

/// 统一的操作失败提示：[ValidationException] 展示业务文案，其余展示通用提示
/// （原始异常只写日志，不把 SQL / 堆栈抛给用户，N25）。
Future<void> showActionError(BuildContext context, Object error) {
  final message =
      error is ValidationException ? error.fullMessage : '操作没有完成，请稍后重试。';
  if (error is! ValidationException) {
    debugPrint('[action] $error');
  }
  return showActionDialog(
    context,
    title: '出错了',
    content: message,
    actions: const <DialogAction>[DialogAction('知道了', isDefault: true)],
  );
}

/// 轻提示（写库成功后的弱反馈）
void showFeedback(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
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
