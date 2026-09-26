import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/color_util.dart';

/// 色带颜色选择：规范色 8 色 + 「跟随优先级」（docs/07 B2-5）。
///
/// `value == null` 表示跟随优先级，落库时 `accent_color` 存 NULL（docs/07 B6-5）。
class AccentColorPicker extends StatelessWidget {
  final String? value;
  final TodoPriority priority;
  final ValueChanged<String?> onChanged;

  const AccentColorPicker({
    super.key,
    required this.value,
    required this.priority,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        _Swatch(
          color: priority.color,
          selected: value == null,
          label: '跟随',
          onTap: () => onChanged(null),
        ),
        for (final swatch in ColorUtil.palette)
          _Swatch(
            color: swatch.color,
            selected: value?.toUpperCase() == swatch.hex.toUpperCase(),
            onTap: () => onChanged(swatch.hex),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final String? label;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: label == null ? 32 : 46,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(label == null ? 16 : 10),
          border: Border.all(
            color: selected ? const Color(0xFF1C1C1E) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: label != null
              ? Text(
                  label!,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: <Shadow>[
                      Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
                    ],
                  ),
                )
              : (selected
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Colors.white)
                  : null),
        ),
      ),
    );
  }
}
