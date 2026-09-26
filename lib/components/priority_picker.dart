import 'package:flutter/cupertino.dart';

import 'package:qingyun_todo/models/todo_priority.dart';

/// 优先级四段选择器（无 / 低 / 中 / 高，带规范色圆点，docs/07 B2-5）
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
    return CupertinoSegmentedControl<TodoPriority>(
      groupValue: value,
      onValueChanged: onChanged,
      selectedColor: const Color(0xFF007AFF),
      borderColor: const Color(0xFFD1D1D6),
      pressedColor: const Color(0xFF007AFF).withValues(alpha: 0.15),
      padding: const EdgeInsets.all(2),
      children: <TodoPriority, Widget>{
        for (final p in TodoPriority.values)
          p: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: p.color,
                    shape: BoxShape.circle,
                    border: p == TodoPriority.none
                        ? Border.all(color: const Color(0xFFC7C7CC), width: 1)
                        : null,
                  ),
                ),
                const SizedBox(width: 4),
                Text(p.label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      },
    );
  }
}
