import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:qingyun_todo/components/todo_tag.dart';
import 'package:qingyun_todo/models/todo.dart';

/// 单条待办卡片：顶部 accentColor 色带 + 白底 + 勾选 + 标题/备注 + tags
class TodoCard extends StatelessWidget {
  final Todo todo;
  final ValueChanged<String> onToggle;

  const TodoCard({super.key, required this.todo, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final isDone = todo.done;
    final titleColor = isDone
        ? const Color(0xFF8E8E93)
        : const Color(0xFF1C1C1E);
    final noteColor = isDone
        ? const Color(0xFFAEAEB2)
        : const Color(0xFF636366);
    // 已完成态色带淡化
    final bandColor = isDone
        ? todo.accentColor.withValues(alpha: 0.30)
        : todo.accentColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bandColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildCheckbox(isDone),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitle(isDone, titleColor),
                    if (todo.note != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        todo.note!,
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
    );
  }

  /// 勾选按钮（带缩放切换动画）
  Widget _buildCheckbox(bool isDone) {
    return GestureDetector(
      onTap: () => onToggle(todo.id),
      behavior: HitTestBehavior.opaque,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          isDone
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.circle,
          key: ValueKey(isDone),
          size: 24,
          color: isDone
              ? const Color(0xFF34C759)
              : const Color(0xFFC7C7CC),
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

  /// tags 行：逾期 / 周期 / 日期 / 子任务进度
  Widget _buildTags() {
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        if (todo.isOverdue)
          const TodoTag(text: '已逾期', color: Color(0xFFFF3B30)),
        if (todo.isPeriodic)
          const TodoTag(
            text: '周期',
            icon: CupertinoIcons.refresh,
            color: Color(0xFFFF9500),
          ),
        if (todo.dueDate != null)
          TodoTag(
            text: todo.dueDateLabel,
            icon: CupertinoIcons.calendar,
            color: const Color(0xFF636366),
          ),
        if (todo.subTotal > 0)
          TodoTag(
            text: '${todo.subDone}/${todo.subTotal}',
            icon: CupertinoIcons.checkmark_rectangle,
            color: const Color(0xFF007AFF),
          ),
      ],
    );
  }
}
