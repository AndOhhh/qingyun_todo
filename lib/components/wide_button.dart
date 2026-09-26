import 'package:flutter/cupertino.dart';

/// 通栏浅色动作按钮（图标 + 文案）。
///
/// 用于表单页底部的次要动作（暂停 / 启用 / 标记完成）；
/// 危险动作（删除）统一用红色纯文字按钮，二者在视觉上必须分离（Q5）。
class WideButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const WideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 10),
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.12),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
