import 'package:flutter/material.dart';

/// 左滑露出的动作按钮定义
class SwipeActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const SwipeActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// 左滑露出动作按钮（**不是**滑走即删，docs/07 B3-1）。
///
/// - 横向拖拽跟手，松手时按「超过一半 / 甩动速度」吸附到展开或收起；
/// - 展开时在卡片上覆盖一层透明拦截层，点击任意处先收起，避免误触发卡片点击；
/// - 竖向滚动不受影响（只响应水平 drag）；
/// - 卡片自身不要带外边距（列表侧用 `Padding` 包裹），否则动作区会高出一截。
class SwipeAction extends StatefulWidget {
  final Widget child;
  final List<SwipeActionItem> actions;
  final double actionWidth;
  final double borderRadius;
  final bool enabled;

  const SwipeAction({
    super.key,
    required this.child,
    required this.actions,
    this.actionWidth = 76,
    this.borderRadius = 24,
    this.enabled = true,
  });

  @override
  State<SwipeAction> createState() => SwipeActionState();
}

class SwipeActionState extends State<SwipeAction>
    with SingleTickerProviderStateMixin {
  // 必须在 initState 中**立即**创建：`late final` 懒初始化会让首次访问发生在
  // dispose()（未滑动过的卡片直接销毁时），此时 element 已 deactivated，
  // AnimationController 内部取 TickerMode 会抛「Looking up a deactivated
  // widget's ancestor is unsafe」。
  late final AnimationController _controller;

  double _offset = 0;
  Animation<double>? _animation;

  double get _maxExtent => widget.actions.length * widget.actionWidth;

  bool get isOpen => _offset < -0.5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _animation?.removeListener(_onAnimationTick);
    _controller.dispose();
    super.dispose();
  }

  /// 收起（供动作执行后调用）
  void close() => _animateTo(0);

  void _animateTo(double target) {
    if ((_offset - target).abs() < 0.5) return;
    _animation?.removeListener(_onAnimationTick);
    _animation = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(_onAnimationTick);
    _controller.forward(from: 0);
  }

  void _onAnimationTick() {
    final value = _animation?.value;
    if (value == null) return;
    setState(() => _offset = value);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _offset = (_offset + details.delta.dx).clamp(-_maxExtent, 0.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = _offset < -_maxExtent / 2 || velocity < -320;
    _animateTo(shouldOpen ? -_maxExtent : 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;

    final revealed = -_offset;
    return Stack(
      children: <Widget>[
        if (revealed > 0.5)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: revealed,
            child: _buildActions(),
          ),
        Transform.translate(
          offset: Offset(_offset, 0),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: widget.child,
          ),
        ),
        // 展开时拦截点击：先收起，不触发卡片自身的点击。
        // 只覆盖卡片可见区域（right: revealed），否则会挡住刚露出的动作按钮。
        if (isOpen)
          Positioned(
            left: 0,
            right: revealed,
            top: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
            ),
          ),
      ],
    );
  }

  Widget _buildActions() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Row(
        children: <Widget>[
          for (final action in widget.actions)
            Expanded(
              child: Material(
                color: action.color,
                child: InkWell(
                  onTap: () {
                    close();
                    action.onTap();
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(action.icon, size: 22, color: Colors.white),
                      const SizedBox(height: 4),
                      Text(
                        action.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
