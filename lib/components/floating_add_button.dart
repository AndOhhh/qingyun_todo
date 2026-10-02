import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 右下角浮动圆形新增按钮。
///
/// 待办 / 周期 / 日程三个页面统一用它替代导航栏右上角的 `+`：
/// 拇指热区更近，且不与大标题导航栏的收起动画抢位置。
/// 蓝色实心圆 + 白色加号，与白色「今」按钮在颜色上区分主次。
class FloatingAddButton extends StatefulWidget {
  final VoidCallback onPressed;

  /// 无障碍标签（如「新建待办」/「新建周期」）
  final String semanticLabel;

  const FloatingAddButton({
    super.key,
    required this.onPressed,
    required this.semanticLabel,
  });

  @override
  State<FloatingAddButton> createState() => _FloatingAddButtonState();
}

class _FloatingAddButtonState extends State<FloatingAddButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF),
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF007AFF).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              CupertinoIcons.add,
              size: 26,
              color: Colors.white,
              weight: 600,
            ),
          ),
        ),
      ),
    );
  }
}
