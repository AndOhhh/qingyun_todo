import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_priority.dart';

/// 优先级四段选择器（无 / 低 / 中 / 高）。
///
/// 视觉（N18）：浅灰胶囊轨道 + 每段独立配色 —— 选中段用该优先级的**淡色底 +
/// 同色描边 + 同色文字**（无=蓝、低=灰、中=橙、高=红），未选中段只留一个淡色圆点。
/// 相比系统分段控件：① 四档颜色语义一眼可辨（不再全部变成同一块蓝色）；
/// ② 选中态是「淡色胶囊」而非实心块，与统计页/底部 Tab 的胶囊语言一致；
/// ③ 段与段等宽，点击热区更大。
class PriorityPicker extends StatelessWidget {
  final TodoPriority value;
  final ValueChanged<TodoPriority> onChanged;

  const PriorityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          for (final priority in TodoPriority.values)
            Expanded(
              child: _PrioritySegment(
                priority: priority,
                selected: priority == value,
                onTap: () => onChanged(priority),
              ),
            ),
        ],
      ),
    );
  }
}

class _PrioritySegment extends StatelessWidget {
  final TodoPriority priority;
  final bool selected;
  final VoidCallback onTap;

  const _PrioritySegment({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = priority.color;
    return Semantics(
      button: true,
      selected: selected,
      label: '${priority.label}优先级',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: selected
                ? Border.all(color: color.withValues(alpha: 0.45), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: selected ? color : color.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                priority.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : const Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
