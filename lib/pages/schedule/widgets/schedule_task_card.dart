import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/components/todo_tag.dart';
import 'package:qingyun_todo/models/todo.dart';

/// 日程页当日安排卡片：左侧色带 + 勾选 + 标题 + 时间 / 周期标签。
///
/// 与待办页 `TodoCard` 的区别：更紧凑、不带投影色带卡片外形，
/// 因为日程页一屏要容纳月历 + 列表；点击主体进入编辑页（复用首页编辑控件）。
class ScheduleTaskCard extends StatelessWidget {
  final Todo task;
  final ValueChanged<int> onToggle;
  final VoidCallback? onTap;

  const ScheduleTaskCard({
    super.key,
    required this.task,
    required this.onToggle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.isCompleted;
    final periodicLabel = task.periodicTagLabel;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 左侧 4px 色带：与待办卡片色带同色
                Container(width: 4, color: task.accentColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    child: Row(
                      children: <Widget>[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onToggle(task.id!),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                isDone
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                key: ValueKey<bool>(isDone),
                                size: 21,
                                color: isDone
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFC7C7CC),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: isDone
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  color: isDone
                                      ? const Color(0xFF8E8E93)
                                      : const Color(0xFF1C1C1E),
                                  decoration: isDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationColor: const Color(0xFF8E8E93),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: <Widget>[
                                  if (task.isOverdue)
                                    const TodoTag(
                                      text: '已逾期',
                                      color: Color(0xFFFF3B30),
                                    ),
                                  if (periodicLabel != null)
                                    TodoTag(
                                      text: periodicLabel,
                                      icon: CupertinoIcons.refresh,
                                      color: const Color(0xFFFF9500),
                                    ),
                                  TodoTag(
                                    text: task.remindTime ?? '全天',
                                    icon: task.remindTime == null
                                        ? CupertinoIcons.sun_max
                                        : CupertinoIcons.clock,
                                    color: task.remindTime == null
                                        ? const Color(0xFF8E8E93)
                                        : const Color(0xFF007AFF),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          size: 13,
                          color: Color(0xFFC7C7CC),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
