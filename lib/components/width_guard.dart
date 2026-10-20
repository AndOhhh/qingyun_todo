import 'package:flutter/cupertino.dart';

/// 宽度守卫：父级可用宽度为 0 时先渲染空占位，不构建 [child]。
///
/// 为什么需要它：视图首帧的尺寸尚未测量时（引擎日志 `D/FlutterRenderer:
/// Width is zero. 0,0`），滚动视图会把 `maxWidth = 0` 传给子级。绝大多数组件能
/// 容忍，但 `CupertinoSlidingSegmentedControl` 会按
/// `(maxWidth - 分隔线总宽) / 段数` 计算段宽并构造 tight 约束，得到**负宽度**
/// （debug 下 `BoxConstraints has a negative minimum width` + 一屏红色错误）。
///
/// 该异常只影响预热帧、下一帧即自愈，但会污染日志并掩盖真实错误；用本组件在
/// 宽度未知时跳过构建即可（统计页范围分段控件即为此类受害者）。
class WidthGuard extends StatelessWidget {
  final Widget child;

  /// 小于该宽度视为「尺寸未就绪」。取 1 是因为分段控件内部会做减法，
  /// 任何 `< 分隔线总宽` 的宽度都可能算出负值。
  final double minWidth;

  const WidthGuard({super.key, required this.child, this.minWidth = 1});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < minWidth
          ? const SizedBox.shrink()
          : child,
    );
  }
}
