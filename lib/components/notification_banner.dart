import 'package:flutter/cupertino.dart';

import 'package:qingyun_todo/services/notification_service.dart';

/// 通知能力异常时的可见诊断条。
///
/// 「到点收不到通知」绝大多数源于系统开关 / 精确闹钟权限，而不是代码；
/// 与其让用户盲猜，不如在首屏给出原因与一键修复入口。
class NotificationBanner extends StatelessWidget {
  final NotificationHealth health;
  final VoidCallback onDismiss;

  /// 点击「去开启」：由页面按 blocker 类型执行对应修复动作
  final VoidCallback onFix;

  /// 修复动作完成后回调（重新自检 + 重排）
  final VoidCallback onFixed;

  const NotificationBanner({
    super.key,
    required this.health,
    required this.onDismiss,
    required this.onFix,
    required this.onFixed,
  });

  @override
  Widget build(BuildContext context) {
    final blocker = health.blocker;
    if (blocker == NotificationBlocker.none ||
        blocker == NotificationBlocker.unavailable) {
      return const SizedBox.shrink();
    }
    final denied = blocker == NotificationBlocker.permissionDenied;
    final color = denied ? const Color(0xFFFF3B30) : const Color(0xFFFF9500);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            denied
                ? CupertinoIcons.bell_slash
                : CupertinoIcons.exclamationmark_triangle,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              denied
                  ? '系统通知未开启，到点提醒无法送达通知栏。'
                  : '未授予「精确闹钟」权限，到点提醒可能延迟几分钟。',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: color.withValues(alpha: 0.95),
              ),
            ),
          ),
          const SizedBox(width: 6),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            onPressed: onFix,
            child: Text(
              '去开启',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            onPressed: onDismiss,
            child: Icon(
              CupertinoIcons.xmark,
              size: 14,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
