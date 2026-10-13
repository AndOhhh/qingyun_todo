import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 右下角浮动圆形新增按钮。
///
/// 待办 / 周期 / 日程三个页面统一用它替代导航栏右上角的 `+`：
/// 拇指热区更近，且不与大标题导航栏的收起动画抢位置。
/// 蓝色实心圆 + 白色加号，与白色「今」按钮在颜色上区分主次。
/// 悬浮按钮距屏幕底部的统一偏移。
///
/// 主页 Scaffold 开启了 `extendBody: true`，各页 Stack 会延伸到屏幕物理底边；
/// 而底部悬浮导航栏外层包了 `SafeArea`，在 iOS 上会被 Home 指示条（约 34pt）
/// 整体抬高。若按钮写死 `bottom` 常量，iOS 上就会躲进导航栏后面被遮挡
/// （Android 底部安全区为 0 时表现正常），两端视觉不一致。
///
/// `extendBody` 开启时 Scaffold 会把导航栏实际高度（含底部安全区）回写进
/// body 的 `MediaQuery.padding.bottom`（框架 _BodyBuilder 行为），
/// 因此以它作为「导航栏顶边」基线：[base] 为无安全区时（安卓基准）按钮的
/// 底部偏移，超出无安全区导航栏高度（8 外边距 + 66 栏高 = 74）的部分即
/// 按钮与导航栏的视觉间距，双端保持一致。
double floatingBottomOffset(BuildContext context, {double base = 96}) {
  // 与 MainPage._buildTabBar 保持一致：8 外边距 + 66 栏高
  const double kNavBarHeightNoInset = 74;
  final double navBarHeight = MediaQuery.paddingOf(context).bottom;
  return navBarHeight + (base - kNavBarHeightNoInset);
}

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
