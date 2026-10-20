import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:qingyun_todo/models/todo_priority.dart';
import 'package:qingyun_todo/utils/color_util.dart';

/// 色带颜色选择：规范色 8 色。
///
/// 「跟随优先级」不再作为可点选项（N18）：`value == null` 仍表示跟随优先级
/// （落库 `accent_color` 存 NULL，docs/07 B6-5），此时把**与优先级同色的色块**
/// 高亮成默认选中态——用户改优先级时，默认色随之变化；点选任意色块即覆盖为自定义色。
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
    // 未显式选色时按优先级取色，并与色板中的对应色块对齐高亮
    final effective = (value ?? ColorUtil.toHex(priority.color)).toUpperCase();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        for (final swatch in ColorUtil.palette)
          _Swatch(
            color: swatch.color,
            label: swatch.label,
            selected: effective == swatch.hex.toUpperCase(),
            onTap: () => onChanged(swatch.hex),
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xFF1C1C1E) : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 16,
                  color: Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}
