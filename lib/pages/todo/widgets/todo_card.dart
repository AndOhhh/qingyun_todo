import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/components/todo_tag.dart';
import 'package:qingyun_todo/models/todo.dart';

/// 单条待办卡片：顶部 5px 色带 + 白底 + 勾选圈 + 标题/备注 + 标签行。
///
/// 标签顺序固定（docs/01 §3.1）：`已逾期` → `周期·{名}` → 日期 → 提醒时间。
/// 子任务 `x/y` 标签已按 Q2 决策移除。
///
/// ⚠️ 卡片自身不带外边距，由列表侧用 `Padding` 控制间距。
/// 删除入口在编辑页底部红色按钮（2026-10-05 起移除左滑删除手势）。
class TodoCard extends StatelessWidget {
  final Todo todo;

  /// 点击左侧圆圈：切换完成状态（绿色、无需确认、可逆）
  final ValueChanged<int> onToggle;

  /// 点击卡片主体：进入编辑页
  final VoidCallback? onTap;

  /// 是否允许点击（如批量选择模式下可关闭）
  final bool dense;

  const TodoCard({
    super.key,
    required this.todo,
    required this.onToggle,
    this.onTap,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = todo.isCompleted;
    final titleColor =
        isDone ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E);
    final noteColor =
        isDone ? const Color(0xFFAEAEB2) : const Color(0xFF636366);
    // 已完成态色带淡化
    final bandColor =
        isDone ? todo.accentColor.withValues(alpha: 0.30) : todo.accentColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bandColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: bandColor.withValues(alpha: isDone ? 0.04 : 0.18),
              blurRadius: 18,
              spreadRadius: -3,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          // 顶部留 5px 形成色带
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              // 顶部圆角 19 = 24-5，与外层同心，保证色带均匀 5px
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(19),
                topRight: Radius.circular(19),
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            padding: EdgeInsets.fromLTRB(16, dense ? 10 : 12, 16, dense ? 12 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _buildCheckbox(isDone),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildTitle(isDone, titleColor),
                      if (todo.remark != null && todo.remark!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 4),
                        Text(
                          todo.remark!,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            letterSpacing: -0.1,
                            color: noteColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildTags(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 勾选按钮（缩放切换动画）：绿色 = 完成，与红色删除动作在视觉与手势上完全区分（Q5）
  Widget _buildCheckbox(bool isDone) {
    return GestureDetector(
      onTap: () => onToggle(todo.id!),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Icon(
            isDone
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
            key: ValueKey<bool>(isDone),
            size: 24,
            color: isDone ? const Color(0xFF34C759) : const Color(0xFFC7C7CC),
          ),
        ),
      ),
    );
  }

  /// 标题（完成后置灰 + 删除线）
  Widget _buildTitle(bool isDone, Color color) {
    return Text(
      todo.title,
      style: TextStyle(
        fontSize: 16,
        height: 1.25,
        letterSpacing: -0.2,
        fontWeight: isDone ? FontWeight.w400 : FontWeight.w700,
        color: color,
        decoration: isDone ? TextDecoration.lineThrough : null,
        decorationColor: const Color(0xFF8E8E93),
        decorationThickness: 1.5,
      ),
    );
  }

  /// 标签行：逾期 / 周期·{名} / 日期 / 提醒时间
  Widget _buildTags() {
    final periodicLabel = todo.periodicTagLabel;
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: <Widget>[
        if (todo.isOverdue)
          const TodoTag(text: '已逾期', color: Color(0xFFFF3B30)),
        if (periodicLabel != null)
          TodoTag(
            text: periodicLabel,
            icon: CupertinoIcons.refresh,
            color: const Color(0xFFFF9500),
          ),
        TodoTag(
          text: todo.dueDateLabel,
          icon: CupertinoIcons.calendar,
          color: const Color(0xFF636366),
        ),
        if (todo.remindTime != null)
          TodoTag(
            text: todo.remindTime!,
            icon: CupertinoIcons.clock,
            color: const Color(0xFF007AFF),
          ),
      ],
    );
  }
}
